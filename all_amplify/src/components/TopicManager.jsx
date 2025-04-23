import { useState, useEffect } from "react";
import {
  Flex,
  View, // Keep View for main container
  Divider,
  Loader, // Keep for list loading state
  useTheme,
  useAuthenticator
} from "@aws-amplify/ui-react";
import { fetchUserAttributes } from "aws-amplify/auth";

// Import Helper functions
import { parseApiTimestampToMillis } from '../utils/formatters';

// Import Child Components
import Header from './Header';
import Notifications from './Notifications';
import TopicForm from './TopicForm';
import TopicList from './TopicList';
import TopicDetailsModal from './TopicDetailsModal';

const API_BASE_URL = import.meta.env.VITE_API_ENDPOINT;

function TopicManager() {
  // --- State Management ---
  const [topics, setTopics] = useState([]);
  const [isLoadingList, setIsLoadingList] = useState(true);
  const [isSubmittingForm, setIsSubmittingForm] = useState(false);
  const [error, setError] = useState(null);
  const [successMessage, setSuccessMessage] = useState(null);
  const [userEmail, setUserEmail] = useState(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [selectedTopic, setSelectedTopic] = useState(null);

  // --- Hooks ---
  const { tokens } = useTheme();
  const { user, signOut } = useAuthenticator((context) => [
    context.user,
    context.signOut,
  ]);

  // --- Effects ---

  // Effect for clearing transient messages
  useEffect(() => {
    let timer;
    if (error || successMessage) {
      timer = setTimeout(() => {
        setError(null);
        setSuccessMessage(null);
      }, 5000);
    }
    return () => clearTimeout(timer);
  }, [error, successMessage]);

  // Effect for initial fetch of user email and topic list
  useEffect(() => {
    console.log("TopicManager mounted, fetching user email...");
    setIsLoadingList(true);
    setError(null);
    setSuccessMessage(null);

    fetchUserAttributes()
      .then(attributes => {
        const email = attributes.email;
        if (!email) {
            throw new Error("Email not found in user attributes.");
        }
        setUserEmail(email);
        console.log("Fetched user email:", email);
        return fetchTopics(email);
      })
      .catch(e => {
        console.error("Error fetching user attributes or initial topics:", e);
        setError(`Initialization failed: ${e.message}. Please try refreshing.`);
        setIsLoadingList(false);
        setTopics([]);
      });
  }, []);


  // --- API Functions ---

  async function fetchTopics(currentUserEmail) {
    if (!currentUserEmail) {
      setError("User email not available, cannot fetch topics.");
      setIsLoadingList(false);
      return;
    }
    console.log("Attempting to fetch topics for user:", currentUserEmail);
    try {
      const response = await fetch(`${API_BASE_URL}/queries/retrieve?Email=${encodeURIComponent(currentUserEmail)}`, {
          method: 'GET',
          headers: { 'Accept': 'application/json' }
      });
      if (!response.ok) {
           let errorBody = `API Error ${response.status} ${response.statusText}`;
           try { const errData = await response.json(); errorBody = `API Error ${response.status}: ${errData.error || errData.message || JSON.stringify(errData)}`; } catch (e) { /* ignore */ }
           throw new Error(errorBody);
      }
      const data = await response.json();

      if (!Array.isArray(data)) {
          if (typeof data === 'object' && data !== null && data.message) { throw new Error(`API returned an error: ${data.message}`); }
          throw new Error("Invalid data format received from API (expected an array).");
      }

      const processedTopics = data
        .map(element => {
            if (!element || element.QueryID === undefined || element.QueryID === null) {
                console.warn("Topic data missing QueryID, skipping:", element); return null;
            }
            const createdAtMs = parseApiTimestampToMillis(element.CreatedAt);
            return {
              queryId: element.QueryID,
              topic: element.Topic || "Untitled Topic",
              intervalLength: Number(element.IntervalLength) || 1,
              intervalUnit: element.IntervalUnit || "minutes",
              numberOfIntervals: Number(element.NumIntervals) || 1,
              createdAt: createdAtMs ?? Date.now(),
            };
        })
        .filter(topic => topic !== null);

      processedTopics.sort((a, b) => b.createdAt - a.createdAt);
      console.log("Successfully fetched and processed topics:", processedTopics);
      setTopics(processedTopics);

    } catch (err) {
      console.error("Catch block: Error fetching topics:", err);
      setError(`Failed to fetch topics: ${err.message}`);
      setTopics([]);
    } finally {
       setIsLoadingList(false);
    }
  }

  async function createTopic(event) {
     event.preventDefault();
     if (!userEmail) { setError("User email not found. Cannot create topic."); return; }
     if (isSubmittingForm || isModalOpen) return;

     setIsSubmittingForm(true);
     setError(null);
     setSuccessMessage(null);

     const form = new FormData(event.target);
     const topicValue = form.get("topic")?.toString().trim();
     const intervalLengthValue = form.get("intervalLength")?.toString();
     const intervalUnitValue = form.get("intervalUnit")?.toString();
     const numberOfIntervalsValue = form.get("numberOfIntervals")?.toString();
     const numberOfIntervalsAmount = form.get("amountPerInterval")?.toString();


    if (!topicValue || !intervalLengthValue || !intervalUnitValue || !numberOfIntervalsValue || !numberOfIntervalsAmount) {
      setError("All fields are required."); setIsSubmittingForm(false); return;
    }
    let parsedLength = parseInt(intervalLengthValue, 10);
    const parsedCount = parseInt(numberOfIntervalsValue, 10);
    const parsedAmount = parseInt(numberOfIntervalsAmount, 10);
    if (isNaN(parsedLength) || parsedLength <= 0) {
      setError("Interval Length must be a positive number."); setIsSubmittingForm(false); return;
    }
    if (isNaN(parsedCount) || parsedCount <= 0) {
       setError("Number of Intervals must be a positive number."); setIsSubmittingForm(false); return;
    }
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      setError("Amount of post must be a positive number."); setIsSubmittingForm(false); return;
   }
   console.log("interval type: " + intervalUnitValue);
    if(intervalUnitValue == "hours")
      {
        let newLength = parsedLength * 60;
        parsedLength = newLength
        console.log(parsedLength);
      }
    else if(intervalUnitValue == "days")
        {
          const newLength = parsedLength * 60 * 24;
          parsedLength = newLength
        }
     try {
      //  const response = await fetch(`${API_BASE_URL}/queries/send`, {
      //    method: 'POST',
      //    headers: { 'Content-Type': 'application/json' },
      //    body: JSON.stringify({
      //      "Email": userEmail, "Topic": topicValue, "NumIntervals": parsedCount,
      //      "PostsToAnalyze": 100, "IntervalLength": parsedLength, "IntervalUnit": intervalUnitValue,
      //    })
      //  });

      //  if (!response.ok) {
      //      let errorBody = `API Error ${response.status} ${response.statusText}`;
      //      try { const errData = await response.json(); errorBody = `API Error ${response.status}: ${errData.error || errData.message || JSON.stringify(errData)}`; } catch (e) { /* ignore */ }
      //      throw new Error(errorBody);
      //  }
      fetch(`${API_BASE_URL}/queries/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          "Email": userEmail, "Topic": topicValue, "NumIntervals": parsedCount,
          "PostsToAnalyze": parsedAmount, "IntervalLength": parsedLength, "IntervalUnit": intervalUnitValue,
        })
      }).then(response => response.json())
      .then(data => {
        const s = JSON.parse(data.body);
        // console.log(s.QueryID);

        const createdAtMs = parseApiTimestampToMillis(data.body.CreatedAt);
        const newTopicData = {
            queryId: s.QueryID|| `temp-${Date.now()}`, topic: topicValue,
            intervalLength: parsedLength, intervalUnit: intervalUnitValue,
            numberOfIntervals: parsedCount, createdAt: createdAtMs ?? Date.now()
        };

       setSuccessMessage(`Topic "${newTopicData.topic}" added successfully!`);
       setTopics(prevTopics => [newTopicData, ...prevTopics].sort((a, b) => b.createdAt - a.createdAt));
       event.target.reset();
       });

     } catch (err) {
       console.error("Error creating topic:", err);
       setError(`Failed to add topic: ${err.message}`);
     } finally {
       setIsSubmittingForm(false);
     }
  }

 

  // --- Modal Handling ---
  const handleViewDetails = (topic) => {
    setSelectedTopic(topic);
    setIsModalOpen(true);
  };

  const handleCloseModal = () => {
    setIsModalOpen(false);
    setSelectedTopic(null);
  };

  // --- Render Logic ---
  return (
     <View
       width="100%"
       maxWidth={tokens?.breakpoints?.large ?? '1024px'} 
       margin="0 auto"
       padding={{ base: tokens.space.medium, large: tokens.space.xl }}
     >
       {/* Header Component at the top */}
       <Header
           userEmail={userEmail}
           onSignOut={signOut}
           isActionDisabled={isSubmittingForm}
       />

       <Flex
        direction="column"
        alignItems="center"
        width="100%"
        gap={tokens.space.large}
        style={{
            filter: isModalOpen ? 'blur(4px)' : 'none',
            transition: 'filter 0.2s ease-out',
            pointerEvents: isModalOpen ? 'none' : 'auto',
        }}
      >
        {/* Notifications right below header, above form */}
        <Notifications
            error={error}
            successMessage={successMessage}
            onErrorDismiss={() => setError(null)}
            onSuccessDismiss={() => setSuccessMessage(null)}
        />

        {/* Topic Form */}
        <TopicForm
            onSubmit={createTopic}
            isLoading={isSubmittingForm}
        />

        <Divider marginTop={tokens.space.medium} marginBottom={tokens.space.small} />

        {/* Topic List */}
        <TopicList
            topics={topics}
            isLoading={isLoadingList}
            onViewTopicDetails={handleViewDetails}
            isActionDisabled={isSubmittingForm || isModalOpen}
        />

      </Flex>

      {/* Modal Component - Rendered outside the main blurred content Flex */}
      <TopicDetailsModal
        isOpen={isModalOpen}
        onClose={handleCloseModal}
        topic={selectedTopic}
      />
    </View>
  );
}

export default TopicManager;