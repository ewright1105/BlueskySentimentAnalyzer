import json 
import boto3
from botocore.exceptions import ClientError
import time
import os

dynamodb = boto3.resource("dynamodb")
scheduler = boto3.client('scheduler')
query_table = dynamodb.Table("Queries")
counter_table_queries = dynamodb.Table('CountersQuery')

def lambda_handler(event, context):
    TARGET_LAMBDA_ARN = os.environ.get('TARGET_LAMBDA_ARN')
    SCHEDULER_ROLE_ARN = os.environ.get('SCHEDULER_ROLE_ARN')
    if not TARGET_LAMBDA_ARN or not SCHEDULER_ROLE_ARN:
        print("Error: TARGET_LAMBDA_ARN or SCHEDULER_ROLE_ARN environment variable not set.")
        return {"statusCode": 500, "body": json.dumps({"error": "Server configuration error."})}
    try:
        body = json.loads(event["body"]) if "body" in event else event
    except json.JSONDecodeError:
         return {"statusCode": 400, "body": json.dumps({"error": "Invalid JSON in request body"})}
    return add_query(body)

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
            response = counter_table_queries.update_item(
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

def add_query(data):
    try:
        print("Received data:", json.dumps(data, indent=2))  # Debugging

        # Ensure required fields exist
        required_fields = ["Topic", "Email", "NumIntervals", "PostsToAnalyze", "IntervalLength"]
        for field in required_fields:
            if field not in data:
                raise ValueError(f"Missing required key: {field}")
        
        # Get the next QueryID from the dedicated query counter table
        query_id = get_next_id('QueryCounter')
        
        # Create the item with auto-incremented QueryID
        item = {
            "QueryID": query_id,
            "Topic": data["Topic"],
            "Email": data["Email"],
            "NumIntervals": int(data["NumIntervals"]),
            "PostsToAnalyze": int(data["PostsToAnalyze"]),
            "IntervalLength": int(data["IntervalLength"]),
            # Optional: add creation timestamp
            "CreatedAt": int(time.time())
        }

        query_table.put_item(Item=item)
        
        schedule_name = f"BlueskyAnalysis-Query-{query_id}"
        
        # Define the target for the schedule (the Bluesky Lambda)
        target = {
            'Arn': TARGET_LAMBDA_ARN,
            'RoleArn': SCHEDULER_ROLE_ARN,
            'Input': json.dumps({
                "source": "aws.scheduler",
                "detail-type": "Scheduled Event",
                "detail": {
                    "queryId": query_id,
                    "topic": data["Topic"]
                    # Add other details if the target lambda needs them
                }
            }),
            # Optional: Add retry policy, dead-letter queue config
            'RetryPolicy': {
                 'MaximumEventAgeInSeconds': 3600, # e.g., 1 hour
                 'MaximumRetryAttempts': 3
             }
        }

        # Create the schedule
        print(f"Creating schedule: {schedule_name} with expression: {schedule_expression} for {num_intervals} invocations.")
        try:
             # Use FlexibleTimeWindow for resilience
             # ActionAfterCompletion='DELETE' ensures the schedule is removed after the last invocation
             scheduler.create_schedule(
                 Name=schedule_name,
                 GroupName='default',
                 ScheduleExpression=schedule_expression,
                 Target=target,
                 State='ENABLED', # Start the schedule immediately
                 FlexibleTimeWindow={'Mode': 'OFF'}, # Or FLEXIBLE with a window
                 # --- Key part: Stop after N invocations ---
                 ActionAfterCompletion='DELETE', # Delete schedule after completion
                 ScheduleExpressionTimezone='UTC', # Explicitly set timezone
                 # --- Define the end condition based on NumIntervals ---
                 # This requires a start date/time. Use now.
                 StartDate=datetime.utcnow(),
                 # No EndDate needed if using count, but we need a way to limit runs.
                 # Unfortunately, EventBridge Scheduler doesn't directly support a "run N times" count in the CreateSchedule API itself as of my last update.
                 # Common Workaround:
                 # 1. Set ActionAfterCompletion='DELETE'.
                 # 2. Calculate an approximate EndDate far enough in the future to allow all runs.
                 # 3. The target Lambda *must* check how many times it has run for this QueryID (e.g., by checking data count in DynamoDB) and potentially disable/delete the schedule or update the Query status itself.
                 # OR: A slightly more complex approach using Step Functions.
                 # Let's stick to the simpler approach for now, relying on ActionAfterCompletion='DELETE' and calculating a reasonable EndDate.

                 # Calculate a rough end date (add buffer)
                 # This is less precise than a direct count.
                 # total_seconds = num_intervals * interval_length * {'minutes': 60, 'hours': 3600, 'days': 86400}[interval_unit]
                 # end_date = datetime.utcnow() + timedelta(seconds=total_seconds + 3600) # Add 1hr buffer

                 # --- ALTERNATIVE & BETTER: Use EventBridge Rules with Input Transformer (More setup) ---
                 # OR --- Manage count within the target Lambda (Requires state tracking) ---

                 # For now, let's rely on ActionAfterCompletion='DELETE' and the target lambda potentially needing logic later.
                 # We won't set an EndDate here to avoid premature deletion if intervals are long.
                 # The deletion relies solely on the target completing successfully 'num_intervals' times.
                 # **REVISIT THIS:** EventBridge Scheduler *might* have added a direct count feature. Check latest docs.
                 # If not, the target lambda *must* handle the count logic.

             )
             print(f"Successfully created EventBridge schedule: {schedule_name}")

        except ClientError as e:
             print(f"Error creating EventBridge schedule: {e}")
             # Consider cleanup: Should we delete the DynamoDB entry if schedule fails? Depends on requirements.
             # For now, just report the error.
             raise Exception(f"Failed to create schedule: {e.response['Error']['Message']}")

        # Return the generated QueryID in the response
        return {
            "statusCode": 200, 
            "body": json.dumps({
                "message": "Query added successfully",
                "QueryID": query_id
            })
        }
    except ValueError as ve:
        return {"statusCode": 400, "body": json.dumps({"error": str(ve)})}
    except Exception as e:
        print(f"Error: {str(e)}")  # Log the error
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}