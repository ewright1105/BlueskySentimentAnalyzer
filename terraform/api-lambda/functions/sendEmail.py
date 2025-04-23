import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)
ses = boto3.client('ses')

# Get the verified sender email from environment variables
SENDER_EMAIL = os.environ.get('SENDER_EMAIL')
# Optional: Specify AWS Region for SES if different from Lambda's region
# SES_REGION = os.environ.get('SES_REGION', 'us-east-1')
# ses = boto3.client('ses', region_name=SES_REGION)


def lambda_handler(event, context):
    if not SENDER_EMAIL:
        logger.error("SENDER_EMAIL environment variable is not set.")
        return {'statusCode': 500, 'body': json.dumps({'error': 'Config error: Sender email missing.'})}

    logger.info(f"Received event: {json.dumps(event)}")

    # Extract parameters (handle direct invoke or API Gateway)
    to_email = None
    subject = "It's Done!" # Default subject
    body_text = None
    body_html = None # Optional HTML body

    payload = event
    if 'body' in event and isinstance(event['body'], str):
        try:
            payload = json.loads(event['body'])
        except json.JSONDecodeError:
            logger.warning("Could not decode event body as JSON, treating event directly as payload.")

    if isinstance(payload, dict):
        to_email = payload.get('to_email')
        subject = payload.get('subject', subject)
        body_text = payload.get('body_text')
        body_html = payload.get('body_html') # Optional

    # --- Validation ---
    if not to_email or '@' not in str(to_email):
        logger.error("Recipient email ('to_email') missing or invalid.")
        return {'statusCode': 400, 'body': json.dumps({'error': "Valid 'to_email' is required."})}
    if not body_text and not body_html:
         logger.error("Email body ('body_text' or 'body_html') missing.")
         return {'statusCode': 400, 'body': json.dumps({'error': "Email body ('body_text' or 'body_html') is required."})}
    # --- End Validation ---


    message_dict = {
        'Subject': {'Data': subject, 'Charset': 'UTF-8'}
    }
    body_dict = {}
    if body_text:
        body_dict['Text'] = {'Data': body_text, 'Charset': 'UTF-8'}
    if body_html:
        body_dict['Html'] = {'Data': body_html, 'Charset': 'UTF-8'}
    message_dict['Body'] = body_dict


    logger.info(f"Attempting to send email via SES from {SENDER_EMAIL} to {to_email}")

    try:
        response = ses.send_email(
            Source=SENDER_EMAIL,
            Destination={'ToAddresses': [to_email]},
            Message=message_dict
            # ReplyToAddresses=[SENDER_EMAIL], # Optional
            # ConfigurationSetName='YourConfigSetName' # Optional: For tracking opens/clicks
        )
        message_id = response.get('MessageId')
        logger.info(f"SES SendEmail successful to {to_email}. Message ID: {message_id}")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Email successfully sent to {to_email}.',
                'messageId': message_id
            })
        }
    except ses.exceptions.MessageRejected as e:
         logger.error(f"SES Message Rejected: {e}. Is recipient email verified (if in sandbox)?", exc_info=True)
         # This often happens in sandbox mode if the recipient isn't verified.
         return {'statusCode': 400, 'body': json.dumps({'error': f'SES Message Rejected: {e}. Ensure recipient is verified if in sandbox.'})}
    except ses.exceptions.MailFromDomainNotVerifiedException as e:
        logger.error(f"SES Mail From Domain Not Verified: {e}. Ensure sender email '{SENDER_EMAIL}' is verified.", exc_info=True)
        return {'statusCode': 500, 'body': json.dumps({'error': f'SES Sender Identity Not Verified: {e}'})}
    except Exception as e:
        logger.error(f"SES SendEmail failed for {to_email}: {e}", exc_info=True)
        return {'statusCode': 500, 'body': json.dumps({'error': f'Could not send email: {e}'})}