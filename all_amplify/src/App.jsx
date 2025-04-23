// src/App.jsx
import React from "react"; // Ensure React is imported
import { Authenticator } from "@aws-amplify/ui-react";
import { Amplify } from "aws-amplify";
import "@aws-amplify/ui-react/styles.css"; // Keep global styles
import '@aws-amplify/ui-react/styles.css';
import TopicManager from './components/TopicManager';

console.log('Amplify Auth Configuration:', {
  region: import.meta.env.VITE_REGION,
  userPoolId: import.meta.env.VITE_USER_POOL_ID,
  userPoolClientId: import.meta.env.VITE_USER_POOL_CLIENT_ID,
  identityPoolId: import.meta.env.VITE_IDENTITY_POOL_ID,
  api: import.meta.env.VITE_API_ENDPOINT,
});
// Correct Amplify configuration
Amplify.configure({
  Auth: {
    Cognito: {
      region: import.meta.env.VITE_REGION,
      userPoolId: import.meta.env.VITE_USER_POOL_ID,
      userPoolClientId: import.meta.env.VITE_USER_POOL_CLIENT_ID,
      identityPoolId: import.meta.env.VITE_IDENTITY_POOL_ID,
    }

  },
  Storage: {
    region: import.meta.env.VITE_REGION,
    bucket: import.meta.env.VITE_BUCKET_NAME,
    identityPoolId: import.meta.env.VITE_IDENTITY_POOL_ID,
  },
});

export default function App() {
  return (
    <Authenticator>
          <TopicManager />
    </Authenticator>

  );
}
