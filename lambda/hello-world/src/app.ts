import { BskyAgent, AppBskyFeedDefs, AppBskyFeedPost } from '@atproto/api'; // Added AppBskyFeedPost
import {
    ComprehendClient,
    DetectSentimentCommand,
    DetectKeyPhrasesCommand,
    DetectKeyPhrasesCommandInput,
    DetectSentimentCommandInput,
    LanguageCode,
} from '@aws-sdk/client-comprehend';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
    DynamoDBDocumentClient,
    GetCommand,
    PutCommand,
    ScanCommand,
    UpdateCommand,
    QueryCommand,
} from '@aws-sdk/lib-dynamodb';
import { APIGatewayProxyEvent, APIGatewayProxyResult, Context, ScheduledEvent } from 'aws-lambda';
import { SchedulerClient, DeleteScheduleCommand } from '@aws-sdk/client-scheduler';
import { LambdaClient, InvokeCommand, InvocationType } from '@aws-sdk/client-lambda';
import { TextDecoder } from 'util';
import { PublishCommand, SNSClient, SubscribeCommand } from '@aws-sdk/client-sns';

// --- Constants ---
const BSKY_SERVICE = 'https://bsky.social';
const DATA_COUNTER_NAME = 'DataCounter';
const SUBTOPIC_COUNT = 3; // Define the desired number of subtopics

const TOPIC_ARN = process.env.TOPIC_ARN;
// --- AWS Clients ---
const comprehendClient = new ComprehendClient({ region: process.env.AWS_REGION });
const dynamoClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const schedulerClient = new SchedulerClient({ region: process.env.AWS_REGION });
const lambdaClient = new LambdaClient({ region: process.env.AWS_REGION });

// --- Table Names from Environment Variables ---
const QUERIES_TABLE_NAME = process.env.QUERIES_TABLE_NAME;
const DATA_TABLE_NAME = process.env.DATA_TABLE_NAME;
const COUNTERS_TABLE_NAME = process.env.COUNTERS_TABLE_NAME || 'CountersData'; // Provide default
const MAX_COMPREHEND_BYTES = 4990; // Slightly less than 5000 for safety

// --- Interfaces ---
// PostWithAnalysis should augment PostView, as searchPosts returns PostView[]
interface PostWithAnalysis extends AppBskyFeedDefs.PostView {
    sentimentAnalysis?: {
        sentiment: string | undefined;
        scores: Record<string, number | undefined> | undefined;
        languageCode?: LanguageCode;
        error?: string;
    };
    keyPhraseAnalysis?: {
        phrases?: string[];
        error?: string;
    };
}

interface QueryDetails {
    QueryID: number;
    Topic: string;
    Email: string;
    NumIntervals: number;
    PostsToAnalyze: number;
    IntervalLength: number;
    IntervalUnit: string;
    CreatedAt: number;
    Status?: string;
}

interface SentimentSummary {
    queryId: number;
    topic: string;
    timestamp: number;
    totalPostsAnalyzed: number;
    positivePosts: number;
    negativePosts: number;
    neutralPosts: number;
    mixedPosts: number;
    avgPositiveScore: number;
    avgNegativeScore: number;
    avgNeutralScore: number;
    avgMixedScore: number;
}

// --- DynamoDB Helper Functions ---

/**
 * Fetches query details from the Queries DynamoDB table.
 */
async function getQueryDetails(queryId: number, topicHint?: string): Promise<QueryDetails> {
    if (!QUERIES_TABLE_NAME) {
        throw new Error('QUERIES_TABLE_NAME environment variable is not set.');
    }
    console.log(`Fetching details for QueryID: ${queryId} from table: ${QUERIES_TABLE_NAME}`);

    // If topicHint is provided, use GetItem (more efficient)
    if (topicHint) {
        try {
            const command = new GetCommand({
                TableName: QUERIES_TABLE_NAME,
                Key: { QueryID: queryId, Topic: topicHint },
            });
            const result = await docClient.send(command);
            if (result.Item) {
                console.log('Successfully fetched query details using GetCommand.');
                return result.Item as QueryDetails;
            }
            console.log(
                `Query details not found with GetCommand (QueryID: ${queryId}, Topic: ${topicHint}). Falling back to Query.`,
            );
        } catch (error) {
            console.warn(
                `Error fetching query details with GetCommand for QueryID ${queryId}, Topic ${topicHint}. Falling back to Query. Error:`,
                error,
            );
        }
    }

    // Fallback or if no topicHint: Use Query on QueryID (assuming QueryID is the Partition Key)
    console.log(`Attempting Query operation for QueryID: ${queryId}`);
    try {
        const queryCommand = new QueryCommand({
            TableName: QUERIES_TABLE_NAME,
            KeyConditionExpression: 'QueryID = :qid',
            ExpressionAttributeValues: { ':qid': queryId },
            Limit: 1, // We only expect one item per QueryID
        });
        const result = await docClient.send(queryCommand);
        if (result.Items && result.Items.length > 0) {
            console.log('Successfully fetched query details using QueryCommand.');
            return result.Items[0] as QueryDetails;
        } else {
            throw new Error(`Query details not found for QueryID: ${queryId} using QueryCommand.`);
        }
    } catch (error) {
        console.error(`Error fetching query details for QueryID ${queryId} using QueryCommand:`, error);
        throw new Error(`Failed to fetch query details: ${error instanceof Error ? error.message : String(error)}`);
    }
}

/**
 * Stores the sentiment analysis summary in the Data DynamoDB table.
 */
async function storeAnalysisResults(summary: SentimentSummary): Promise<void> {
    if (!DATA_TABLE_NAME) {
        throw new Error('DATA_TABLE_NAME environment variable is not set.');
    }
    const dataId = await getNextDataId(DATA_COUNTER_NAME);
    const topicForStorage = summary.topic; // Main topic storage

    console.log(
        `Storing analysis results for QueryID: ${summary.queryId}, Topic: "${topicForStorage}" in table: ${DATA_TABLE_NAME}`,
    );

    try {
        const item: Record<string, any> = {
            DataID: dataId, // Partition Key
            QueryID: summary.queryId, // Attribute (Consider making this a GSI PK)
            AnalysisTimestamp: summary.timestamp, // Sort Key (Timestamp of analysis run)
            Topic: topicForStorage, // Store the specific topic analyzed
            PostsAnalyzed: summary.totalPostsAnalyzed,
            PositivePosts: summary.positivePosts,
            NegativePosts: summary.negativePosts,
            NeutralPosts: summary.neutralPosts,
            MixedPosts: summary.mixedPosts,
            AvgPositiveScore: summary.avgPositiveScore,
            AvgNegativeScore: summary.avgNegativeScore,
            AvgNeutralScore: summary.avgNeutralScore,
            AvgMixedScore: summary.avgMixedScore,
            CreatedAt: Math.floor(Date.now() / 1000),
            IsSubtopic: false, // Main topic entries are not subtopics
        };

        const command = new PutCommand({
            TableName: DATA_TABLE_NAME,
            Item: item,
        });
        await docClient.send(command);
        console.log(
            `Successfully stored analysis results for QueryID ${summary.queryId} at ${summary.timestamp} for main topic "${summary.topic}"`,
        );
    } catch (error) {
        console.error(
            `Error storing analysis results for QueryID ${summary.queryId} (Main Topic: ${summary.topic}):`,
            error,
        );
        throw new Error(`Failed to store analysis results: ${error instanceof Error ? error.message : String(error)}`);
    }
}

/**
 * Stores the sentiment analysis summary for a subtopic in the Data DynamoDB table.
 */
async function storeSubtopicAnalysisResults(
    summary: SentimentSummary,
    subtopic: string,
    mainTopic: string,
): Promise<void> {
    if (!DATA_TABLE_NAME) {
        throw new Error('DATA_TABLE_NAME environment variable is not set.');
    }
    const dataId = await getNextDataId(DATA_COUNTER_NAME);

    console.log(
        `Storing analysis results for QueryID: ${summary.queryId}, Subtopic: "${subtopic}" (Main: "${mainTopic}") in table: ${DATA_TABLE_NAME}`,
    );

    try {
        // Note: summary.topic here will be the subtopic name because analyzeSentimentForTerm uses the 'term' passed to it.
        const item: Record<string, any> = {
            DataID: dataId, // Partition Key
            QueryID: summary.queryId, // Attribute (Consider making this a GSI PK)
            AnalysisTimestamp: summary.timestamp, // Sort Key (Timestamp of analysis run)
            Topic: subtopic, // Store the specific subtopic analyzed
            MainTopic: mainTopic, // Store the main topic context
            PostsAnalyzed: summary.totalPostsAnalyzed,
            PositivePosts: summary.positivePosts,
            NegativePosts: summary.negativePosts,
            NeutralPosts: summary.neutralPosts,
            MixedPosts: summary.mixedPosts,
            AvgPositiveScore: summary.avgPositiveScore,
            AvgNegativeScore: summary.avgNegativeScore,
            AvgNeutralScore: summary.avgNeutralScore,
            AvgMixedScore: summary.avgMixedScore,
            CreatedAt: Math.floor(Date.now() / 1000),
            IsSubtopic: true, // Explicitly mark as subtopic entry
        };

        const command = new PutCommand({
            TableName: DATA_TABLE_NAME,
            Item: item,
        });
        await docClient.send(command);
        console.log(
            `Successfully stored analysis results for QueryID ${summary.queryId} at ${summary.timestamp} for subtopic "${subtopic}"`,
        );
    } catch (error) {
        console.error(`Error storing analysis results for QueryID ${summary.queryId} (Subtopic: ${subtopic}):`, error);
        throw new Error(
            `Failed to store subtopic analysis results: ${error instanceof Error ? error.message : String(error)}`,
        );
    }
}

/**
 * Deletes the EventBridge Schedule associated with a QueryID.
 */
async function deleteSchedule(queryId: number): Promise<void> {
    const scheduleName = `BlueskyAnalysis-Query-${queryId}`;
    const groupName = process.env.SCHEDULER_GROUP_NAME || 'default';
    console.log(`Attempting to delete schedule: ${scheduleName} in group: ${groupName}`);
    try {
        const deleteCommand = new DeleteScheduleCommand({
            Name: scheduleName,
            GroupName: groupName,
        });
        await schedulerClient.send(deleteCommand);
        console.log(`Successfully deleted schedule: ${scheduleName}`);
    } catch (error) {
        // Check specifically for ResourceNotFoundException
        if (error instanceof Error && error.name === 'ResourceNotFoundException') {
            console.log(
                `Schedule ${scheduleName} not found in group ${groupName}, likely already deleted or never existed.`,
            );
        } else {
            console.error(`Error deleting schedule ${scheduleName} in group ${groupName}:`, error);
            // Decide if this should be a fatal error or just logged
            // throw error; // Uncomment if deletion failure should stop the process
        }
    }
}

const textDecoder = new TextDecoder('utf-8');

/**
 * Fetches subtopics associated with a QueryID.
 * Invokes another Lambda function to retrieve stored subtopics.
 */
async function getSubtopics(queryId: number): Promise<string[]> {
    const GET_SUBTOPICS_LAMBDA_NAME = process.env.GET_SUBTOPICS_LAMBDA_NAME || 'getSubtopic'; // Use env var

    if (!GET_SUBTOPICS_LAMBDA_NAME) {
        console.error('GET_SUBTOPICS_LAMBDA_NAME environment variable is not set.');
        return [];
    }

    const payload = {
        QueryID: queryId,
    };

    console.log(`Invoking ${GET_SUBTOPICS_LAMBDA_NAME} to get subtopics for QueryID: ${queryId}`);

    try {
        const command = new InvokeCommand({
            FunctionName: GET_SUBTOPICS_LAMBDA_NAME,
            InvocationType: InvocationType.RequestResponse,
            Payload: JSON.stringify(payload),
            LogType: 'Tail', // Request logs if needed for debugging
        });

        const response = await lambdaClient.send(command);

        // Check for function errors returned by the invoked Lambda
        if (response.FunctionError) {
            console.error(
                `Lambda function ${GET_SUBTOPICS_LAMBDA_NAME} returned an error for QueryID ${queryId}:`,
                response.FunctionError,
            );
            if (response.Payload) {
                console.error('Error Payload:', textDecoder.decode(response.Payload));
            }
            if (response.LogResult) {
                console.error('Execution Logs:\n', Buffer.from(response.LogResult, 'base64').toString('utf-8'));
            }
            return []; // Return empty array on function error
        }

        if (response.Payload) {
            const responsePayloadString = textDecoder.decode(response.Payload);
            console.log(`Raw payload string from ${GET_SUBTOPICS_LAMBDA_NAME}:`, responsePayloadString);
            const responsePayload = JSON.parse(responsePayloadString);

            // Adapt based on the actual structure returned by getSubtopic lambda
            // Scenario 1: Direct array of strings
            if (Array.isArray(responsePayload) && responsePayload.every((item) => typeof item === 'string')) {
                console.log(
                    `Successfully extracted ${responsePayload.length} subtopics (direct array) for QueryID ${queryId}.`,
                );
                return responsePayload.filter((s) => s && s.trim() !== ''); // Filter empty strings
            }

            // Scenario 2: API Gateway-like response with stringified body containing array of objects { Subtopic: "..." }
            if (
                responsePayload &&
                typeof responsePayload.body === 'string' &&
                (responsePayload.statusCode === 200 ||
                    (responsePayload.statusCode >= 200 && responsePayload.statusCode < 300))
            ) {
                console.log(
                    `Detected API Gateway-like response structure from ${GET_SUBTOPICS_LAMBDA_NAME}. Parsing body...`,
                );
                try {
                    const bodyPayload = JSON.parse(responsePayload.body);

                    // Check if the parsed body is an array of objects with 'Subtopic' property
                    if (Array.isArray(bodyPayload)) {
                        const subtopics = bodyPayload
                            .map((item: any) => item?.Subtopic) // Extract 'Subtopic' field
                            .filter((s): s is string => typeof s === 'string' && s.trim() !== ''); // Filter out non-strings or empty strings

                        console.log(
                            `Successfully extracted ${
                                subtopics.length
                            } subtopics (API Gateway body) for QueryID ${queryId}: ${subtopics.join(', ')}`,
                        );
                        return subtopics;
                    } else {
                        console.warn(
                            `Parsed body from ${GET_SUBTOPICS_LAMBDA_NAME} is not an array for QueryID ${queryId}. Body:`,
                            responsePayload.body,
                        );
                        return [];
                    }
                } catch (parseError) {
                    console.error(
                        `Error parsing the 'body' string from ${GET_SUBTOPICS_LAMBDA_NAME} response for QueryID ${queryId}:`,
                        parseError,
                    );
                    console.error('Body content:', responsePayload.body);
                    return [];
                }
            }
            // Scenario 3: API Gateway-like response with stringified body containing array of strings
            else if (
                responsePayload &&
                typeof responsePayload.body === 'string' &&
                (responsePayload.statusCode === 200 ||
                    (responsePayload.statusCode >= 200 && responsePayload.statusCode < 300))
            ) {
                console.log(
                    `Detected API Gateway-like response structure from ${GET_SUBTOPICS_LAMBDA_NAME}. Parsing body (assuming array of strings)...`,
                );
                try {
                    const bodyPayload = JSON.parse(responsePayload.body);
                    if (Array.isArray(bodyPayload) && bodyPayload.every((item) => typeof item === 'string')) {
                        const subtopics = bodyPayload.filter((s) => s && s.trim() !== ''); // Filter empty strings
                        console.log(
                            `Successfully extracted ${subtopics.length} subtopics (API Gateway body - string array) for QueryID ${queryId}.`,
                        );
                        return subtopics;
                    } else {
                        console.warn(
                            `Parsed body from ${GET_SUBTOPICS_LAMBDA_NAME} is not an array of strings for QueryID ${queryId}. Body:`,
                            responsePayload.body,
                        );
                        return [];
                    }
                } catch (parseError) {
                    console.error(
                        `Error parsing the 'body' string (as string array) from ${GET_SUBTOPICS_LAMBDA_NAME} response for QueryID ${queryId}:`,
                        parseError,
                    );
                    console.error('Body content:', responsePayload.body);
                    return [];
                }
            } else {
                console.warn(
                    `Received unexpected payload structure from ${GET_SUBTOPICS_LAMBDA_NAME} for QueryID ${queryId}:`,
                    responsePayloadString,
                );
                return [];
            }
        } else {
            console.warn(
                `Lambda function ${GET_SUBTOPICS_LAMBDA_NAME} did not return a payload for QueryID ${queryId}.`,
            );
            return [];
        }
    } catch (error) {
        console.error(`Error invoking Lambda ${GET_SUBTOPICS_LAMBDA_NAME} for QueryID ${queryId}:`, error);
        return []; // Return empty array on invocation error
    }
}

/**
 * Performs Bluesky search, sentiment analysis, and calculates summary for a given term.
 * Does NOT perform key phrase analysis.
 * Returns the original PostView objects along with the summary.
 */
async function analyzeSentimentForTerm(
    agent: BskyAgent,
    term: string,
    limit: number,
    queryIdForContext: number, // For logging/context
): Promise<{ summary: SentimentSummary | null; posts: AppBskyFeedDefs.PostView[] }> {
    // <-- Return PostView[]
    console.log(`[QueryID: ${queryIdForContext}] Starting sentiment analysis for term: "${term}" with limit ${limit}`);
    let searchResults;
    try {
        console.log(`[QueryID: ${queryIdForContext}] Searching posts for "${term}"...`);
        searchResults = await agent.app.bsky.feed.searchPosts({
            q: term,
            limit: limit,
        });
        // The result is PostView[]
        const posts: AppBskyFeedDefs.PostView[] = searchResults.data.posts; // <-- Correct type
        console.log(`[QueryID: ${queryIdForContext}] Found ${posts.length} posts for "${term}".`);

        if (posts.length === 0) {
            console.log(`[QueryID: ${queryIdForContext}] No posts found for term "${term}".`);
            return { summary: null, posts: [] }; // <-- Return empty PostView[]
        }

        // --- Analyze Sentiment ---
        console.log(`[QueryID: ${queryIdForContext}] Analyzing sentiment for ${posts.length} "${term}" posts...`);
        // Map over PostView[], return PostWithAnalysis[] for intermediate calculation
        const postsWithSentiment: PostWithAnalysis[] = await Promise.all(
            posts.map(async (postView): Promise<PostWithAnalysis> => {
                // <-- Iterate PostView
                // Correctly access the post record
                const postRecord = postView.record as { text?: string; [key: string]: unknown } | undefined; // <-- Use postView
                const postText = postRecord?.text;

                // Start by spreading the original PostView, then add analysis fields
                const analysisResult: PostWithAnalysis = { ...postView }; // <-- Spread PostView

                if (!postText || postText.trim() === '') {
                    // No text to analyze, return the original PostView structure within PostWithAnalysis
                    return analysisResult;
                }

                let textToAnalyze = postText;
                const byteLength = Buffer.byteLength(postText, 'utf8');
                if (byteLength > MAX_COMPREHEND_BYTES) {
                    console.warn(
                        `[QueryID: ${queryIdForContext}] Post text (URI: ${postView.uri}) for term "${term}" exceeds ${MAX_COMPREHEND_BYTES} bytes (${byteLength}), truncating.`, // <-- Use postView.uri
                    );
                    const buffer = Buffer.from(postText, 'utf8');
                    textToAnalyze = buffer.slice(0, MAX_COMPREHEND_BYTES).toString('utf8');
                }

                const languageCode: LanguageCode = 'en'; // Hardcoded

                try {
                    const sentimentParams: DetectSentimentCommandInput = {
                        Text: textToAnalyze,
                        LanguageCode: languageCode,
                    };
                    const sentimentCommand = new DetectSentimentCommand(sentimentParams);
                    const sentimentData = await comprehendClient.send(sentimentCommand);

                    // Add sentiment analysis to the result object
                    analysisResult.sentimentAnalysis = {
                        sentiment: sentimentData.Sentiment,
                        scores: sentimentData.SentimentScore
                            ? {
                                  Positive: sentimentData.SentimentScore.Positive,
                                  Negative: sentimentData.SentimentScore.Negative,
                                  Neutral: sentimentData.SentimentScore.Neutral,
                                  Mixed: sentimentData.SentimentScore.Mixed,
                              }
                            : undefined,
                        languageCode: languageCode,
                    };
                } catch (comprehendError) {
                    console.error(
                        `[QueryID: ${queryIdForContext}] Error analyzing sentiment for post URI ${postView.uri} (term "${term}"):`, // <-- Use postView.uri
                        comprehendError,
                    );
                    // Add error info to the result object
                    analysisResult.sentimentAnalysis = {
                        sentiment: undefined,
                        scores: undefined,
                        languageCode: languageCode,
                        error: comprehendError instanceof Error ? comprehendError.message : String(comprehendError),
                    };
                }
                // Key phrase analysis is NOT done here
                analysisResult.keyPhraseAnalysis = undefined;
                return analysisResult;
            }),
        );

        // --- Calculate Sentiment Summary ---
        let positivePosts = 0,
            negativePosts = 0,
            neutralPosts = 0,
            mixedPosts = 0;
        let totalPositiveScore = 0,
            totalNegativeScore = 0,
            totalNeutralScore = 0,
            totalMixedScore = 0;
        let analyzedCount = 0;

        postsWithSentiment.forEach((p) => {
            // p is PostWithAnalysis (which extends PostView)
            if (p.sentimentAnalysis && !p.sentimentAnalysis.error && p.sentimentAnalysis.sentiment) {
                analyzedCount++;
                totalPositiveScore += p.sentimentAnalysis.scores?.Positive || 0;
                totalNegativeScore += p.sentimentAnalysis.scores?.Negative || 0;
                totalNeutralScore += p.sentimentAnalysis.scores?.Neutral || 0;
                totalMixedScore += p.sentimentAnalysis.scores?.Mixed || 0;
                switch (p.sentimentAnalysis.sentiment) {
                    case 'POSITIVE':
                        positivePosts++;
                        break;
                    case 'NEGATIVE':
                        negativePosts++;
                        break;
                    case 'NEUTRAL':
                        neutralPosts++;
                        break;
                    case 'MIXED':
                        mixedPosts++;
                        break;
                }
            }
        });

        if (analyzedCount === 0) {
            console.log(`[QueryID: ${queryIdForContext}] No posts could be analyzed for sentiment for term "${term}".`);
            // Return original posts (PostView[]) even if analysis failed/yielded nothing
            return { summary: null, posts: posts }; // <-- Return original PostView[]
        }

        const summary: SentimentSummary = {
            queryId: queryIdForContext,
            topic: term, // Use the term analyzed
            timestamp: Date.now(),
            totalPostsAnalyzed: analyzedCount,
            positivePosts: positivePosts,
            negativePosts: negativePosts,
            neutralPosts: neutralPosts,
            mixedPosts: mixedPosts,
            avgPositiveScore: analyzedCount > 0 ? totalPositiveScore / analyzedCount : 0,
            avgNegativeScore: analyzedCount > 0 ? totalNegativeScore / analyzedCount : 0,
            avgNeutralScore: analyzedCount > 0 ? totalNeutralScore / analyzedCount : 0,
            avgMixedScore: analyzedCount > 0 ? totalMixedScore / analyzedCount : 0,
        };
        console.log(
            `[QueryID: ${queryIdForContext}] Sentiment Summary for "${term}":`,
            JSON.stringify(summary, null, 2),
        );
        // Return summary and original posts (PostView[])
        return { summary: summary, posts: posts }; // <-- Return original PostView[]
    } catch (searchError) {
        console.error(`[QueryID: ${queryIdForContext}] Error searching Bluesky posts for "${term}":`, searchError);
        return { summary: null, posts: [] }; // <-- Return empty PostView[]
    }
}

// --- Type Guard ---
function isScheduledEvent(event: any): event is ScheduledEvent {
    return event.source === 'aws.scheduler' && event['detail-type'] === 'Scheduled Event';
}

// --- Lambda Handler ---
export const handler = async (
    event: ScheduledEvent | APIGatewayProxyEvent | { topic: string },
    context?: Context,
): Promise<APIGatewayProxyResult | void> => {
    console.log('Received event:', JSON.stringify(event, null, 2));

    let queryId: number | undefined;
    let topicFromEvent: string | undefined; // Topic might come from event or DB

    // --- 1. Extract Query Info from Event ---
    if (isScheduledEvent(event)) {
        console.log('Detected Scheduled Event from EventBridge Scheduler.');
        queryId = event.detail?.queryId;
        topicFromEvent = event.detail?.topic; // May or may not be present/needed

        if (typeof queryId !== 'number') {
            console.error(
                'Scheduled event missing required detail property (queryId: number). Event detail:',
                event.detail,
            );
            throw new Error('Invalid scheduled event payload: Missing queryId.');
        }
        console.log(`Processing scheduled job for QueryID: ${queryId}`);
        if (topicFromEvent) {
            console.log(`Topic hint from event: "${topicFromEvent}" (will be confirmed from DB)`);
        }
    } else {
        // Handle other invocation types (e.g., API Gateway for testing)
        console.log('Detected non-scheduled event (e.g., API Gateway, manual invocation).');
        if (
            'queryStringParameters' in event &&
            event.queryStringParameters?.queryId &&
            !isNaN(parseInt(event.queryStringParameters.queryId, 10))
        ) {
            queryId = parseInt(event.queryStringParameters.queryId, 10);
            topicFromEvent = event.queryStringParameters.topic; // Optional topic hint for testing
            console.log(
                `Manual invocation for QueryID: ${queryId}` +
                    (topicFromEvent ? `, Topic Hint: "${topicFromEvent}"` : ''),
            );
        } else {
            console.error('Manual invocation requires queryId query string parameter.');
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "Manual invocation requires 'queryId' parameter." }),
            };
        }
    }

    // --- Ensure Table Names are Set ---
    if (!QUERIES_TABLE_NAME || !DATA_TABLE_NAME || !COUNTERS_TABLE_NAME) {
        console.error('Missing environment variables: QUERIES_TABLE_NAME, DATA_TABLE_NAME, or COUNTERS_TABLE_NAME');
        throw new Error('Server configuration error: Missing table names.');
    }

    // --- 2. Fetch Query Details from DynamoDB ---
    let queryDetails: QueryDetails;
    try {
        // Pass topicFromEvent as a hint for potential GetItem optimization
        queryDetails = await getQueryDetails(queryId, topicFromEvent);
        console.log('Fetched Query Details:', queryDetails);

        // Validate status
        if (queryDetails.Status === 'COMPLETED' || queryDetails.Status === 'CANCELLED') {
            console.log(`Query ${queryId} is already in status ${queryDetails.Status}. Skipping execution.`);
            await deleteSchedule(queryId); // Ensure schedule is deleted if somehow still active
            return;
        }
    } catch (error) {
        console.error(`Error during query detail fetch or validation for QueryID ${queryId}:`, error);
        // Consider updating status to FAILED here if appropriate
        throw error; // Stop execution
    }

    // --- 3. Check Run Count (Number of times main topic has been analyzed) ---
    let currentRunCount = 0;
    try {
        console.warn(
            `Using SCAN operation on table '${DATA_TABLE_NAME}' to count runs for QueryID ${queryId}. Consider adding a GSI on QueryID with a filter on 'IsSubtopic = false' for efficiency.`,
        );
        const scanCmd = new ScanCommand({
            TableName: DATA_TABLE_NAME,
            // Filter for main topic entries only
            FilterExpression: 'QueryID = :qid AND attribute_exists(IsSubtopic) AND IsSubtopic = :isfalse',
            ExpressionAttributeValues: {
                ':qid': queryId,
                ':isfalse': false,
            },
            Select: 'COUNT',
        });
        const countResult = await docClient.send(scanCmd);
        currentRunCount = countResult.Count ?? 0;
        console.log(`Current main topic run count for QueryID ${queryId}: ${currentRunCount}`);
    } catch (error) {
        console.error(`Error fetching run count using SCAN for QueryID ${queryId}:`, error);
        throw new Error(`Failed to fetch run count: ${error instanceof Error ? error.message : String(error)}`);
    }

    // --- Early Exit if Max Intervals Reached ---
    // Check *before* doing any expensive API calls if we've already completed enough runs
    if (currentRunCount >= queryDetails.NumIntervals) {
        console.log(
            `QueryID ${queryId} has already completed ${currentRunCount}/${queryDetails.NumIntervals} intervals. Finalizing.`,
        );
        // Optional: Update Query Status to COMPLETED in Queries table (idempotently)
        // await updateQueryStatus(queryId, queryDetails.Topic, 'COMPLETED');
        await triggerEmailNotification(queryDetails);
        await deleteSchedule(queryId);
        return; // Stop execution
    }

    // --- 4. Get Bluesky Credentials ---
    const identifier = process.env.BLUESKY_HANDLE;
    const password = process.env.BLUESKY_APP_PASSWORD;
    if (!identifier || !password) {
        console.error('Missing Bluesky credentials in environment variables');
        throw new Error('Server configuration error: Missing Bluesky credentials.');
    }

    // --- 5. Initialize and Authenticate Bluesky Agent ---
    const agent = new BskyAgent({ service: BSKY_SERVICE });
    try {
        console.log(`Attempting Bluesky login for handle: ${identifier}`);
        await agent.login({ identifier, password });
        console.log('Bluesky login successful.');
    } catch (loginError) {
        console.error('Bluesky login failed:', loginError);
        // Consider updating status to FAILED
        throw new Error(
            `Bluesky authentication failed: ${loginError instanceof Error ? loginError.message : String(loginError)}`,
        );
    }

    // --- 6. Perform Analysis ---
    const mainTopic = queryDetails.Topic;
    const postLimit = queryDetails.PostsToAnalyze;
    let mainTopicStoredSuccessfullyThisRun = false;

    // --- 6a. ALWAYS Analyze Main Topic ---
    console.log(`--- Analyzing Main Topic (Run ${currentRunCount + 1}) for QueryID ${queryId}: "${mainTopic}" ---`);
    // Declare variable to hold the result, matching the updated return type
    let mainTopicAnalysisResult: { summary: SentimentSummary | null; posts: AppBskyFeedDefs.PostView[] };

    try {
        mainTopicAnalysisResult = await analyzeSentimentForTerm(agent, mainTopic, postLimit, queryId);

        if (mainTopicAnalysisResult.summary) {
            // Store main topic results (no subtopic specified)
            await storeAnalysisResults(mainTopicAnalysisResult.summary);
            mainTopicStoredSuccessfullyThisRun = true;

            if (currentRunCount === 0) {
                console.log(`--- First Run Specific Actions for QueryID ${queryId} ---`);
                const client = new SNSClient({});

                const emailAddress = queryDetails.Email;
                const command = new SubscribeCommand({
                    TopicArn: TOPIC_ARN,
                    Protocol: 'email',
                    Endpoint: emailAddress,
                    Attributes: {
                        FilterPolicyScope: 'MessageAttributes',
                        FilterPolicy: JSON.stringify({
                            event: [emailAddress],
                        }),
                    },
                });
                const response = await client.send(command);

                const mainTopicPosts = mainTopicAnalysisResult.posts;

                if (mainTopicPosts.length > 0) {
                    console.log('Analyzing key phrases for main topic posts...');
                    // Map over PostView[], create PostWithAnalysis[] containing key phrases
                    const postsWithKeyPhrases: PostWithAnalysis[] = await Promise.all(
                        mainTopicPosts.map(async (postView): Promise<PostWithAnalysis> => {
                            // <-- Iterate PostView
                            // Correctly access the post record
                            const postRecord = postView.record as { text?: string; [key: string]: unknown } | undefined; // <-- Use postView
                            const postText = postRecord?.text;

                            // Start by spreading the original PostView
                            const analysisResult: PostWithAnalysis = { ...postView }; // <-- Spread PostView

                            if (!postText || postText.trim() === '') {
                                return analysisResult; // Return structure with no keyPhraseAnalysis
                            }

                            let textToAnalyze = postText;
                            const byteLength = Buffer.byteLength(postText, 'utf8');
                            if (byteLength > MAX_COMPREHEND_BYTES) {
                                console.warn(
                                    `[KP Analysis] Post text (URI: ${postView.uri}) exceeds ${MAX_COMPREHEND_BYTES} bytes (${byteLength}), truncating.`, // <-- Use postView.uri
                                );
                                const buffer = Buffer.from(postText, 'utf8');
                                textToAnalyze = buffer.slice(0, MAX_COMPREHEND_BYTES).toString('utf8');
                            }
                            const languageCode: LanguageCode = 'en'; // Assuming English

                            // Key Phrase Detection
                            try {
                                const keyPhraseParams: DetectKeyPhrasesCommandInput = {
                                    Text: textToAnalyze,
                                    LanguageCode: languageCode,
                                };
                                const keyPhraseCommand = new DetectKeyPhrasesCommand(keyPhraseParams);
                                const keyPhraseData = await comprehendClient.send(keyPhraseCommand);
                                // Add key phrase analysis to the result object
                                analysisResult.keyPhraseAnalysis = {
                                    phrases:
                                        keyPhraseData.KeyPhrases?.map((kp) => kp.Text ?? '').filter((text) => text) ??
                                        [],
                                };
                            } catch (comprehendError) {
                                console.error(
                                    `Error detecting key phrases for post URI ${postView.uri}:`, // <-- Use postView.uri
                                    comprehendError,
                                );
                                // Add error info to the result object
                                analysisResult.keyPhraseAnalysis = {
                                    phrases: [],
                                    error:
                                        comprehendError instanceof Error
                                            ? comprehendError.message
                                            : String(comprehendError),
                                };
                            }
                            // Sentiment analysis is not added here, only key phrases
                            analysisResult.sentimentAnalysis = undefined;
                            return analysisResult;
                        }),
                    );
                    console.log('Key phrase analysis complete for main topic.');

                    // Aggregate Key Phrases and Find Top Subtopics
                    console.log('Aggregating key phrases...');
                    const phraseCounts: { [phrase: string]: number } = {};
                    postsWithKeyPhrases.forEach((p) => {
                        // p is PostWithAnalysis (extends PostView)
                        if (p.keyPhraseAnalysis && !p.keyPhraseAnalysis.error && p.keyPhraseAnalysis.phrases) {
                            p.keyPhraseAnalysis.phrases.forEach((phrase) => {
                                const normalizedPhrase = phrase.toLowerCase().trim();
                                // Basic filtering: ignore very short phrases or phrases identical to main topic
                                if (
                                    normalizedPhrase &&
                                    normalizedPhrase.length > 2 &&
                                    normalizedPhrase !== mainTopic.toLowerCase().trim()
                                ) {
                                    phraseCounts[normalizedPhrase] = (phraseCounts[normalizedPhrase] || 0) + 1;
                                }
                            });
                        }
                    });

                    // Get top N+1 potential subtopics (to allow filtering main topic if it appears)
                    const sortedPhrases = Object.entries(phraseCounts).sort(
                        ([, countA], [, countB]) => countB - countA,
                    );

                    const potentialSubtopics = sortedPhrases
                        .slice(0, SUBTOPIC_COUNT + 1) // Get a few extra
                        .map(([phrase]) => phrase); // Extract original casing phrase text

                    console.log(`Top ${potentialSubtopics.length} potential subtopics found:`, potentialSubtopics);

                    // Filter out the main topic (case-insensitive) and select the top N (SUBTOPIC_COUNT)
                    const normalizedMainTopic = mainTopic.toLowerCase().trim();
                    const finalSubtopics = potentialSubtopics
                        .filter((phrase) => phrase.toLowerCase().trim() !== normalizedMainTopic) // Filter out main topic
                        .slice(0, SUBTOPIC_COUNT); // Take the top N

                    console.log(`Selected ${finalSubtopics.length} final subtopics:`, finalSubtopics);

                    // Invoke addSubtopic Lambda for the final list
                    if (finalSubtopics.length > 0) {
                        await Promise.all(
                            finalSubtopics.map((subtopic) => triggerAddSubtopicLambda(queryId!, subtopic)),
                        );
                    } else {
                        console.log('No suitable subtopics found after filtering.');
                    }
                } else {
                    console.log(
                        'No posts found for main topic during first run, skipping key phrase analysis and subtopic generation.',
                    );
                }
            } // End of first run block (moved inside try)
        } else {
            console.warn(`Main topic analysis for "${mainTopic}" did not produce a summary. Skipping storage.`);
            // Ensure mainTopicAnalysisResult is assigned even if summary is null, if analyzeSentimentForTerm succeeded without throwing
            if (!mainTopicAnalysisResult) {
                mainTopicAnalysisResult = { summary: null, posts: [] };
            }
        }
    } catch (error) {
        console.error(`Error during main topic analysis or storage for QueryID ${queryId}:`, error);
        // Assign a default value here to prevent potential downstream errors if code proceeds.
        mainTopicAnalysisResult = { summary: null, posts: [] };
        // Decide if this should be fatal. For now, we log and continue.
        if (currentRunCount === 0) {
            console.error(
                "Error occurred during the first run's main topic analysis. Subtopic generation will be skipped.",
            );
            // Optionally re-throw error here if first run MUST succeed for main topic
            // throw error;
        }
    }

    // --- 6b. First Run ONLY: Key Phrases and Subtopic Generation ---
    // THIS BLOCK WAS MOVED INSIDE THE TRY BLOCK ABOVE (around line 778)

    // --- 6c. Subsequent Runs ONLY: Analyze Subtopics ---
    // This block should execute if it's not the first run, regardless of main topic success *this run*.
    if (currentRunCount > 0) {
        console.log(`--- Analyzing Subtopics (Run ${currentRunCount + 1}) for QueryID ${queryId} ---`);
        const subtopics = await getSubtopics(queryId);

        if (!subtopics || subtopics.length === 0) {
            console.log(
                `No subtopics found or configured for QueryID ${queryId} on run ${
                    currentRunCount + 1
                }. Only main topic was analyzed this interval.`,
            );
        } else {
            console.log(`Analyzing ${subtopics.length} subtopics: ${subtopics.join(', ')}`);
            for (const subtopic of subtopics) {
                try {
                    // Analyze sentiment only for the subtopic
                    const subtopicAnalysisResult = await analyzeSentimentForTerm(agent, subtopic, postLimit, queryId);
                    if (subtopicAnalysisResult.summary) {
                        // Store Subtopic Results, passing the subtopic name and the original main topic
                        await storeSubtopicAnalysisResults(subtopicAnalysisResult.summary, subtopic, mainTopic);
                    } else {
                        console.warn(
                            `Skipping storage for subtopic "${subtopic}" due to analysis error or no posts found/analyzed.`,
                        );
                    }
                } catch (error) {
                    // Log error for this specific subtopic but continue with others
                    console.error(`Error processing subtopic "${subtopic}" for QueryID ${queryId}:`, error);
                }
            }
        }
    } else if (currentRunCount === 0 && !mainTopicStoredSuccessfullyThisRun) {
        // Log if first run failed before subtopic generation could occur
        console.warn(
            `Subtopic generation skipped for QueryID ${queryId} as main topic analysis failed or yielded no results on the first run.`,
        );
    }

    // --- 7. Final Check and Cleanup ---
    // Calculate the effective run count *after* this execution attempt
    const effectiveRunCountAfterThisExecution = currentRunCount + (mainTopicStoredSuccessfullyThisRun ? 1 : 0);

    console.log(
        `Effective main topic run count after this execution: ${effectiveRunCountAfterThisExecution} / ${queryDetails.NumIntervals}`,
    );

    // Check completion based on the number of *main topic* runs successfully stored
    if (effectiveRunCountAfterThisExecution >= queryDetails.NumIntervals) {
        console.log(
            `QueryID ${queryId} has now completed its final interval (${effectiveRunCountAfterThisExecution}/${queryDetails.NumIntervals}).`,
        );
 
        await triggerEmailNotification(queryDetails);
        await deleteSchedule(queryId); // Delete the schedule after the final successful run
    } else {
        console.log(
            `QueryID ${queryId} has completed ${effectiveRunCountAfterThisExecution}/${queryDetails.NumIntervals} intervals. Scheduling next run.`,
        );
    }

    // --- 8. Return ---
    console.log(`Execution for QueryID ${queryId} completed for this interval.`);
    // No explicit return needed for successful scheduled event processing
    if (!isScheduledEvent(event)) {
        // For manual invocation, return a success message
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: mainTopicStoredSuccessfullyThisRun
                    ? 'Analysis complete for interval (main topic stored).'
                    : 'Analysis attempted for interval (main topic not stored).',
                mainTopicAnalyzed: true, // Indicate main topic was attempted
                mainTopicStored: mainTopicStoredSuccessfullyThisRun,
                runCountAfter: effectiveRunCountAfterThisExecution,
                intervalsNeeded: queryDetails.NumIntervals,
            }),
        };
    }
};

// --- Utility Functions (getNextDataId, triggerEmailNotification, triggerAddSubtopicLambda) ---

async function getNextDataId(counterName: string): Promise<number> {
    if (!COUNTERS_TABLE_NAME) {
        throw new Error('COUNTERS_TABLE_NAME environment variable is not set.');
    }
    console.log(`Attempting to get next ID for counter: ${counterName} from table: ${COUNTERS_TABLE_NAME}`);
    try {
        const command = new UpdateCommand({
            TableName: COUNTERS_TABLE_NAME,
            Key: { CounterName: counterName },
            UpdateExpression: 'SET CurrentValue = if_not_exists(CurrentValue, :start) + :inc',
            ExpressionAttributeValues: {
                ':inc': 1,
                ':start': 0,
            },
            ReturnValues: 'UPDATED_NEW',
        });
        const result = await docClient.send(command);

        if (result.Attributes && typeof result.Attributes.CurrentValue === 'number') {
            const nextId = result.Attributes.CurrentValue;
            console.log(`Successfully obtained next ID: ${nextId} for counter: ${counterName}`);
            return nextId;
        } else {
            // This path should ideally not be reached if Update works correctly,
            // but handle potential edge cases or initial creation race conditions.
            console.warn(`Counter ${counterName} update did not return expected attributes. Attempting read/retry.`);
            // Attempt to read the value first
            try {
                const getCmd = new GetCommand({
                    TableName: COUNTERS_TABLE_NAME,
                    Key: { CounterName: counterName },
                });
                const getResult = await docClient.send(getCmd);
                if (getResult.Item && typeof getResult.Item.CurrentValue === 'number') {
                    console.log(`Found existing counter value ${getResult.Item.CurrentValue}. Retrying update.`);
                    // Retry the update once more
                    const retryResult = await docClient.send(command);
                    if (retryResult.Attributes && typeof retryResult.Attributes.CurrentValue === 'number') {
                        return retryResult.Attributes.CurrentValue;
                    }
                }
            } catch (readError) {
                console.error(`Error reading counter ${counterName} during recovery:`, readError);
            }

            // If read/retry fails, attempt initialization (Put with condition)
            console.warn(`Attempting initialization for counter ${counterName}.`);
            try {
                const putCmd = new PutCommand({
                    TableName: COUNTERS_TABLE_NAME,
                    Item: { CounterName: counterName, CurrentValue: 1 },
                    ConditionExpression: 'attribute_not_exists(CounterName)',
                });
                await docClient.send(putCmd);
                console.log(`Initialized counter ${counterName} to 1.`);
                return 1;
            } catch (initError: any) {
                if (initError.name === 'ConditionalCheckFailedException') {
                    // Another instance likely created it, retry the original update command
                    console.log(`Counter ${counterName} created concurrently. Retrying initial update.`);
                    const finalRetryResult = await docClient.send(command);
                    if (finalRetryResult.Attributes && typeof finalRetryResult.Attributes.CurrentValue === 'number') {
                        return finalRetryResult.Attributes.CurrentValue;
                    } else {
                        throw new Error(
                            `Failed to update counter ${counterName} even after initialization race condition.`,
                        );
                    }
                } else {
                    console.error(`Error initializing counter ${counterName}:`, initError);
                    throw new Error(`Failed to initialize counter ${counterName}: ${initError.message}`);
                }
            }
        }
    } catch (error) {
        console.error(`Error getting next ID for counter ${counterName}:`, error);
        throw new Error(
            `Failed to get next ID for ${counterName}: ${error instanceof Error ? error.message : String(error)}`,
        );
    }
}

async function triggerEmailNotification(queryDetails: QueryDetails): Promise<void> {
    if (!queryDetails.Email) {
        console.warn(`QueryID ${queryDetails.QueryID} has no email address associated. Skipping email notification.`);
        return;
    }

    const snsClient = new SNSClient({});
    const response = await snsClient.send(
        new PublishCommand({
            Message: `Your Bluesky sentiment analysis for the topic "${queryDetails.Topic}" (QueryID: ${queryDetails.QueryID}) has completed all ${queryDetails.NumIntervals} intervals. You can now view the results.`,
            Subject: `Bluesky Analysis Completed: ${queryDetails.Topic}`,
            TopicArn: TOPIC_ARN,
            MessageAttributes: {
                event: {
                    DataType: 'String',
                    StringValue: queryDetails.Email, // Use email as a filter
                },
            },
        }),
    );
    console.log(`Email notification sent to ${queryDetails.Email} with message ID: ${response.MessageId}`);
    console.log(response);
}

async function triggerAddSubtopicLambda(queryId: number, subtopic: string): Promise<void> {
    const ADD_SUBTOPIC_LAMBDA_NAME = process.env.ADD_SUBTOPIC_LAMBDA_NAME || 'addSubtopic'; // Use env var

    if (!ADD_SUBTOPIC_LAMBDA_NAME) {
        console.warn('ADD_SUBTOPIC_LAMBDA_NAME environment variable not set. Skipping adding subtopic.');
        return;
    }

    // Ensure subtopic isn't excessively long if there are DB limits
    const MAX_SUBTOPIC_LENGTH = 255; // Example limit
    const truncatedSubtopic =
        subtopic.length > MAX_SUBTOPIC_LENGTH ? subtopic.substring(0, MAX_SUBTOPIC_LENGTH) : subtopic;

    if (!truncatedSubtopic) {
        console.warn(`Skipping empty or invalid subtopic for QueryID ${queryId}.`);
        return;
    }

    const payload = {
        QueryID: queryId,
        Subtopic: truncatedSubtopic, // Send potentially truncated subtopic
    };

    console.log(
        `Invoking addSubtopic Lambda: ${ADD_SUBTOPIC_LAMBDA_NAME} for QueryID: ${queryId}, Subtopic: "${truncatedSubtopic}"`,
    );

    try {
        const command = new InvokeCommand({
            FunctionName: ADD_SUBTOPIC_LAMBDA_NAME,
            InvocationType: InvocationType.Event, // Fire-and-forget
            Payload: JSON.stringify(payload),
        });
        await lambdaClient.send(command);
        console.log(
            `Successfully invoked addSubtopic Lambda for QueryID: ${queryId}, Subtopic: "${truncatedSubtopic}"`,
        );
    } catch (error) {
        console.error(
            `Error invoking addSubtopic Lambda ${ADD_SUBTOPIC_LAMBDA_NAME} for subtopic "${truncatedSubtopic}":`,
            error,
        );
        // Log error but don't fail the main lambda execution
    }
}
