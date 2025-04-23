import json
import os
import boto3
import logging
from decimal import Decimal # Use Decimal for numbers if precision is critical

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Get table name from environment variable; provide a default for local testing
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'Subtopics')

# Initialize DynamoDB client/resource
# Using Resource API for higher-level abstraction
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)


def lambda_handler(event, context):
    """
    Lambda function handler to add an item to the Subtopics DynamoDB table.
    Expects event payload with at least 'QueryID' (Number) and 'Subtopic' (String).
    """
    logger.info(f"Received event: {json.dumps(event)}")

    try:
        # Check if the payload is in event['body'] (API Gateway proxy integration)
        if 'body' in event and isinstance(event['body'], str):
            try:
                payload = json.loads(event['body'])
                logger.info("Parsed payload from event['body']")
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse JSON from event body: {e}")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Invalid JSON format in request body'})
                }
        else:
            # Assume the event itself is the payload
            payload = event
            logger.info("Using event directly as payload")

        # --- Validate required fields ---
        query_id = payload.get('QueryID')
        subtopic_name = payload.get('Subtopic')

        if query_id is None or subtopic_name is None:
            logger.error("Missing required fields: QueryID or Subtopic")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing required fields: QueryID (Number) or Subtopic (String)'})
            }

        # --- Prepare item for DynamoDB ---
        # Copy the payload to avoid modifying the original event
        item_to_add = payload.copy()

        # Ensure QueryID is treated as a number (boto3 resource handles int/float)
        # Add explicit conversion/validation if necessary
        try:
            # If QueryID might come as a string, try converting
            if isinstance(query_id, str):
                 item_to_add['QueryID'] = int(query_id) # Or float() if decimals needed
            elif not isinstance(query_id, (int, float)):
                 raise ValueError("QueryID must be a number")
        except ValueError:
             logger.error(f"Invalid format for QueryID: {query_id}. Must be a number.")
             return {
                 'statusCode': 400,
                 'body': json.dumps({'error': f'Invalid format for QueryID: {query_id}. Must be a number.'})
             }

        # Ensure Subtopic is a string
        if not isinstance(subtopic_name, str):
            logger.error(f"Invalid format for Subtopic: {subtopic_name}. Must be a string.")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Invalid format for Subtopic: {subtopic_name}. Must be a string.'})
            }

        # Optional: Use Decimal for numbers if high precision is needed, especially for floats
        # item_to_add = replace_floats_with_decimal(item_to_add)

        logger.info(f"Attempting to add item to table {TABLE_NAME}: {json.dumps(item_to_add, default=str)}") # Use default=str for logging Decimals

        # --- Add item to DynamoDB ---
        response = table.put_item(Item=item_to_add)

        logger.info(f"Successfully added item. Response: {response}")

        # --- Return Success Response ---
        return {
            'statusCode': 201, # 201 Created is appropriate for successful PUT/POST
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'message': 'Subtopic added successfully',
                'item': item_to_add # Return the added item (optional)
            })
        }

    except dynamodb.meta.client.exceptions.ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', 'DynamoDB client error')
        logger.exception(f"DynamoDB Error ({error_code}): {error_message}") # Log the full exception
        return {
            'statusCode': 500, # Or potentially 4xx depending on the error (e.g., validation)
            'body': json.dumps({'error': f'Failed to add subtopic: {error_message}', 'errorCode': error_code})
        }
    except Exception as e:
        logger.exception("An unexpected error occurred") # Log the full exception
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'An internal server error occurred: {str(e)}'})
        }