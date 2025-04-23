import React from 'react';
import {
  Button,
  Text,
  Heading,
  Flex,
  Card,
  useTheme
} from "@aws-amplify/ui-react";
import { formatTimestamp, formatDuration } from '../utils/formatters';

function TopicCard({ topic, onViewDetails, isDisabled }) {
  const { tokens } = useTheme();

  // const handleDeleteClick = () => {
  //   if (window.confirm(`Are you sure you want to delete the topic "${topic.topic}"?`)) {
  //       onDelete(topic);
  //   }
  // };

  const handleViewClick = () => {
    onViewDetails(topic);
  };

  return (
    <Card key={topic.queryId} variation="outlined" padding={tokens?.space?.medium ?? '1rem'}>
      <Flex direction="column" gap={tokens?.space?.small ?? '0.75rem'}>
        <Heading level={4}>{topic.topic}</Heading>
        <Text fontSize="small" color="font.secondary">
          Duration: {formatDuration(topic)}
        </Text>
         <Text fontSize="xs" color="font.tertiary">
           Added: {formatTimestamp(topic.createdAt)}
        </Text>
        <Flex direction="row" justifyContent="space-between" alignItems="center" marginTop="small">
          <Button
            size="small"
            variation="link"
            onClick={handleViewClick}
            isDisabled={isDisabled}
          >
            View Details
          </Button>
        </Flex>
      </Flex>
    </Card>
  );
}

export default TopicCard;