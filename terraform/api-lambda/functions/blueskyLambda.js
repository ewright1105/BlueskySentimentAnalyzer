"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
const api_1 = require("@atproto/api");
const client_comprehend_1 = require("@aws-sdk/client-comprehend");
const client_dynamodb_1 = require("@aws-sdk/client-dynamodb");
const lib_dynamodb_1 = require("@aws-sdk/lib-dynamodb");
const client_scheduler_1 = require("@aws-sdk/client-scheduler");
// --- Constants ---
const BSKY_SERVICE = 'https://bsky.social';
const DATA_COUNTER_NAME = 'DataCounter';
// POST_LIMIT is now fetched from QueryDetails
// --- AWS Clients ---
const comprehendClient = new client_comprehend_1.ComprehendClient({ region: process.env.AWS_REGION });
const dynamoClient = new client_dynamodb_1.DynamoDBClient({ region: process.env.AWS_REGION });
const docClient = lib_dynamodb_1.DynamoDBDocumentClient.from(dynamoClient);
const schedulerClient = new client_scheduler_1.SchedulerClient({ region: process.env.AWS_REGION });
// --- Table Names from Environment Variables ---
const QUERIES_TABLE_NAME = process.env.QUERIES_TABLE_NAME;
const DATA_TABLE_NAME = process.env.DATA_TABLE_NAME;
const COUNTERS_TABLE_NAME = 'CountersData'; //process.env.COUNTERS_TABLE_NAME;
// --- DynamoDB Helper Functions ---
/**
 * Fetches query details from the Queries DynamoDB table.
 * Assumes QueryID is the Partition Key.
 */
async function getQueryDetails(queryId, topic) {
    if (!QUERIES_TABLE_NAME) {
        throw new Error('QUERIES_TABLE_NAME environment variable is not set.');
    }
    console.log(`Fetching details for QueryID: ${queryId} from table: ${QUERIES_TABLE_NAME}`);
    try {
        const command = new lib_dynamodb_1.GetCommand({
            TableName: QUERIES_TABLE_NAME,
            Key: { QueryID: queryId, Topic: topic },
        });
        const result = await docClient.send(command);
        if (!result.Item) {
            throw new Error(`Query details not found for QueryID: ${queryId}`);
        }
        console.log('Successfully fetched query details.');
        return result.Item;
    }
    catch (error) {
        console.error(`Error fetching query details for QueryID ${queryId}:`, error);
        throw new Error(`Failed to fetch query details: ${error instanceof Error ? error.message : String(error)}`);
    }
}
/**
 * Stores the sentiment analysis summary in the Data DynamoDB table.
 * Assumes QueryID is the Partition Key and CreatedAt (analysis timestamp) is the Sort Key.
 */
async function storeAnalysisResults(summary) {
    if (!DATA_TABLE_NAME) {
        throw new Error('DATA_TABLE_NAME environment variable is not set.');
    }
    const dataId = await getNextDataId(DATA_COUNTER_NAME);
    console.log(`Storing analysis results for QueryID: ${summary.queryId} in table: ${DATA_TABLE_NAME}`);
    try {
        const item = {
            DataID: dataId,
            QueryID: summary.queryId,
            AnalysisTimestamp: summary.timestamp,
            Topic: summary.topic,
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
            // RawPosts: postsWithSentiment // Optional: Store raw posts (can get large!)
        };
        const command = new lib_dynamodb_1.PutCommand({
            TableName: DATA_TABLE_NAME,
            Item: item,
        });
        await docClient.send(command);
        console.log(`Successfully stored analysis results for QueryID ${summary.queryId} at ${summary.timestamp}`);
    }
    catch (error) {
        console.error(`Error storing analysis results for QueryID ${summary.queryId}:`, error);
        throw new Error(`Failed to store analysis results: ${error instanceof Error ? error.message : String(error)}`);
    }
}
/**
 * Deletes the EventBridge Schedule associated with a QueryID.
 */
async function deleteSchedule(queryId) {
    const scheduleName = `BlueskyAnalysis-Query-${queryId}`;
    // Assuming 'default' group name, adjust if different
    const groupName = process.env.SCHEDULER_GROUP_NAME || 'default';
    console.log(`Attempting to delete schedule: ${scheduleName} in group: ${groupName}`);
    try {
        const deleteCommand = new client_scheduler_1.DeleteScheduleCommand({
            Name: scheduleName,
            GroupName: groupName,
        });
        await schedulerClient.send(deleteCommand);
        console.log(`Successfully deleted schedule: ${scheduleName}`);
    }
    catch (error) {
        // Handle errors, e.g., schedule not found (might have been deleted already)
        if (error instanceof Error && error.name === 'ResourceNotFoundException') {
            console.log(`Schedule ${scheduleName} not found in group ${groupName}, likely already deleted.`);
        }
        else {
            console.error(`Error deleting schedule ${scheduleName} in group ${groupName}:`, error);
            // Don't throw here usually, just log, as the main task might have succeeded.
        }
    }
}
// --- Type Guard ---
function isScheduledEvent(event) {
    return event.source === 'aws.scheduler' && event['detail-type'] === 'Scheduled Event';
}
// --- Lambda Handler ---
const handler = async (event, context) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    let queryId;
    let topicFromEvent; // Topic might come from event or DB
    // --- 1. Extract Query Info from Event ---
    if (isScheduledEvent(event)) {
        console.log('Detected Scheduled Event from EventBridge Scheduler.');
        queryId = event.detail?.queryId;
        topicFromEvent = event.detail?.topic; // May or may not be present/needed
        if (typeof queryId !== 'number') {
            console.error('Scheduled event missing required detail property (queryId: number). Event detail:', event.detail);
            throw new Error('Invalid scheduled event payload: Missing queryId.');
        }
        console.log(`Processing scheduled job for QueryID: ${queryId}`);
        if (topicFromEvent) {
            console.log(`Topic hint from event: "${topicFromEvent}" (will be confirmed from DB)`);
        }
    }
    else {
        // Handle other invocation types (e.g., API Gateway for testing)
        console.log('Detected non-scheduled event (e.g., API Gateway, manual invocation).');
        if ('queryStringParameters' in event && event.queryStringParameters?.topic) {
            topicFromEvent = event.queryStringParameters.topic;
            console.error('Direct API Gateway invocation is not fully supported for scheduled tasks.');
            // Need a way to get queryId for testing if not provided.
            // For now, require queryId for testing via API GW as well.
            if (event.queryStringParameters?.queryId && !isNaN(parseInt(event.queryStringParameters.queryId, 10))) {
                queryId = parseInt(event.queryStringParameters.queryId, 10);
                console.log(`Manual invocation for QueryID: ${queryId}, Topic: "${topicFromEvent}"`);
            }
            else {
                console.error('Manual invocation requires queryId query string parameter.');
                return {
                    statusCode: 400,
                    body: JSON.stringify({ message: "Manual invocation requires 'queryId' parameter." }),
                };
            }
        }
        else {
            console.error('Unsupported event type or missing parameters.');
            return {
                statusCode: 400,
                body: JSON.stringify({ message: 'Unsupported event type or missing parameters.' }),
            };
        }
    }
    // --- Ensure Table Names are Set ---
    if (!QUERIES_TABLE_NAME || !DATA_TABLE_NAME) {
        console.error('Missing environment variables: QUERIES_TABLE_NAME or DATA_TABLE_NAME');
        throw new Error('Server configuration error: Missing table names.');
    }
    // --- 2. Fetch Query Details from DynamoDB ---
    let queryDetails;
    try {
        // Use the dedicated function to fetch details
        queryDetails = await getQueryDetails(queryId, topicFromEvent);
        console.log('Fetched Query Details:', queryDetails);
        // Validate status
        if (queryDetails.Status === 'COMPLETED' || queryDetails.Status === 'CANCELLED') {
            console.log(`Query ${queryId} is already in status ${queryDetails.Status}. Skipping execution.`);
            // Attempt to delete schedule just in case it wasn't cleaned up
            await deleteSchedule(queryId);
            return;
        }
    }
    catch (error) {
        console.error(`Error during query detail fetch or validation for QueryID ${queryId}:`, error);
        // Let the error propagate to Lambda runtime for retries/failure handling
        throw error;
    }
    // --- 3. Check Run Count ---
    let currentRunCount = 0;
    try {
        console.warn(`Using SCAN operation on table '${DATA_TABLE_NAME}' to count runs for QueryID ${queryId}. This can be inefficient on large tables. Consider adding a GSI on QueryID.`);
        // Use Scan with a FilterExpression (less efficient)
        const scanCmd = new lib_dynamodb_1.ScanCommand({
            // <--- Use ScanCommand
            TableName: DATA_TABLE_NAME,
            FilterExpression: 'QueryID = :qid',
            ExpressionAttributeValues: { ':qid': queryId },
            Select: 'COUNT', // <--- Get only the count
        });
        const countResult = await docClient.send(scanCmd); // <--- Send the ScanCommand
        currentRunCount = countResult.Count ?? 0;
        console.log(`Current run count for QueryID ${queryId} (using Scan): ${currentRunCount}`);
    }
    catch (error) {
        console.error(`Error fetching run count using SCAN for QueryID ${queryId}:`, error);
        if (error instanceof Error && error.message.includes('ProvisionedThroughputExceededException')) {
            console.warn(`Provisioned throughput likely exceeded during SCAN operation. SCAN is resource-intensive.`);
        }
        throw new Error(`Failed to fetch run count: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (currentRunCount >= queryDetails.NumIntervals) {
        console.log(`QueryID ${queryId} has reached the desired number of intervals (${queryDetails.NumIntervals}). Stopping.`);
        // Optional: Update Query Status to COMPLETED in Queries table here if needed
        await deleteSchedule(queryId); // Ensure schedule is deleted
        return;
    }
    // --- 4. Get Bluesky Credentials ---
    const identifier = process.env.BLUESKY_HANDLE;
    const password = process.env.BLUESKY_APP_PASSWORD;
    if (!identifier || !password) {
        console.error('Missing Bluesky credentials in environment variables');
        throw new Error('Server configuration error: Missing Bluesky credentials.');
    }
    // --- 5. Initialize and Authenticate Bluesky Agent ---
    const agent = new api_1.BskyAgent({ service: BSKY_SERVICE });
    try {
        console.log(`Attempting Bluesky login for handle: ${identifier}`);
        await agent.login({ identifier, password });
        console.log('Bluesky login successful.');
    }
    catch (loginError) {
        console.error('Bluesky login failed:', loginError);
        throw new Error(`Bluesky authentication failed: ${loginError instanceof Error ? loginError.message : String(loginError)}`);
    }
    // --- 6. Search for Posts ---
    let searchResults;
    const searchTerm = queryDetails.Topic; // Use topic from fetched details
    const postLimit = queryDetails.PostsToAnalyze; // Use limit from fetched details
    try {
        console.log(`Searching posts for "${searchTerm}" with limit ${postLimit}...`);
        searchResults = await agent.app.bsky.feed.searchPosts({
            q: searchTerm,
            limit: postLimit,
            // cursor: TODO: Consider pagination strategy if needed
        });
        console.log(`Found ${searchResults.data.posts.length} posts.`);
    }
    catch (searchError) {
        console.error('Error searching Bluesky posts:', searchError);
        throw new Error(`Failed to search Bluesky posts: ${searchError instanceof Error ? searchError.message : String(searchError)}`);
    }
    // --- 7. Analyze Sentiment ---
    console.log('Analyzing sentiment for fetched posts...');
    const postsWithSentiment = await Promise.all(searchResults.data.posts.map(async (post) => {
        // Type assertion for record, handle potential missing text
        const postRecord = post.record;
        const postText = postRecord?.text;
        if (!postText || postText.trim() === '') {
            console.warn(`Post URI ${post.uri} has no text content or is empty.`);
            // Return the original post without sentiment analysis
            return post;
        }
        let textToAnalyze = postText;
        const byteLength = Buffer.byteLength(postText, 'utf8');
        const MAX_BYTES = 4990; // Slightly less than 5000 for safety
        if (byteLength > MAX_BYTES) {
            console.warn(`Post text (URI: ${post.uri}) exceeds ${MAX_BYTES} bytes (${byteLength}), truncating.`);
            const buffer = Buffer.from(postText, 'utf8');
            textToAnalyze = buffer.slice(0, MAX_BYTES).toString('utf8');
            // Add check for incomplete multi-byte characters if necessary, though toString usually handles this
        }
        // TODO: Implement language detection or get language from post if available
        const languageCode = 'en'; // Hardcoded for now
        const params = {
            Text: textToAnalyze,
            LanguageCode: languageCode,
        };
        try {
            const command = new client_comprehend_1.DetectSentimentCommand(params);
            const sentimentData = await comprehendClient.send(command);
            return {
                post,
                sentimentAnalysis: {
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
                },
            };
        }
        catch (comprehendError) {
            console.error(`Error analyzing sentiment for post URI ${post.uri}:`, comprehendError);
            return {
                post,
                sentimentAnalysis: {
                    sentiment: undefined,
                    scores: undefined,
                    languageCode: languageCode,
                    error: comprehendError instanceof Error ? comprehendError.message : String(comprehendError),
                },
            };
        }
    }));
    console.log('Sentiment analysis complete.');
    // --- 8. Calculate Summary ---
    let positivePosts = 0;
    let negativePosts = 0;
    let neutralPosts = 0;
    let mixedPosts = 0;
    let totalPositiveScore = 0;
    let totalNegativeScore = 0;
    let totalNeutralScore = 0;
    let totalMixedScore = 0;
    let analyzedCount = 0; // Count posts where sentiment analysis was successful
    postsWithSentiment.forEach((p) => {
        // Check if sentimentAnalysis exists and there was no error during analysis
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
        else if (p.sentimentAnalysis?.error) {
            console.warn(`Skipping post in summary due to sentiment analysis error: ${p.sentimentAnalysis.error}`);
        }
        else if (!p.sentimentAnalysis) {
            console.warn(`Skipping post in summary as it had no text or analysis was skipped.`);
        }
    });
    const summary = {
        queryId: queryId,
        topic: searchTerm,
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
    console.log('Sentiment Summary:', JSON.stringify(summary, null, 2));
    // --- 9. Store Results in DynamoDB (Data Table) ---
    try {
        // Use the dedicated function to store results
        await storeAnalysisResults(summary);
    }
    catch (error) {
        console.error(`Error during result storage for QueryID ${queryId}:`, error);
        // Let the error propagate to Lambda runtime
        throw error;
    }
    // --- 10. Check if this was the last run and delete schedule ---
    // Check run count *after* storing results for the current run
    if (currentRunCount + 1 >= queryDetails.NumIntervals) {
        console.log(`QueryID ${queryId} has now completed its final interval (${currentRunCount + 1}/${queryDetails.NumIntervals}).`);
        // Optional: Update Query Status to COMPLETED in Queries table
        await deleteSchedule(queryId); // Delete the schedule after the final successful run
    }
    // --- 11. Return ---
    console.log(`Execution for QueryID ${queryId} completed successfully.`);
    // No explicit return needed for successful scheduled event processing
    // If invoked via API Gateway for testing, return the summary:
    if (!isScheduledEvent(event)) {
        return { statusCode: 200, body: JSON.stringify(summary) };
    }
};
exports.handler = handler;
async function getNextDataId(counterName) {
    if (!COUNTERS_TABLE_NAME) {
        throw new Error('COUNTERS_TABLE_NAME environment variable is not set.');
    }
    console.log(`Attempting to get next ID for counter: ${counterName} from table: ${COUNTERS_TABLE_NAME}`);
    try {
        const command = new lib_dynamodb_1.UpdateCommand({
            TableName: COUNTERS_TABLE_NAME,
            Key: { CounterName: counterName },
            UpdateExpression: 'SET CurrentValue = if_not_exists(CurrentValue, :start) + :inc',
            ExpressionAttributeValues: {
                ':inc': 1,
                ':start': 0, // Start counter at 0 if it doesn't exist, first ID will be 1
            },
            ReturnValues: 'UPDATED_NEW',
        });
        const result = await docClient.send(command);
        if (result.Attributes && typeof result.Attributes.CurrentValue === 'number') {
            const nextId = result.Attributes.CurrentValue;
            console.log(`Successfully obtained next ID: ${nextId} for counter: ${counterName}`);
            return nextId;
        }
        else {
            throw new Error('Failed to parse CurrentValue from UpdateCommand response.');
        }
    }
    catch (error) {
        console.error(`Error getting next ID for counter ${counterName}:`, error);
        // Consider adding retry logic here if needed, although atomic counters are generally reliable
        throw new Error(`Failed to get next ID for ${counterName}: ${error instanceof Error ? error.message : String(error)}`);
    }
}
//# sourceMappingURL=app.js.map