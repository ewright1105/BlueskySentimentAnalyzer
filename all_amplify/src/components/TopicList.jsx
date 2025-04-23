import React from 'react';
import {
  Text,
  Heading,
  Flex,
  Grid,
  Loader,
  useTheme
} from "@aws-amplify/ui-react";
import TopicCard from './TopicCard';

function TopicList({ topics, isLoading, onDeleteTopic, onViewTopicDetails, isActionDisabled }) {
  const { tokens } = useTheme();

  return (
    <Flex direction="column" width="100%" gap={tokens?.space?.medium ?? '1rem'}>
      <Heading level={2}>Saved Topics</Heading>
      {isLoading ? (
        <Flex justifyContent="center" padding={tokens?.space?.large ?? '1.5rem'}><Loader size="large" /></Flex>
      ) : !topics || !topics.length ? (
        <Text>No topics added yet. Use the form above to add one.</Text>
      ) : (
        <Grid
          templateColumns={{ base: "1fr", medium: `repeat(auto-fit, minmax(300px, 1fr))` }}
          gap={tokens?.space?.medium ?? '1rem'} >
          {topics.map((topic) => (
            <TopicCard
              key={topic.queryId}
              topic={topic}
              onViewDetails={onViewTopicDetails}
              isDisabled={isActionDisabled}
            />
          ))}
        </Grid>
      )}
    </Flex>
  );
}

export default TopicList;