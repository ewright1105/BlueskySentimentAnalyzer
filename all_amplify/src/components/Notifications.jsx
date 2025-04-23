import React from 'react';
import { Alert } from "@aws-amplify/ui-react";

function Notifications({ error, successMessage, onErrorDismiss, onSuccessDismiss }) {
  return (
    <>
      {error && (
        <Alert
          key="error-alert"
          variation="error"
          isDismissible={true}
          onDismiss={onErrorDismiss}
          heading="Error"
          width="100%"
        >
          {error}
        </Alert>
      )}
      {successMessage && (
        <Alert
          key="success-alert"
          variation="success"
          isDismissible={true}
          onDismiss={onSuccessDismiss}
          heading="Success"
          width="100%"
        >
          {successMessage}
        </Alert>
      )}
    </>
  );
}

export default Notifications;