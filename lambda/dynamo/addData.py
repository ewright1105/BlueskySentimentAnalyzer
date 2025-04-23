import json 
import boto3
from botocore.exceptions import ClientError
import time

dynamodb = boto3.resource("dynamodb")
data_table = dynamodb.Table("Data")
counter_table_data = dynamodb.Table('CountersData')  # Using the dedicated counter table for data

def lambda_handler(event, context):
    body = json.loads(event["body"]) if "body" in event else event
    return add_data(body)

def get_next_id(counter_name):
    """
    Atomically increments and returns the next ID for a given counter.
    Includes retry logic for handling potential conflicts.
    """
    max_retries = 3
    retry_count = 0
    
    while retry_count < max_retries:
        try:
            # Atomically increment the counter
            response = counter_table_data.update_item(
                Key={'CounterName': counter_name},
                UpdateExpression='SET CurrentValue = if_not_exists(CurrentValue, :start) + :inc',
                ExpressionAttributeValues={':inc': 1, ':start': 0},
                ReturnValues='UPDATED_NEW'
            )
            
            # Return the new ID value
            return int(response['Attributes']['CurrentValue'])
            
        except ClientError as e:
            if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
                # If there's a conflict, wait briefly and retry
                retry_count += 1
                time.sleep(0.1)
            else:
                # For other errors, raise the exception
                raise
    
    # If we exceed retries, raise an exception
    raise Exception(f"Failed to obtain next ID for {counter_name} after {max_retries} attempts")

def add_data(data):
    try:
        print("Received data:", json.dumps(data, indent=2))  # Debugging

        # Ensure required fields exist
        required_fields = ["QueryID", "Topic", "PostsAnalyzed", "PositivePosts", 
                          "NeutralPosts", "NegativePosts", "MixedPosts"]
        for field in required_fields:
            if field not in data:
                raise ValueError(f"Missing required key: {field}")
        
        # Get the next DataID from the dedicated data counter table
        data_id = get_next_id('DataCounter')
        
        # Create the item with auto-incremented DataID
        item = {
            "DataID": data_id,
            "QueryID": int(data["QueryID"]),
            "Topic": data["Topic"],
            "PostsAnalyzed": int(data["PostsAnalyzed"]),
            "PositivePosts": int(data["PositivePosts"]),
            "NeutralPosts": int(data["NeutralPosts"]),
            "NegativePosts": int(data["NegativePosts"]),
            "MixedPosts": int(data["MixedPosts"]),
            # Optional: add creation timestamp
            "CreatedAt": int(time.time())
        }

        data_table.put_item(Item=item)
        
        # Return the generated DataID in the response
        return {
            "statusCode": 200, 
            "body": json.dumps({
                "message": "Data entry added successfully",
                "DataID": data_id
            })
        }
    except ValueError as ve:
        return {"statusCode": 400, "body": json.dumps({"error": str(ve)})}
    except Exception as e:
        print(f"Error: {str(e)}")  # Log the error
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}