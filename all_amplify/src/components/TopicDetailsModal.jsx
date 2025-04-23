import React, { useState, useEffect, useCallback } from 'react'; // Added useCallback
import {
    View,
    Card,
    Flex,
    Heading,
    Button,
    Divider,
    Loader,
    Alert,
    Text,
    useTheme,
    Radio,
    RadioGroupField,
} from "@aws-amplify/ui-react";
import SentimentChart from './SentimentChart';
import IntervalList from './IntervalList';
import { parseApiTimestampToMillis } from '../utils/formatters';

const API_BASE_URL = import.meta.env.VITE_API_ENDPOINT;

function TopicDetailsModal({ isOpen, onClose, topic }) {
    const { tokens } = useTheme();
    const [sentimentData, setSentimentData] = useState([]);
    const [subtopics, setSubtopics] = useState([]); // <-- State for subtopics
    const [selectedGraphTopic, setSelectedGraphTopic] = useState(''); // <-- State for selected radio value
    const [isLoadingSentiment, setIsLoadingSentiment] = useState(false);
    const [isLoadingSubtopics, setIsLoadingSubtopics] = useState(false); // <-- Separate loading for subtopics
    const [error, setError] = useState(null);

    // --- Fetch Sentiment Data ---
    // Use useCallback to memoize the function if needed, especially if passed as prop
    const fetchSentimentData = useCallback(async (queryId, graphTopic) => {
        // Ensure we have a topic to filter by
        if (!graphTopic) {
            console.log("Skipping sentiment fetch: graphTopic is not set yet.");
            setSentimentData([]); // Clear data if no topic selected
            return;
        }

        console.log(`Fetching sentiment data for QueryID: ${queryId}, Topic: ${graphTopic}`);
        setIsLoadingSentiment(true);
        setError(null); // Clear previous errors specific to sentiment fetch
        setSentimentData([]); // Clear previous data

        try {
            const apiUrl = `${API_BASE_URL}/data/retrieve?QueryID=${queryId}`;
            const response = await fetch(apiUrl, {
                method: 'GET',
                headers: { 'Accept': 'application/json' }
            });

            if (!response.ok) throw await generateError(response, 'sentiment data');

            let allData = await response.json();
            console.log("Raw Modal Sentiment Data:", allData);

            if (!Array.isArray(allData)) {
                 if (typeof allData === 'object' && allData !== null && allData.message) {
                    throw new Error(`API returned an error message: ${allData.message}`);
                 }
                 throw new Error("Received invalid data format (expected an array).");
            }

            // Filter data based on the *selected* graph topic
            const filteredData = allData.filter(element => element.Topic === graphTopic);
            console.log(`Filtered Modal Sentiment Data for ${graphTopic}:`, filteredData);

            const processedData = filteredData
                .map(item => {
                    const createdAtMs = parseApiTimestampToMillis(item.CreatedAt);
                    if (createdAtMs === null) {
                        console.warn("Invalid CreatedAt - skipping:", item.DataID, item.CreatedAt);
                        return null;
                    }
                    return {
                        ...item,
                        CreatedAt: createdAtMs,
                        PositivePosts: Number(item.PositivePosts ?? 0),
                        NegativePosts: Number(item.NegativePosts ?? 0),
                        NeutralPosts: Number(item.NeutralPosts ?? 0),
                        MixedPosts: Number(item.MixedPosts ?? 0),
                        PostsAnalyzed: item.PostsAnalyzed
                    };
                })
                .filter(item => item !== null);

            const sortedData = processedData.sort((a, b) => a.CreatedAt - b.CreatedAt);

            if (sortedData.length === 0 && filteredData.length > 0) {
                console.warn("All filtered data points had invalid timestamps.");
                setError("Could not display data: Timestamps missing or invalid.");
            } else if (sortedData.length === 0 && filteredData.length === 0) {
                 console.log(`No sentiment data found for topic: ${graphTopic}`);
                 // Optional: Set a specific message like setError(`No data found for ${graphTopic}`)
            }

            setSentimentData(sortedData);

        } catch (err) {
            console.error("Error fetching modal sentiment data:", err);
            setError(`Failed to fetch details for ${graphTopic}. ${err.message || 'Please try again.'}`);
            setSentimentData([]); // Clear data on error
        } finally {
            setIsLoadingSentiment(false);
        }
    }, []); // No dependencies needed if API_BASE_URL and parseApiTimestampToMillis are stable

    // --- Fetch Subtopics ---
    const fetchSubtopics = useCallback(async (queryId) => {
        console.log(`Fetching subtopics for QueryID: ${queryId}`);
        setIsLoadingSubtopics(true);
        setSubtopics([]); // Clear previous subtopics
        // Don't clear the main 'error' state here, keep it for sentiment errors
        let subtopicError = null; // Local error state for this fetch

        try {
            const apiUrl = `${API_BASE_URL}/subtopics/retrieve?QueryID=${queryId}`;
            const response = await fetch(apiUrl, {
                method: 'GET',
                headers: {
                    'Accept': 'application/json',
                    // REMOVED CLIENT-SIDE CORS HEADERS - Fix CORS on the SERVER (API Gateway)
                }
            });

            if (!response.ok) throw await generateError(response, 'subtopics');

            let data = await response.json();
            console.log("Raw Subtopic Data:", data);

            // Assuming data is an array like [{Subtopic: 'A'}, {Subtopic: 'B'}, ...]
            // Adjust '.Subtopic' if the actual property name is different
            const extractedSubtopics = data.slice(0, 3).map(item => item.Subtopic).filter(Boolean); // Take top 3 and filter out any null/empty
            console.log("Extracted Subtopics:", extractedSubtopics);
            setSubtopics(extractedSubtopics);

        } catch (err) {
            console.error("Error fetching subtopics:", err);
            // Set a specific error or potentially display it separately
            // setError(`Failed to fetch subtopics. ${err.message}`); // Or use a dedicated subtopic error state
            subtopicError = `Failed to load subtopics. ${err.message}`; // Store locally for now
            setSubtopics([]); // Ensure subtopics are empty on error
        } finally {
            setIsLoadingSubtopics(false);
            // Optionally display the subtopicError somewhere
            if (subtopicError) {
                 console.error(subtopicError); // Log it at least
                 // You could update the main error state, but it might overwrite sentiment errors
                 // setError(prev => prev ? `${prev}\n${subtopicError}` : subtopicError);
            }
        }
    }, []); // No dependencies needed if API_BASE_URL is stable

    // --- Effect for Initial Load ---
    useEffect(() => {
        if (isOpen && topic?.queryId) {
            console.log(`Modal opened for QueryID: ${topic.queryId}, Topic: ${topic.topic}`);
            // Set the initial selected topic
            setSelectedGraphTopic(topic.topic);
            // Fetch data for the initial topic
            fetchSentimentData(topic.queryId, topic.topic);
            // Fetch subtopics
            fetchSubtopics(topic.queryId);
        } else {
            // Reset state when modal closes or topic is invalid
            setSentimentData([]);
            setSubtopics([]);
            setSelectedGraphTopic('');
            setError(null);
            setIsLoadingSentiment(false);
            setIsLoadingSubtopics(false);
        }
        // Dependencies: Trigger when modal opens/closes or the main topic changes
    }, [isOpen, topic?.queryId, topic?.topic, fetchSentimentData, fetchSubtopics]);

    // --- Handle Radio Button Change ---
    const handleRadioChange = (event) => {
        const newSelectedTopic = event.target.value;
        console.log("Radio changed to:", newSelectedTopic);
        setSelectedGraphTopic(newSelectedTopic);
        // Fetch sentiment data for the newly selected topic/subtopic
        if (topic?.queryId) {
             fetchSentimentData(topic.queryId, newSelectedTopic);
        } else {
             console.error("Cannot fetch data: QueryID is missing.");
             setError("Cannot fetch data: QueryID is missing.");
        }
    };

    // --- Helper for generating API Error messages ---
    async function generateError(response, dataType) {
         let errorBody = `API Error fetching ${dataType}: ${response.status} ${response.statusText}`;
         try {
             const errData = await response.json();
             errorBody = `API Error ${response.status} fetching ${dataType}: ${errData.error || errData.message || JSON.stringify(errData)}`;
         } catch (parseError) {
             console.log("Could not parse error response body:", parseError);
         }
         return new Error(errorBody);
     }


    // --- Render Logic ---
    if (!isOpen || !topic) {
        return null;
    }

    const isLoading = isLoadingSentiment || isLoadingSubtopics; // Combined loading state for general loader

    return (
        <View  position="fixed"
        top="0"
        left="0"
        width="100vw"
        height="100vh"
        backgroundColor={tokens.colors.overlay['50']}
        display="flex"
        justifyContent="center"
        alignItems="center"
        onClick={onClose} // Close modal on backdrop click 
        >
            <Card variation="elevated"
        maxWidth="90%"
        width="800px"
        maxHeight="90vh"
        padding={tokens.space.large}
        backgroundColor={tokens.colors.background.primary}
        borderRadius={tokens.radii.medium}
        boxShadow={tokens.shadows.large}
        overflow="auto"
        onClick={(e) => e.stopPropagation()}>
                <Flex direction="column" gap={tokens.space.medium}>
                    {/* Header */}
                    <Flex justifyContent="space-between" alignItems="center">
                        <Heading level={2}>Details for: {topic.topic}</Heading>
                        <Button variation="primary" onClick={onClose} size="large">Close</Button>
                    </Flex>
                    <Divider />

                    {/* Body */}
                    {/* Show loader if either fetch is happening */}
                    {isLoading && <Flex justifyContent="center" padding={tokens.space.xl}><Loader size="large" /></Flex>}

                    {/* Show main error if present (could be from sentiment or other issues) */}
                    {error && !isLoading && <Alert variation="error" heading="Error Loading Details">{error}</Alert>}

                    {/* Content Area - Render even if loading, components inside can handle their data */}
                    {!isLoading && !error && (
                        <Flex direction="column" gap={tokens.space.large}>
                            {/* Radio Buttons for Topic/Subtopics */}
                            <RadioGroupField
                                legend="Select Topic/Subtopic"
                                name="graphTopic"
                                direction="row"
                                value={selectedGraphTopic} // <-- Controlled component
                                onChange={handleRadioChange} // <-- Update state on change
                                isDisabled={isLoadingSubtopics || isLoadingSentiment} // Disable while loading
                            >
                                <Radio value={topic.topic}>{topic.topic}</Radio>
                                {/* Render subtopic radios only if subtopics exist */}
                                {subtopics.map((sub, index) => (
                                    <Radio key={index} value={sub}>{sub}</Radio>
                                ))}
                                {/* Optional: Show indicator if subtopics failed to load */}
                                {isLoadingSubtopics && <Text fontSize="small" fontStyle="italic"> (Loading subtopics...)</Text>}
                                {!isLoadingSubtopics && subtopics.length === 0 && topic.queryId && <Text fontSize="small" fontStyle="italic"> (No subtopics found or failed to load)</Text>}
                             </RadioGroupField>

                            {/* Chart Section - Render based on sentiment data */}
                            <View>
                                <Heading level={4} marginBottom={tokens.space.small}>
                                    Sentiment Trend {selectedGraphTopic ? `for ${selectedGraphTopic}` : ''}
                                </Heading>
                                {isLoadingSentiment ? (
                                    <Flex justifyContent="center" padding={tokens.space.medium}><Text>Loading chart data...</Text></Flex>
                                ) : sentimentData.length > 0 ? (
                                    <SentimentChart data={sentimentData} />
                                ) : (
                                    // Show message only if not loading and no error was already shown
                                    !error && <Text>No sentiment data available for "{selectedGraphTopic}".</Text>
                                )}
                            </View>

                            {/* Interval List Section - Render based on sentiment data */}
                            {isLoadingSentiment ? (
                                 <Flex justifyContent="center" padding={tokens.space.medium}><Text>Loading interval data...</Text></Flex>
                            ) : sentimentData.length > 0 ? (
                                <IntervalList data={sentimentData} />
                            ) : (
                                // Avoid duplicate "no data" message if chart already showed it
                                !error && <></>
                            )}
                        </Flex>
                    )}
                </Flex>
            </Card>
        </View>
    );
}

export default TopicDetailsModal;
