import json
import boto3
import os
import logging
import re # For basic phone number format check

logger = logging.getLogger()
logger.setLevel(logging.INFO)
sns = boto3.client('sns')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

# Basic E.164 format check (starts with +, followed by digits)
E164_PATTERN = re.compile(r"^\+[1-9]\d{1,14}$")

def lambda_handler(event, context):
    if not SNS_TOPIC_ARN:
        logger.error("SNS_TOPIC_ARN environment variable is not set.")
        return {'statusCode': 500, 'body': json.dumps({'error': 'Config error: SNS Topic ARN missing.'})}

    logger.info(f"Received event: {json.dumps(event)}")

    phone_number = None
    payload = event
    if 'body' in event and isinstance(event['body'], str):
         try: payload = json.loads(event['body'])
         except json.JSONDecodeError: pass # Continue to check top level

    if isinstance(payload, dict) and 'phone_number' in payload:
         phone_number = payload['phone_number']

    if not phone_number or not isinstance(phone_number, str):
         logger.error("Phone number not found or invalid in payload.")
         return {'statusCode': 400, 'body': json.dumps({'error': 'phone_number is missing or invalid.'})}

    # Validate E.164 format
    if not E164_PATTERN.match(phone_number):
        logger.error(f"Invalid phone number format: {phone_number}. Must be E.164 (e.g., +14155552671).")
        return {'statusCode': 400, 'body': json.dumps({'error': 'Invalid phone number format. Use E.164 (e.g., +14155552671).'})}

    logger.info(f"Attempting to subscribe phone number: {phone_number} to topic: {SNS_TOPIC_ARN}")

    try:
        response = sns.subscribe(
            TopicArn=SNS_TOPIC_ARN,
            Protocol='sms',
            Endpoint=phone_number, # Use phone number as the endpoint
            ReturnSubscriptionArn=True
        )
        subscription_arn = response.get('SubscriptionArn')
        logger.info(f"Successfully initiated SMS subscription for {phone_number}. Sub ARN: {subscription_arn}")

        # NOTE: AWS SNS handles SMS opt-in confirmation mechanisms.
        # The user might receive an initial message asking for confirmation depending on region/settings.
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'SMS subscription request successful for {phone_number}. Check phone for any confirmation messages.',
                'subscriptionArn': subscription_arn # Might be PendingConfirmation initially
            })
        }
    except sns.exceptions.InvalidParameterException as e:
         logger.error(f"Invalid parameter during SMS subscription: {e}")
         return {'statusCode': 400, 'body': json.dumps({'error': f'Invalid parameter: {e}'})}
    except sns.exceptions.AuthorizationErrorException as e:
         logger.error(f"Authorization error: Check Lambda role permissions for sns:Subscribe on {SNS_TOPIC_ARN}. Error: {e}")
         return {'statusCode': 500, 'body': json.dumps({'error': f'Authorization error: {e}'})}
    except Exception as e:
        logger.error(f"An unexpected error occurred during SMS subscription: {e}")
        return {'statusCode': 500, 'body': json.dumps({'error': f'An unexpected error occurred: {e}'})}