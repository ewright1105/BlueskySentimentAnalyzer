import React from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";
import { View, useTheme } from '@aws-amplify/ui-react';
import { formatTimestamp, formatXAxis } from '../utils/formatters';

function SentimentChart({ data }) {
  const { tokens } = useTheme();

  // Define colors using theme tokens for consistency
  const positiveColor = tokens?.colors?.green?.[60] ?? '#3d8b4a'; // Fallback color
  const negativeColor = tokens?.colors?.red?.[60] ?? '#d13212';
  const neutralColor = tokens?.colors?.neutral?.[80] ?? '#5f6369';
  const mixedColor = tokens?.colors?.purple?.[60] ?? '#7b55a9';

  if (!data || data.length === 0) {
      return <View>No chart data available.</View>; // Handle empty data case
  }

  return (
    <View style={{ width: '100%', height: 350 }}>
      <ResponsiveContainer>
         <LineChart data={data} margin={{ top: 5, right: 30, left: 20, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis
              dataKey="CreatedAt" // Should be milliseconds timestamp
              tickFormatter={formatXAxis}
            />
            <YAxis label={{ value: 'Posts', angle: -90, position: 'insideLeft' }}/>
            {/* Tooltip labelFormatter expects milliseconds */}
            <Tooltip
                labelFormatter={(label) => formatTimestamp(label)} // Format the timestamp for the tooltip title
                formatter={(value, name) => [`${value ?? 0} Posts`, name]} // Handle potential null/undefined values
            />
            <Legend />
            {/* Ensure dataKeys match the processed data structure exactly */}
            <Line type="monotone" dataKey="PositivePosts" name="Positive" stroke={positiveColor} activeDot={{ r: 6 }} dot={false}/>
            <Line type="monotone" dataKey="NegativePosts" name="Negative" stroke={negativeColor} dot={false} />
            <Line type="monotone" dataKey="NeutralPosts" name="Neutral" stroke={neutralColor} dot={false} />
            <Line type="monotone" dataKey="MixedPosts" name="Mixed" stroke={mixedColor} dot={false} />
         </LineChart>
      </ResponsiveContainer>
    </View>
  );
}

export default SentimentChart;