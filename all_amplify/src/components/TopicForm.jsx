import React from 'react';
import {
  Button,
  TextField,
  Heading,
  Flex,
  View, // Keep View for the form element itself if Card is used as wrapper
  Grid,
  SelectField,
  useTheme,
  Card,
} from "@aws-amplify/ui-react";

function TopicForm({ onSubmit, isLoading }) {
  const { tokens } = useTheme();

  return (
    <Card
        as="form"
        onSubmit={onSubmit}
        width="100%"
        variation="outlined"
        padding={tokens.space.large} 
    >
       <Flex direction="column" gap={tokens.space.medium}>
         <Heading level={4} marginBottom={tokens.space.small}>Add New Topic</Heading>

         <TextField
            name="topic"
            placeholder="e.g., 'Taylor Swift'"
            label="Topic"
            isRequired
            disabled={isLoading}
            descriptiveText="Enter the keyword or phrase to track."
         />

         {/* Interval Configuration Grid */}
         <Grid templateColumns={{base: "1fr", small: "1fr 1fr"}} gap={tokens.space.medium} alignItems="end">
              <TextField
                name="intervalLength"
                placeholder="e.g., 10"
                label="Interval Length"
                type="number"
                min="1"
                isRequired
                disabled={isLoading}
              />
              <SelectField
                name="intervalUnit"
                label="Interval Unit"
                isRequired
                disabled={isLoading}
                defaultValue="minutes"
              >
                      <option value="minutes">Minutes</option>
                      <option value="hours">Hours</option>
                      <option value="days">Days</option>
              </SelectField>
         </Grid>

         <TextField
            name="numberOfIntervals"
            placeholder="e.g., 6"
            label="Number of Intervals"
            type="number"
            min="1"
            isRequired
            disabled={isLoading}
            descriptiveText="How many times should the analysis run?"
         />
         <TextField
            name="amountPerInterval"
            placeholder="e.g., 50"
            label="Amount of Post to Check"
            type="number"
            min="1"
            max="100"
            isRequired
            disabled={isLoading}
            descriptiveText="How many post should be checked per interval? Max 100"
         />

         {/* Submit Button */}
         <Button
            type="submit"
            variation="primary"
            isLoading={isLoading}
            isDisabled={isLoading}
            marginTop={tokens.space.small}
            isFullWidth
        >
            Add Topic
        </Button>
       </Flex>
    </Card>
  );
}

export default TopicForm;