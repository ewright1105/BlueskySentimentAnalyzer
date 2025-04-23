// src/components/IntervalList.jsx
import React from 'react';
import { View, Heading, Flex, Card, Text, useTheme } from '@aws-amplify/ui-react';
import { formatTimestamp } from '../utils/formatters';

function IntervalList({ data }) {
  const { tokens } = useTheme();

   if (!data || data.length === 0) {
      return <Text>No analysis interval data available.</Text>;
  }

  return (
    <View>
      <Heading level={4} marginBottom={tokens.space.small}>Analysis Intervals</Heading>
      <Flex direction="column" gap={tokens.space.small} maxHeight="300px" overflowY="auto" paddingRight="small">
        {data.map((dataPoint, index) => (
          // Prefer a unique ID from data if available (e.g., dataPoint.DataID)
          <Card key={dataPoint.DataID || `interval-${index}`} variation="outlined" padding={tokens.space.small}>
            <Flex direction="column" gap="xs">
              <Text fontWeight="bold">Interval Time: {formatTimestamp(dataPoint.CreatedAt)}</Text>
              {/* Use nullish coalescing for defaults */}
              <Text fontSize="small">Posts Analyzed: {dataPoint.PostsAnalyzed ?? 'N/A'}</Text>
              <Flex wrap="wrap" gap="xs" fontSize="small">
                 <Text>Pos: {dataPoint.PositivePosts ?? 0}</Text>
                 <Text>Neg: {dataPoint.NegativePosts ?? 0}</Text>
                 <Text>Neu: {dataPoint.NeutralPosts ?? 0}</Text>
                 <Text>Mix: {dataPoint.MixedPosts ?? 0}</Text>
              </Flex>
            </Flex>
          </Card>
        ))}
      </Flex>
    </View>
  );
}

export default IntervalList;