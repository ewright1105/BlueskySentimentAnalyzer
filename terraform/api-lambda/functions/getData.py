import json
import boto3
import decimal
import os
from boto3.dynamodb.conditions import Key, Attr # Import Attr for FilterExpression

# Helper class to convert Decimal to float/int for JSON serialization
class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, decimal.Decimal):
            if o % 1 == 0:
                return int(o)
            return float(o)
        return super(DecimalEncoder, self).default(o)

# --- Configuration ---
TABLE_NAME = "Data"
# Key we are filtering on (Range Key in the base table, Type: N)
QUERY_FILTER_KEY_NAME = "QueryID"

# --- Define CORS Headers centrally ---
CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Accept',
    'Access-Control-Allow-Methods': 'OPTIONS,GET', # Adjust methods if needed
    'Content-Type': 'application/json'
}

# --- Initialize DynamoDB Resource ---
dynamodb = None
data_table = None
try:
    dynamodb = boto3.resource("dynamodb")
    data_table = dynamodb.Table(TABLE_NAME)
    data_table.load() # Check table existence
    print(f"Successfully connected to DynamoDB table: {TABLE_NAME}")
except dynamodb.meta.client.exceptions.ResourceNotFoundException:
    print(f"FATAL ERROR: DynamoDB Table '{TABLE_NAME}' not found. Please verify the table name and region.")
except Exception as e:
    print(f"FATAL ERROR: Could not initialize DynamoDB client or table '{TABLE_NAME}': {e}")

# --- Lambda Handler ---
def lambda_handler(event, context):
    """
    Handles incoming requests to fetch all data entries for a specific QueryID
    (expected as a NUMBER) using a Scan operation.
    Expects 'QueryID' in query string parameters (GET) or request body (POST/PUT).

    WARNING: Uses DynamoDB Scan, which can be inefficient for large tables.
             Consider adding a GSI on QueryID for better performance if needed.
    """
    if data_table is None: # Check if table initialization failed
         return {
             "statusCode": 500,
             "headers": CORS_HEADERS,
             "body": json.dumps({"error": f"DynamoDB table '{TABLE_NAME}' could not be accessed. Check logs."})
         }

    query_id_str = None

    # 1. Try getting QueryID from query string parameters
    query_params = event.get("queryStringParameters")
    if query_params:
        query_id_str = query_params.get(QUERY_FILTER_KEY_NAME, "").strip()
        print(f"Found in query params: {QUERY_FILTER_KEY_NAME}='{query_id_str}'")

    # 2. If missing from query params, try getting from the body
    if not query_id_str:
        print(f"{QUERY_FILTER_KEY_NAME} missing from query params, checking body...")
        body_content = event.get("body")
        if body_content:
            try:
                body = json.loads(body_content)
                # Get value, convert to string first for consistent handling before int conversion
                query_id_from_body = body.get(QUERY_FILTER_KEY_NAME)

                if query_id_from_body is not None:
                    query_id_str = str(query_id_from_body).strip()

                print(f"Found in body: {QUERY_FILTER_KEY_NAME}='{query_id_str}'")

            except json.JSONDecodeError:
                 return {
                     "statusCode": 400,
                     "headers": CORS_HEADERS,
                     "body": json.dumps({"error": "Invalid JSON body"})
                 }
            except Exception as e: # Catch potential errors during string conversion or access
                 print(f"Error processing body for key: {e}")
                 return {
                     "statusCode": 400,
                     "headers": CORS_HEADERS,
                     "body": json.dumps({"error": f"Error processing body for {QUERY_FILTER_KEY_NAME}"})
                 }

    # 3. Validate that QueryID was found (as non-empty string)
    if not query_id_str:
        return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": f"Missing required parameter: {QUERY_FILTER_KEY_NAME}"})
        }

    # 4. Convert QueryID to Number (Integer)
    try:
        # Schema defines QueryID as N, convert to int
        query_id_num = int(query_id_str)
        print(f"Converted to numeric type: {QUERY_FILTER_KEY_NAME}={query_id_num}")
    except ValueError:
         return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": f"Invalid number format for {QUERY_FILTER_KEY_NAME} ('{query_id_str}')"})
         }

    # 5. Call the function to get the items using Scan
    return get_data_by_query_id(query_id_num)


# --- Data Retrieval Function ---
def get_data_by_query_id(query_id_num):
    """
    Retrieves all data items from the 'Data' table matching the given QueryID
    using a Scan operation with a FilterExpression.

    Args:
        query_id_num (int): The QueryID to filter by.

    Returns:
        dict: Lambda proxy response object.

    WARNING: Uses DynamoDB Scan, potentially inefficient. Consider a GSI.
    """
    print(f"Attempting to Scan table '{data_table.name}' for items with {QUERY_FILTER_KEY_NAME}={query_id_num} (Number)")

    items = []
    scan_kwargs = {
        # Use FilterExpression to match QueryID
        # Using Attr object for condition building
        'FilterExpression': Attr(QUERY_FILTER_KEY_NAME).eq(query_id_num)
        # Alternatively using expression strings:
        # 'FilterExpression': '#qid = :qidval',
        # 'ExpressionAttributeNames': {'#qid': QUERY_FILTER_KEY_NAME},
        # 'ExpressionAttributeValues': {':qidval': query_id_num}
    }

    try:
        # Loop to handle potential pagination automatically managed by boto3 resource scan
        done = False
        start_key = None
        while not done:
            if start_key:
                scan_kwargs['ExclusiveStartKey'] = start_key

            response = data_table.scan(**scan_kwargs)
            items.extend(response.get('Items', []))
            start_key = response.get('LastEvaluatedKey', None)
            done = start_key is None

        print(f"Scan completed. Found {len(items)} items for {QUERY_FILTER_KEY_NAME}={query_id_num}")

        # Return 200 OK with the list of items (potentially empty)
        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            # Use DecimalEncoder to handle DynamoDB numbers (Decimals) in the response
            "body": json.dumps(items, cls=DecimalEncoder)
        }

    # Keep robust error handling
    except dynamodb.meta.client.exceptions.ResourceNotFoundException:
         error_msg = f"Error: Table '{data_table.name}' not found during scan. Verify table exists."
         print(error_msg)
         return {
             "statusCode": 500,
             "headers": CORS_HEADERS,
             "body": json.dumps({"error": error_msg })
         }
    except dynamodb.meta.client.exceptions.ClientError as e:
        error_code = e.response.get('Error', {}).get('Code')
        error_msg = f"DynamoDB Client Error ({error_code}) scanning table '{data_table.name}': {str(e)}"
        print(error_msg)
        # Specific errors like ProvisionedThroughputExceededException might occur during scans
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": error_msg})
        }
    except Exception as e:
        error_msg = f"An unexpected error occurred during data retrieval scan: {str(e)}"
        print(error_msg)
        # import traceback # Uncomment for detailed debugging
        # print(traceback.format_exc())
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "An internal server error occurred."})
        }
