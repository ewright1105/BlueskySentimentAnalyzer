import json
import boto3
import decimal
from boto3.dynamodb.conditions import Key # Import Key for query

# Helper class to convert Decimal to float/int for JSON serialization
class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, decimal.Decimal):
            if o % 1 == 0:
                return int(o)
            return float(o)
        return super(DecimalEncoder, self).default(o)

dynamodb = boto3.resource("dynamodb")
query_table = dynamodb.Table("Queries")
# *** VERIFY GSI NAME AND PARTITION KEY CASE ('Email') IN DYNAMODB CONSOLE ***
EMAIL_GSI_NAME = "EmailIndex" 

# --- Define CORS Headers centrally for consistency ---
CORS_HEADERS = {
    # Using '*' for testing, replace with 'http://localhost:5173' or production URL later
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Accept',
    'Access-Control-Allow-Methods': 'OPTIONS,GET,POST', # Adjust if other methods are needed
    'Content-Type': 'application/json'
}

def lambda_handler(event, context):
    # Try getting Email from query string parameters first (for GET requests)
    # Ensure frontend is sending 'Email' (capital E) if using this
    Email = event.get("queryStringParameters", {}).get("Email")

    # If not in query string, try getting from the body (for POST requests)
    if not Email and event.get("body"):
        try:
            body = json.loads(event["body"])
            Email = body.get("Email") # Ensure body contains 'Email' (capital E)
        except json.JSONDecodeError:
             # Add CORS headers to error response
             return {
                 "statusCode": 400,
                 "headers": CORS_HEADERS,
                 "body": json.dumps({"error": "Invalid JSON body"})
             }

    if not Email:
        # Add CORS headers to error response
        return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "Missing required parameter: Email"})
        }

    return get_queries_by_Email(Email)

def get_queries_by_Email(Email):
    """
    Retrieves all query items associated with a specific Email using a GSI query.
    """
    print(f"Querying GSI '{EMAIL_GSI_NAME}' for Email: {Email}") # Log GSI name too
    items = []
    try:
        # Use the query operation on the GSI
        # *** VERIFY 'Email' (capital E) MATCHES GSI PARTITION KEY ***
        query_params = {
            "IndexName": EMAIL_GSI_NAME,
            "KeyConditionExpression": Key("Email").eq(Email)
        }

        # Handle pagination if many items match the Email
        while True:
            response = query_table.query(**query_params)
            items.extend(response.get("Items", []))

            last_evaluated_key = response.get("LastEvaluatedKey")
            if not last_evaluated_key:
                break
            query_params["ExclusiveStartKey"] = last_evaluated_key

        # No need for specific 'not items' check here, returning empty list is fine

        print(f"Found {len(items)} queries for Email: {Email}")
        return {
            "statusCode": 200,
            "headers": CORS_HEADERS, # Use defined headers
            "body": json.dumps(items, cls=DecimalEncoder) # Return array even if empty
        }

    except dynamodb.meta.client.exceptions.ResourceNotFoundException:
         error_msg = f"Error: Table 'Queries' or Index '{EMAIL_GSI_NAME}' not found. Verify names and case."
         print(error_msg)
         # Add CORS headers to error response
         return {
             "statusCode": 500,
             "headers": CORS_HEADERS,
             "body": json.dumps({"error": error_msg })
         }
    # Catch potential ValidationException for wrong key schema etc.
    except dynamodb.meta.client.exceptions.ClientError as e:
        error_code = e.response.get('Error', {}).get('Code')
        error_msg = f"DynamoDB Client Error ({error_code}): {str(e)}"
        print(error_msg)
        # Add CORS headers to error response
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": error_msg})
        }
    except Exception as e:
        error_msg = f"An unexpected error occurred: {str(e)}"
        print(error_msg)
        # import traceback # Uncomment for detailed logs in CloudWatch
        # print(traceback.format_exc())
        # Add CORS headers to error response
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "An internal server error occurred."}) # More generic message to client
        }