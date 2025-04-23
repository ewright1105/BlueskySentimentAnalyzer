import json
import boto3
import os
import logging
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError
from decimal import Decimal # Needed to handle DynamoDB numbers for JSON serialization

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize Boto3 DynamoDB client/resource outside the handler for reuse
# Use environment variable for table name - BEST PRACTICE
TABLE_NAME = os.environ.get('SUBTOPICS_TABLE_NAME', 'Subtopics') # Default if not set
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

# Helper function to convert DynamoDB Decimal types to Python floats/ints
# This is necessary because json.dumps() cannot serialize Decimal objects by default.
def replace_decimals(obj):
    if isinstance(obj, list):
        return [replace_decimals(i) for i in obj]
    elif isinstance(obj, dict):
        return {k: replace_decimals(v) for k, v in obj.items()}
    elif isinstance(obj, Decimal):
        # Convert Decimal to int if it's a whole number, else float
        if obj % 1 == 0:
            return int(obj)
        else:
            return float(obj)
    else:
        return obj

def lambda_handler(event, context):
    """
    Retrieves all subtopic items from the DynamoDB table for a given QueryID.

    Args:
        event (dict): Lambda event object. Expected to contain 'QueryID'
                      either directly or in 'queryStringParameters'/'pathParameters'.
        context (object): Lambda context object (unused here).

    Returns:
        dict: An API Gateway proxy compatible response object.
              Contains a list of subtopic items in the body on success,
              or an error message on failure.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # --- 1. Extract QueryID from the event ---
    # Standardize on using 'QueryID' as the key
    query_id_input = None # Use a temporary variable to hold the raw value

    # Check API Gateway standard locations using 'QueryID'
    if 'queryStringParameters' in event and event['queryStringParameters'] and 'QueryID' in event['queryStringParameters']:
         query_id_input = event['queryStringParameters']['QueryID'] # <-- Changed key
         logger.info("Extracted QueryID from queryStringParameters")
    elif 'pathParameters' in event and event['pathParameters'] and 'QueryID' in event['pathParameters']:
         query_id_input = event['pathParameters']['QueryID'] # <-- Changed key
         logger.info("Extracted QueryID from pathParameters")

    # Check direct event payload using 'QueryID'
    elif 'QueryID' in event: # <-- Changed key
         query_id_input = event['QueryID'] # <-- Changed key
         logger.info("Extracted QueryID directly from event body/payload")

    # Add more checks if needed (e.g., for POST body: json.loads(event['body'])['QueryID'])

    if query_id_input is None: # Check if we found *any* value
        logger.error("Missing 'QueryID' in request.")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            # Update error message to be consistent
            'body': json.dumps({'error': "Missing 'QueryID' parameter."})
        }

    # Convert the extracted value to string before attempting int conversion
    # This handles cases where the input is already a number or a string.
    query_id_str = str(query_id_input)

    # --- 2. Validate and Convert QueryID ---
    try:
        # DynamoDB 'N' type requires a number. Convert the input string/number.
        query_id = int(query_id_str)
    except ValueError:
        # Update error message to reflect the actual input tried
        logger.error(f"Invalid 'QueryID' value: '{query_id_str}'. Must be an integer or numeric string.")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': f"Invalid 'QueryID' value: '{query_id_str}'. Must be an integer or numeric string."})
        }

    logger.info(f"Querying table '{TABLE_NAME}' for QueryID: {query_id}")

    # --- 3. Perform DynamoDB Query ---
    try:
        # Use the query operation, which is efficient for partition key lookups
        # The DynamoDB attribute name is 'QueryID' as defined in your Terraform
        response = table.query(
            KeyConditionExpression=Key('QueryID').eq(query_id)
        )
        logger.info(f"DynamoDB query successful. Items found: {len(response.get('Items', []))}")

    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'UnknownError')
        error_message = e.response.get('Error', {}).get('Message', 'An unknown error occurred')
        logger.error(f"DynamoDB ClientError accessing table '{TABLE_NAME}' ({error_code}): {error_message}")
        # Distinguish between client-side (like missing table) and server-side errors if needed
        if error_code == 'ResourceNotFoundException':
             status_code = 404
        else:
             status_code = 500 # Internal Server Error for other DB issues
        return {
            'statusCode': status_code,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': f"Could not retrieve subtopics: {error_code}"})
        }
    except Exception as e:
        # Catch any other unexpected errors
        logger.error(f"An unexpected error occurred: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'An internal server error occurred.'})
        }

    # --- 4. Process and Format the Response ---
    items = response.get('Items', [])

    # Convert DynamoDB Decimal types to standard Python numbers for JSON output
    cleaned_items = replace_decimals(items)

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            # Optional: Add CORS headers if this Lambda is triggered by API Gateway
            #           and called from a web browser on a different domain.
            # 'Access-Control-Allow-Origin': '*',
            # 'Access-Control-Allow-Credentials': True,
        },
        'body': json.dumps(cleaned_items)
    }