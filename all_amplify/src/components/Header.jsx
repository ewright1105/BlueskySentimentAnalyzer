import React from 'react';
import { Heading, Text, Button, Flex, useTheme, Divider } from "@aws-amplify/ui-react";

function Header({ userEmail, onSignOut, isActionDisabled }) {
  const { tokens } = useTheme();

  return (
    <Flex
      direction="column"
      width="100%"
      paddingBottom={tokens.space.small}
      marginBottom={tokens.space.medium}
      borderBottom={`1px solid ${tokens.colors.border.secondary}`}
    >
      <Flex
        justifyContent="space-between"
        alignItems="center"
        width="100%"
        padding={`${tokens.space.small} 0`}
      >
        {/* Left side: Title and Welcome */}
        <Flex direction="column" alignItems="flex-start">
             <Heading level={3} margin="0">Blue Sky Opinion Tracker</Heading>
             <Text fontSize="small" color="font.secondary">Welcome, { userEmail || 'User'}!</Text>
        </Flex>

        {/* Right side: Sign Out Button */}
        <Button
            onClick={onSignOut}
            variation="link"
            size="medium"
            isDisabled={isActionDisabled}
        >
            Sign Out
        </Button>
      </Flex>
    </Flex>
  );
}

export default Header;