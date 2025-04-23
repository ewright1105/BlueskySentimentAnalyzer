#----------------------------------------------------------
# Terraform Configuration & Providers
#----------------------------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

#----------------------------------------------------------
# Helper Data Sources
#----------------------------------------------------------
data "aws_caller_identity" "current" {}

#----------------------------------------------------------
# Variables
#----------------------------------------------------------

variable "aws_region" {
  description = "AWS region where resources are deployed"
  type        = string
  default     = "us-east-2" # <-- CHANGE AS NEEDED
}

variable "lambda_src_path" {
  description = "Path to the directory containing the Node.js Lambda source code files (blueskyLambda.js, node_modules, etc.)"
  type        = string
  default     = "./blueskyAnalyze" # <-- CHANGE THIS
}

variable "python_runtime" {
  description = "Python runtime for the Lambda functions"
  type        = string
  default     = "python3.10"
}

variable "nodejs_runtime" {
  description = "Node.js runtime for the Lambda functions"
  type        = string
  default     = "nodejs18.x"
}

# --- Names of EXISTING DynamoDB Tables ---
variable "queries_table_name" {
  description = "Name of the existing DynamoDB table for queries"
  type        = string
  default     = "Queries"
}

variable "query_counters_table_name" {
  description = "Name of the existing DynamoDB table for query counters"
  type        = string
  default     = "CountersQuery"
}

variable "data_table_name" {
  description = "Name of the existing DynamoDB table for data"
  type        = string
  default     = "Data"
}

variable "data_counters_table_name" {
  description = "Name of the existing DynamoDB table for data counters"
  type        = string
  default     = "CountersData"
}

variable "subtopics_table_name" {
  description = "Name of the existing DynamoDB table for subtopics"
  type        = string
  default     = "Subtopics"
}

# --- SES Configuration ---
# Removed variable "ses_sender_email"
# Note: The send_email Lambda code MUST be updated to retrieve the sender email
# from a secure source like Secrets Manager or Parameter Store, or be hardcoded (not recommended).

# --- EventBridge Scheduler Variables ---
variable "scheduler_group_name" {
  description = "Name of the EventBridge Scheduler group used for schedules"
  type        = string
  default     = "default" # Match the group name used/expected in the Node.js code
}

# --- Bluesky Credentials ---
# Removed variable "bluesky_handle"
# Removed variable "bluesky_app_password"
# Note: The AnalyzeBlueskySentiment Lambda code MUST be updated to retrieve credentials
# securely from Secrets Manager or Parameter Store.

# --- Circular Dependency Workaround Removed ---
# Removed variable "target_lambda_arn_for_scheduler"
# Terraform will now automatically determine the ARN for the AnalyzeBlueskySentiment Lambda.

#----------------------------------------------------------
# SNS Topic Resource
#----------------------------------------------------------
resource "aws_sns_topic" "notifications" {
  # Choose a suitable name for the SNS topic that this config creates
  name = "bluesky-notifications-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name        = "Bluesky Notifications Topic"
    ManagedBy   = "Terraform"
    Environment = "Production" # Or appropriate environment tag
  }
}

#----------------------------------------------------------
# IAM Assume Role Policies
#----------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scheduler_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

#----------------------------------------------------------
# IAM Role for EventBridge Scheduler to Invoke Target Lambda
# Required by the add_query Lambda
#----------------------------------------------------------
resource "aws_iam_role" "scheduler_invocation_role" {
  name               = "EventBridgeSchedulerInvokeLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role_policy.json
  description        = "Role assumed by EventBridge Scheduler to invoke the target Lambda"
}

data "aws_iam_policy_document" "scheduler_invocation_policy_doc" {
  statement {
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      # Reference the ARN directly - Terraform handles the dependency
      aws_lambda_function.analyze_bluesky_sentiment.arn
    ]
  }
}

resource "aws_iam_policy" "scheduler_invocation_policy" {
  name        = "EventBridgeSchedulerInvokeLambdaPolicy"
  description = "Policy allowing EventBridge Scheduler to invoke the target Lambda"
  policy      = data.aws_iam_policy_document.scheduler_invocation_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "scheduler_invocation_attach" {
  role       = aws_iam_role.scheduler_invocation_role.name
  policy_arn = aws_iam_policy.scheduler_invocation_policy.arn
}


#----------------------------------------------------------
# Lambda Function: get_queries_by_email
# (No changes needed here based on removed variables)
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "get_queries_by_email_lambda_role" {
  name               = "GetQueriesByEmailLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "get_queries_by_email_lambda_policy_doc" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "dynamodb:Query"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.queries_table_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.queries_table_name}/index/EmailIndex"
    ]
  }
}

resource "aws_iam_policy" "get_queries_by_email_lambda_policy" {
  name   = "GetQueriesByEmailLambdaPolicy"
  policy = data.aws_iam_policy_document.get_queries_by_email_lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "get_queries_by_email_lambda_attach" {
  role       = aws_iam_role.get_queries_by_email_lambda_role.name
  policy_arn = aws_iam_policy.get_queries_by_email_lambda_policy.arn
}

# --- Code Packaging ---
data "archive_file" "get_queries_by_email_zip" {
  type        = "zip"
  source_file = "${path.module}/getQuery.py"
  output_path = "${path.module}/get_queries_by_email.zip"
}

# --- Lambda Definition ---
resource "aws_lambda_function" "get_queries_by_email" {
  function_name    = "getQueries"
  filename         = data.archive_file.get_queries_by_email_zip.output_path
  source_code_hash = data.archive_file.get_queries_by_email_zip.output_base64sha256
  handler          = "getQuery.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.get_queries_by_email_lambda_role.arn

  environment {
    variables = {
      QUERIES_TABLE_NAME = var.queries_table_name
    }
  }

  tags = {
    Name = "GetQueriesByEmailLambda"
  }

  depends_on = [aws_iam_role_policy_attachment.get_queries_by_email_lambda_attach]
}

#----------------------------------------------------------
# Lambda Function: add_query
# Updated environment variables to reference target lambda ARN directly
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "add_query_lambda_role" {
  name               = "AddQueryLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "add_query_lambda_policy_doc" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.queries_table_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.query_counters_table_name}"
    ]
  }
  statement {
    actions = [
      "scheduler:CreateSchedule"
    ]
    resources = ["arn:aws:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/${var.scheduler_group_name}/*"]
  }
  statement {
    actions = [
      "iam:PassRole"
    ]
    resources = [
      aws_iam_role.scheduler_invocation_role.arn
    ]
  }
}

resource "aws_iam_policy" "add_query_lambda_policy" {
  name   = "AddQueryLambdaPolicy"
  policy = data.aws_iam_policy_document.add_query_lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "add_query_lambda_attach" {
  role       = aws_iam_role.add_query_lambda_role.name
  policy_arn = aws_iam_policy.add_query_lambda_policy.arn
}

# --- Code Packaging ---
data "archive_file" "add_query_zip" {
  type        = "zip"
  source_file = "${path.module}/addQuery.py"
  output_path = "${path.module}/add_query.zip"
}

# --- Lambda Definition ---
resource "aws_lambda_function" "add_query" {
  function_name    = "addQuery"
  filename         = data.archive_file.add_query_zip.output_path
  source_code_hash = data.archive_file.add_query_zip.output_base64sha256
  handler          = "addQuery.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.add_query_lambda_role.arn
  timeout          = 30

  environment {
    variables = {
      # TARGET_LAMBDA_ARN now references the resource directly
      TARGET_LAMBDA_ARN       = aws_lambda_function.analyze_bluesky_sentiment.arn
      SCHEDULER_ROLE_ARN      = aws_iam_role.scheduler_invocation_role.arn
      QUERIES_TABLE_NAME      = var.queries_table_name
      QUERY_COUNTERS_TABLE_NAME = var.query_counters_table_name
      SCHEDULER_GROUP_NAME    = var.scheduler_group_name
    }
  }

  tags = {
    Name = "AddQueryLambda"
  }

  # depends_on block simplified as Terraform infers dependencies now
  depends_on = [
    aws_iam_role_policy_attachment.add_query_lambda_attach,
    aws_iam_role_policy_attachment.scheduler_invocation_attach
  ]
}

#----------------------------------------------------------
# Lambda Function: add_data
# (No changes needed here based on removed variables)
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "add_data_lambda_role" {
  name               = "AddDataLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "add_data_lambda_policy_doc" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.data_table_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.data_counters_table_name}"
    ]
  }
}

resource "aws_iam_policy" "add_data_lambda_policy" {
  name   = "AddDataLambdaPolicy"
  policy = data.aws_iam_policy_document.add_data_lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "add_data_lambda_attach" {
  role       = aws_iam_role.add_data_lambda_role.name
  policy_arn = aws_iam_policy.add_data_lambda_policy.arn
}

# --- Code Packaging ---
data "archive_file" "add_data_zip" {
  type        = "zip"
  source_file = "${path.module}/addData.py"
  output_path = "${path.module}/add_data.zip"
}

# --- Lambda Definition ---
resource "aws_lambda_function" "add_data" {
  function_name    = "addData"
  filename         = data.archive_file.add_data_zip.output_path
  source_code_hash = data.archive_file.add_data_zip.output_base64sha256
  handler          = "addData.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.add_data_lambda_role.arn

  environment {
    variables = {
      DATA_TABLE_NAME      = var.data_table_name
      DATA_COUNTERS_TABLE_NAME = var.data_counters_table_name
    }
  }

  tags = {
    Name = "AddDataLambda"
  }

  depends_on = [aws_iam_role_policy_attachment.add_data_lambda_attach]
}

#----------------------------------------------------------
# Lambda Function: get_data_by_query_id
# (No changes needed here based on removed variables)
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "get_data_by_query_id_lambda_role" {
  name               = "GetDataByQueryIdLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "get_data_by_query_id_lambda_policy_doc" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "dynamodb:Scan"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.data_table_name}"
    ]
    # Note: Consider a GSI on QueryID for the Data table if performance is an issue.
  }
}

resource "aws_iam_policy" "get_data_by_query_id_lambda_policy" {
  name   = "GetDataByQueryIdLambdaPolicy"
  policy = data.aws_iam_policy_document.get_data_by_query_id_lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "get_data_by_query_id_lambda_attach" {
  role       = aws_iam_role.get_data_by_query_id_lambda_role.name
  policy_arn = aws_iam_policy.get_data_by_query_id_lambda_policy.arn
}

# --- Code Packaging ---
data "archive_file" "get_data_by_query_id_zip" {
  type        = "zip"
  source_file = "${path.module}/getData.py"
  output_path = "${path.module}/get_data_by_query_id.zip"
}

# --- Lambda Definition ---
resource "aws_lambda_function" "get_data_by_query_id" {
  function_name    = "getData"
  filename         = data.archive_file.get_data_by_query_id_zip.output_path
  source_code_hash = data.archive_file.get_data_by_query_id_zip.output_base64sha256
  handler          = "getData.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.get_data_by_query_id_lambda_role.arn

  environment {
    variables = {
      DATA_TABLE_NAME = var.data_table_name
    }
  }

  tags = {
    Name = "getData"
  }

  depends_on = [aws_iam_role_policy_attachment.get_data_by_query_id_lambda_attach]
}

#----------------------------------------------------------
# Lambda Function: subscribe_to_sns
# Updated to use ARN from created SNS Topic resource
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "subscribe_to_sns_lambda_role" {
  name               = "SubscribeTosnsLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "subscribe_to_sns_lambda_policy_doc" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "sns:Subscribe"
    ]
    resources = [
      # Use the ARN from the created topic resource
      aws_sns_topic.notifications.arn
    ]
  }
}

resource "aws_iam_policy" "subscribe_to_sns_lambda_policy" {
  name   = "SubscribeToSNSLambdaPolicy"
  policy = data.aws_iam_policy_document.subscribe_to_sns_lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "subscribe_to_sns_lambda_attach" {
  role       = aws_iam_role.subscribe_to_sns_lambda_role.name
  policy_arn = aws_iam_policy.subscribe_to_sns_lambda_policy.arn
}

# --- Code Packaging ---
data "archive_file" "subscribe_to_sns_zip" {
  type        = "zip"
  source_file = "${path.module}/subscribeToSns.py"
  output_path = "${path.module}/subscribe_to_sns.zip"
}

# --- Lambda Definition ---
resource "aws_lambda_function" "subscribe_to_sns" {
  function_name    = "subscribeEmailToSNS"
  filename         = data.archive_file.subscribe_to_sns_zip.output_path
  source_code_hash = data.archive_file.subscribe_to_sns_zip.output_base64sha256
  handler          = "subscribeToSns.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.subscribe_to_sns_lambda_role.arn
  timeout          = 10

  environment {
    variables = {
      # Pass the created topic ARN to the Lambda function
      SNS_TOPIC_ARN = aws_sns_topic.notifications.arn
    }
  }

  tags = {
    Name = "SubscribeTosnsLambda"
  }

  depends_on = [
    aws_iam_role_policy_attachment.subscribe_to_sns_lambda_attach,
    # Explicit dependency on the created topic
    aws_sns_topic.notifications
  ]
}

#----------------------------------------------------------
# Lambda Function: send_email
# Reminder: SENDER_EMAIL must be handled within the Lambda code
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "send_email_lambda_role" {
  name               = "SendEmailLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "send_email_lambda_policy_doc" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail"
    ]
    resources = ["*"]
    # Optionally add permissions to fetch sender email from Secrets Manager/Parameter Store
  }
  # statement {
  #   actions = ["secretsmanager:GetSecretValue"]
  #   resources = ["arn:aws:secretsmanager:REGION:ACCOUNT_ID:secret:your-ses-sender-secret-??????"]
  # }
}

resource "aws_iam_policy" "send_email_lambda_policy" {
  name   = "SendEmailLambdaPolicy"
  policy = data.aws_iam_policy_document.send_email_lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "send_email_lambda_attach" {
  role       = aws_iam_role.send_email_lambda_role.name
  policy_arn = aws_iam_policy.send_email_lambda_policy.arn
}

# --- Code Packaging ---
data "archive_file" "send_email_zip" {
  type        = "zip"
  source_file = "${path.module}/sendEmail.py"
  output_path = "${path.module}/send_email.zip"
}

# --- Lambda Definition ---
resource "aws_lambda_function" "send_email" {
  function_name    = "sendSNSToSpecificEmail"
  filename         = data.archive_file.send_email_zip.output_path
  source_code_hash = data.archive_file.send_email_zip.output_base64sha256
  handler          = "sendEmail.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.send_email_lambda_role.arn
  timeout          = 10

  environment {
    variables = {
      # SENDER_EMAIL removed. Update sendEmail.py to fetch/define it.
    }
  }

  tags = {
    Name = "SendEmailLambda"
  }

  depends_on = [aws_iam_role_policy_attachment.send_email_lambda_attach]
}


#----------------------------------------------------------
# Lambda Function: AnalyzeBlueskySentiment
# Reminder: Bluesky credentials must be handled within the Lambda code
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "analyze_bluesky_sentiment_role" {
  name               = "AnalyzeBlueskySentimentRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
  description        = "Role for the Lambda function analyzing Bluesky sentiment"
}

data "aws_iam_policy_document" "analyze_bluesky_sentiment_policy_doc" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Scan" # Note: Consider GSI for efficiency if scanning based on QueryID
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.queries_table_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.data_table_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.data_counters_table_name}"
    ]
  }
  statement {
    actions = [
      "comprehend:DetectSentiment"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "scheduler:DeleteSchedule"
    ]
    resources = [
      "arn:aws:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/${var.scheduler_group_name}/BlueskyAnalysis-Query-*"
    ]
  }
  # *** ADD PERMISSIONS TO FETCH BLUESKY CREDENTIALS ***
  # statement {
  #   actions = ["secretsmanager:GetSecretValue"]
  #   resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:YOUR_BLUESKY_SECRET_NAME-??????"]
  # }
}

resource "aws_iam_policy" "analyze_bluesky_sentiment_policy" {
  name        = "AnalyzeBlueskySentimentPolicy"
  description = "Policy for the AnalyzeBlueskySentiment Lambda"
  policy      = data.aws_iam_policy_document.analyze_bluesky_sentiment_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "analyze_bluesky_sentiment_attach" {
  role       = aws_iam_role.analyze_bluesky_sentiment_role.name
  policy_arn = aws_iam_policy.analyze_bluesky_sentiment_policy.arn
}

# --- Code Packaging ---
data "archive_file" "analyze_bluesky_sentiment_zip" {
  type        = "zip"
  source_dir  = var.lambda_src_path
  output_path = "${path.module}/blueskyLambda.zip"
  excludes    = ["*.tf", "*.tfvars", ".terraform", "*.zip", ".git"]
}

# --- Lambda Definition ---
resource "aws_lambda_function" "analyze_bluesky_sentiment" {
  function_name = "my-ts-lambda-function"
  filename      = data.archive_file.analyze_bluesky_sentiment_zip.output_path
  source_code_hash = data.archive_file.analyze_bluesky_sentiment_zip.output_base64sha256
  handler     = "blueskyLambda.handler"
  runtime     = var.nodejs_runtime
  role        = aws_iam_role.analyze_bluesky_sentiment_role.arn
  timeout     = 60
  memory_size = 512

  environment {
    variables = {
      QUERIES_TABLE_NAME    = var.queries_table_name
      DATA_TABLE_NAME       = var.data_table_name
      COUNTERS_TABLE_NAME   = var.data_counters_table_name
      SCHEDULER_GROUP_NAME  = var.scheduler_group_name
      # BLUESKY_HANDLE and BLUESKY_APP_PASSWORD removed. Update blueskyLambda.js.
      AWS_NODEJS_CONNECTION_REUSE_ENABLED = "1"
      # Optionally pass Secret ARN or Parameter names if needed by the code:
      # BLUESKY_SECRET_ARN = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:YOUR_BLUESKY_SECRET_NAME-??????"
    }
  }

  tags = {
    Name = "AnalyzeBlueskySentimentLambda"
  }

  depends_on = [
    aws_iam_role_policy_attachment.analyze_bluesky_sentiment_attach
  ]
}


#----------------------------------------------------------
# Lambda Function: get_subtopics
# (No changes needed here based on removed variables)
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "get_subtopics_lambda_role" {
  name               = "GetSubtopicsLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "get_subtopics_lambda_policy_doc" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "dynamodb:Query"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.subtopics_table_name}"
    ]
  }
}

resource "aws_iam_policy" "get_subtopics_lambda_policy" {
  name   = "GetSubtopicsLambdaPolicy"
  policy = data.aws_iam_policy_document.get_subtopics_lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "get_subtopics_lambda_attach" {
  role       = aws_iam_role.get_subtopics_lambda_role.name
  policy_arn = aws_iam_policy.get_subtopics_lambda_policy.arn
}

# --- Code Packaging ---
data "archive_file" "get_subtopics_zip" {
  type        = "zip"
  source_file = "${path.module}/getSubtopics.py"
  output_path = "${path.module}/get_subtopics.zip"
}

# --- Lambda Definition ---
resource "aws_lambda_function" "get_subtopics" {
  function_name    = "getSubtopic"
  filename         = data.archive_file.get_subtopics_zip.output_path
  source_code_hash = data.archive_file.get_subtopics_zip.output_base64sha256
  handler          = "getSubtopics.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.get_subtopics_lambda_role.arn

  environment {
    variables = {
      SUBTOPICS_TABLE_NAME = var.subtopics_table_name
    }
  }

  tags = {
    Name = "GetSubtopicsLambda"
  }

  depends_on = [aws_iam_role_policy_attachment.get_subtopics_lambda_attach]
}

#----------------------------------------------------------
# Lambda Function: add_subtopic
# (No changes needed here based on removed variables)
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "add_subtopic_lambda_role" {
  name               = "AddSubtopicLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "add_subtopic_lambda_policy_doc" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "dynamodb:PutItem"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.subtopics_table_name}"
    ]
  }
}

resource "aws_iam_policy" "add_subtopic_lambda_policy" {
  name   = "AddSubtopicLambdaPolicy"
  policy = data.aws_iam_policy_document.add_subtopic_lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "add_subtopic_lambda_attach" {
  role       = aws_iam_role.add_subtopic_lambda_role.name
  policy_arn = aws_iam_policy.add_subtopic_lambda_policy.arn
}

# --- Code Packaging ---
data "archive_file" "add_subtopic_zip" {
  type        = "zip"
  source_file = "${path.module}/addSubtopic.py"
  output_path = "${path.module}/add_subtopic.zip"
}

# --- Lambda Definition ---
resource "aws_lambda_function" "add_subtopic" {
  function_name    = "addSubtopic"
  filename         = data.archive_file.add_subtopic_zip.output_path
  source_code_hash = data.archive_file.add_subtopic_zip.output_base64sha256
  handler          = "addSubtopic.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.add_subtopic_lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.subtopics_table_name
    }
  }

  tags = {
    Name = "AddSubtopicLambda"
  }

  depends_on = [aws_iam_role_policy_attachment.add_subtopic_lambda_attach]
}


#----------------------------------------------------------
# API Gateway Resources
# (No changes needed here based on removed variables)
#----------------------------------------------------------
# ... [Existing API Gateway resources - aws_api_gateway_*, aws_lambda_permission, etc. remain the same] ...
# 1. Create the REST API
resource "aws_api_gateway_rest_api" "my_api" {
  name        = "PROJECT-API"
  description = "API Gateway triggering Lambdas"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# 2. Define Resources (Paths)
resource "aws_api_gateway_resource" "data" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "data"
}
resource "aws_api_gateway_resource" "data_retrieve" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_resource.data.id
  path_part   = "retrieve"
}
resource "aws_api_gateway_resource" "data_send" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_resource.data.id
  path_part   = "send"
}
resource "aws_api_gateway_resource" "notifications" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "notifications"
}
resource "aws_api_gateway_resource" "notifications_send" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_resource.notifications.id
  path_part   = "send"
}
resource "aws_api_gateway_resource" "notifications_subscribe" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_resource.notifications.id
  path_part   = "subscribe"
}
resource "aws_api_gateway_resource" "queries" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "queries"
}
resource "aws_api_gateway_resource" "queries_retrieve" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_resource.queries.id
  path_part   = "retrieve"
}
resource "aws_api_gateway_resource" "queries_send" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_resource.queries.id
  path_part   = "send"
}
resource "aws_api_gateway_resource" "subtopics" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "subtopics"
}
resource "aws_api_gateway_resource" "subtopics_retrieve" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_resource.subtopics.id
  path_part   = "retrieve"
}
resource "aws_api_gateway_resource" "subtopics_send" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_resource.subtopics.id
  path_part   = "send"
}

# 3. Define Methods and Integrations
# --- /data/retrieve (GET -> get_data_by_query_id) ---
resource "aws_api_gateway_method" "data_retrieve_get" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.data_retrieve.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "data_retrieve_get_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.data_retrieve.id
  http_method           = aws_api_gateway_method.data_retrieve_get.http_method
  integration_http_method = "POST"
  type                  = "AWS_PROXY"
  uri                   = aws_lambda_function.get_data_by_query_id.invoke_arn
}
resource "aws_api_gateway_method_response" "data_retrieve_get_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.data_retrieve.id
  http_method = aws_api_gateway_method.data_retrieve_get.http_method
  status_code = "200"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}
resource "aws_api_gateway_integration_response" "data_retrieve_get_lambda_resp" {
    rest_api_id = aws_api_gateway_rest_api.my_api.id
    resource_id = aws_api_gateway_resource.data_retrieve.id
    http_method = aws_api_gateway_method.data_retrieve_get.http_method
    status_code = aws_api_gateway_method_response.data_retrieve_get_200.status_code
    response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
    depends_on = [aws_api_gateway_integration.data_retrieve_get_lambda]
}
# --- /data/retrieve (OPTIONS - CORS Preflight) ---
resource "aws_api_gateway_method" "data_retrieve_options" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.data_retrieve.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "data_retrieve_options_mock" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.data_retrieve.id
  http_method = aws_api_gateway_method.data_retrieve_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}
resource "aws_api_gateway_method_response" "data_retrieve_options_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.data_retrieve.id
  http_method = aws_api_gateway_method.data_retrieve_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = { "application/json" = "Empty" }
}
resource "aws_api_gateway_integration_response" "data_retrieve_options_mock_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.data_retrieve.id
  http_method = aws_api_gateway_method.data_retrieve_options.http_method
  status_code = aws_api_gateway_method_response.data_retrieve_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = { "application/json" = "" }
  depends_on = [aws_api_gateway_method.data_retrieve_options]
}

# --- /data/send (POST -> add_data) ---
resource "aws_api_gateway_method" "data_send_post" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.data_send.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "data_send_post_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.data_send.id
  http_method           = aws_api_gateway_method.data_send_post.http_method
  integration_http_method = "POST"
  type                  = "AWS_PROXY"
  uri                   = aws_lambda_function.add_data.invoke_arn
}
resource "aws_api_gateway_method_response" "data_send_post_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.data_send.id
  http_method = aws_api_gateway_method.data_send_post.http_method
  status_code = "200"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}
resource "aws_api_gateway_integration_response" "data_send_post_lambda_resp" {
    rest_api_id = aws_api_gateway_rest_api.my_api.id
    resource_id = aws_api_gateway_resource.data_send.id
    http_method = aws_api_gateway_method.data_send_post.http_method
    status_code = aws_api_gateway_method_response.data_send_post_200.status_code
    response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
    depends_on = [aws_api_gateway_integration.data_send_post_lambda]
}
# --- /data/send (OPTIONS - CORS Preflight) ---
resource "aws_api_gateway_method" "data_send_options" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.data_send.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "data_send_options_mock" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.data_send.id
  http_method = aws_api_gateway_method.data_send_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}
resource "aws_api_gateway_method_response" "data_send_options_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.data_send.id
  http_method = aws_api_gateway_method.data_send_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = { "application/json" = "Empty" }
}
resource "aws_api_gateway_integration_response" "data_send_options_mock_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.data_send.id
  http_method = aws_api_gateway_method.data_send_options.http_method
  status_code = aws_api_gateway_method_response.data_send_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = { "application/json" = "" }
  depends_on         = [aws_api_gateway_method.data_send_options]
}

# --- /notifications/send (POST -> send_email) ---
resource "aws_api_gateway_method" "notifications_send_post" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.notifications_send.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "notifications_send_post_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.notifications_send.id
  http_method           = aws_api_gateway_method.notifications_send_post.http_method
  integration_http_method = "POST"
  type                  = "AWS_PROXY"
  uri                   = aws_lambda_function.send_email.invoke_arn
}
resource "aws_api_gateway_method_response" "notifications_send_post_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.notifications_send.id
  http_method = aws_api_gateway_method.notifications_send_post.http_method
  status_code = "200"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}
resource "aws_api_gateway_integration_response" "notifications_send_post_lambda_resp" {
    rest_api_id = aws_api_gateway_rest_api.my_api.id
    resource_id = aws_api_gateway_resource.notifications_send.id
    http_method = aws_api_gateway_method.notifications_send_post.http_method
    status_code = aws_api_gateway_method_response.notifications_send_post_200.status_code
    response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
    depends_on = [aws_api_gateway_integration.notifications_send_post_lambda]
}
# --- /notifications/send (OPTIONS - CORS Preflight) ---
resource "aws_api_gateway_method" "notifications_send_options" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.notifications_send.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "notifications_send_options_mock" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.notifications_send.id
  http_method = aws_api_gateway_method.notifications_send_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}
resource "aws_api_gateway_method_response" "notifications_send_options_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.notifications_send.id
  http_method = aws_api_gateway_method.notifications_send_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = { "application/json" = "Empty" }
}
resource "aws_api_gateway_integration_response" "notifications_send_options_mock_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.notifications_send.id
  http_method = aws_api_gateway_method.notifications_send_options.http_method
  status_code = aws_api_gateway_method_response.notifications_send_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = { "application/json" = "" }
  depends_on         = [aws_api_gateway_method.notifications_send_options]
}

# --- /notifications/subscribe (POST -> subscribe_to_sns) ---
resource "aws_api_gateway_method" "notifications_subscribe_post" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.notifications_subscribe.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "notifications_subscribe_post_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.notifications_subscribe.id
  http_method           = aws_api_gateway_method.notifications_subscribe_post.http_method
  integration_http_method = "POST"
  type                  = "AWS_PROXY"
  uri                   = aws_lambda_function.subscribe_to_sns.invoke_arn
}
resource "aws_api_gateway_method_response" "notifications_subscribe_post_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.notifications_subscribe.id
  http_method = aws_api_gateway_method.notifications_subscribe_post.http_method
  status_code = "200"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}
resource "aws_api_gateway_integration_response" "notifications_subscribe_post_lambda_resp" {
    rest_api_id = aws_api_gateway_rest_api.my_api.id
    resource_id = aws_api_gateway_resource.notifications_subscribe.id
    http_method = aws_api_gateway_method.notifications_subscribe_post.http_method
    status_code = aws_api_gateway_method_response.notifications_subscribe_post_200.status_code
    response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
    depends_on = [aws_api_gateway_integration.notifications_subscribe_post_lambda]
}
# --- /notifications/subscribe (OPTIONS - CORS Preflight) ---
resource "aws_api_gateway_method" "notifications_subscribe_options" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.notifications_subscribe.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "notifications_subscribe_options_mock" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.notifications_subscribe.id
  http_method = aws_api_gateway_method.notifications_subscribe_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}
resource "aws_api_gateway_method_response" "notifications_subscribe_options_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.notifications_subscribe.id
  http_method = aws_api_gateway_method.notifications_subscribe_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = { "application/json" = "Empty" }
}
resource "aws_api_gateway_integration_response" "notifications_subscribe_options_mock_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.notifications_subscribe.id
  http_method = aws_api_gateway_method.notifications_subscribe_options.http_method
  status_code = aws_api_gateway_method_response.notifications_subscribe_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = { "application/json" = "" }
  depends_on         = [aws_api_gateway_method.notifications_subscribe_options]
}

# --- /queries/retrieve (GET -> get_queries_by_email) ---
resource "aws_api_gateway_method" "queries_retrieve_get" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.queries_retrieve.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "queries_retrieve_get_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.queries_retrieve.id
  http_method           = aws_api_gateway_method.queries_retrieve_get.http_method
  integration_http_method = "POST"
  type                  = "AWS_PROXY"
  uri                   = aws_lambda_function.get_queries_by_email.invoke_arn
}
resource "aws_api_gateway_method_response" "queries_retrieve_get_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.queries_retrieve.id
  http_method = aws_api_gateway_method.queries_retrieve_get.http_method
  status_code = "200"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}
resource "aws_api_gateway_integration_response" "queries_retrieve_get_lambda_resp" {
    rest_api_id = aws_api_gateway_rest_api.my_api.id
    resource_id = aws_api_gateway_resource.queries_retrieve.id
    http_method = aws_api_gateway_method.queries_retrieve_get.http_method
    status_code = aws_api_gateway_method_response.queries_retrieve_get_200.status_code
    response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
    depends_on = [aws_api_gateway_integration.queries_retrieve_get_lambda]
}
# --- /queries/retrieve (OPTIONS - CORS Preflight) ---
resource "aws_api_gateway_method" "queries_retrieve_options" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.queries_retrieve.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "queries_retrieve_options_mock" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.queries_retrieve.id
  http_method = aws_api_gateway_method.queries_retrieve_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}
resource "aws_api_gateway_method_response" "queries_retrieve_options_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.queries_retrieve.id
  http_method = aws_api_gateway_method.queries_retrieve_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = { "application/json" = "Empty" }
}
resource "aws_api_gateway_integration_response" "queries_retrieve_options_mock_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.queries_retrieve.id
  http_method = aws_api_gateway_method.queries_retrieve_options.http_method
  status_code = aws_api_gateway_method_response.queries_retrieve_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = { "application/json" = "" }
  depends_on         = [aws_api_gateway_method.queries_retrieve_options]
}

# --- /queries/send (POST -> add_query) ---
resource "aws_api_gateway_method" "queries_send_post" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.queries_send.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "queries_send_post_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.queries_send.id
  http_method           = aws_api_gateway_method.queries_send_post.http_method
  integration_http_method = "POST"
  type                  = "AWS_PROXY"
  uri                   = aws_lambda_function.add_query.invoke_arn
}
resource "aws_api_gateway_method_response" "queries_send_post_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.queries_send.id
  http_method = aws_api_gateway_method.queries_send_post.http_method
  status_code = "200"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}
resource "aws_api_gateway_integration_response" "queries_send_post_lambda_resp" {
    rest_api_id = aws_api_gateway_rest_api.my_api.id
    resource_id = aws_api_gateway_resource.queries_send.id
    http_method = aws_api_gateway_method.queries_send_post.http_method
    status_code = aws_api_gateway_method_response.queries_send_post_200.status_code
    response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
    depends_on = [aws_api_gateway_integration.queries_send_post_lambda]
}
# --- /queries/send (OPTIONS - CORS Preflight) ---
resource "aws_api_gateway_method" "queries_send_options" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.queries_send.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "queries_send_options_mock" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.queries_send.id
  http_method = aws_api_gateway_method.queries_send_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}
resource "aws_api_gateway_method_response" "queries_send_options_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.queries_send.id
  http_method = aws_api_gateway_method.queries_send_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = { "application/json" = "Empty" }
}
resource "aws_api_gateway_integration_response" "queries_send_options_mock_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.queries_send.id
  http_method = aws_api_gateway_method.queries_send_options.http_method
  status_code = aws_api_gateway_method_response.queries_send_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = { "application/json" = "" }
  depends_on         = [aws_api_gateway_method.queries_send_options]
}

# --- /subtopics/retrieve (GET -> get_subtopics) ---
resource "aws_api_gateway_method" "subtopics_retrieve_get" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.subtopics_retrieve.id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "subtopics_retrieve_get_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.subtopics_retrieve.id
  http_method           = aws_api_gateway_method.subtopics_retrieve_get.http_method
  integration_http_method = "POST"
  type                  = "AWS_PROXY"
  uri                   = aws_lambda_function.get_subtopics.invoke_arn
}
resource "aws_api_gateway_method_response" "subtopics_retrieve_get_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_retrieve.id
  http_method = aws_api_gateway_method.subtopics_retrieve_get.http_method
  status_code = "200"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}
resource "aws_api_gateway_integration_response" "subtopics_retrieve_get_lambda_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_retrieve.id
  http_method = aws_api_gateway_method.subtopics_retrieve_get.http_method
  status_code = aws_api_gateway_method_response.subtopics_retrieve_get_200.status_code
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
  depends_on = [aws_api_gateway_integration.subtopics_retrieve_get_lambda]
}
# --- /subtopics/retrieve (OPTIONS - CORS Preflight) ---
resource "aws_api_gateway_method" "subtopics_retrieve_options" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.subtopics_retrieve.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "subtopics_retrieve_options_mock" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_retrieve.id
  http_method = aws_api_gateway_method.subtopics_retrieve_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}
resource "aws_api_gateway_method_response" "subtopics_retrieve_options_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_retrieve.id
  http_method = aws_api_gateway_method.subtopics_retrieve_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = { "application/json" = "Empty" }
}
resource "aws_api_gateway_integration_response" "subtopics_retrieve_options_mock_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_retrieve.id
  http_method = aws_api_gateway_method.subtopics_retrieve_options.http_method
  status_code = aws_api_gateway_method_response.subtopics_retrieve_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = { "application/json" = "" }
  depends_on = [aws_api_gateway_method.subtopics_retrieve_options]
}

# --- /subtopics/send (POST -> add_subtopic) ---
resource "aws_api_gateway_method" "subtopics_send_post" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.subtopics_send.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "subtopics_send_post_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.subtopics_send.id
  http_method           = aws_api_gateway_method.subtopics_send_post.http_method
  integration_http_method = "POST"
  type                  = "AWS_PROXY"
  uri                   = aws_lambda_function.add_subtopic.invoke_arn
}
resource "aws_api_gateway_method_response" "subtopics_send_post_201" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_send.id
  http_method = aws_api_gateway_method.subtopics_send_post.http_method
  status_code = "201"
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = true }
}
resource "aws_api_gateway_integration_response" "subtopics_send_post_lambda_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_send.id
  http_method = aws_api_gateway_method.subtopics_send_post.http_method
  status_code = aws_api_gateway_method_response.subtopics_send_post_201.status_code
  response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" }
  depends_on = [aws_api_gateway_integration.subtopics_send_post_lambda]
}
# --- /subtopics/send (OPTIONS - CORS Preflight) ---
resource "aws_api_gateway_method" "subtopics_send_options" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.subtopics_send.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "subtopics_send_options_mock" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_send.id
  http_method = aws_api_gateway_method.subtopics_send_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}
resource "aws_api_gateway_method_response" "subtopics_send_options_200" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_send.id
  http_method = aws_api_gateway_method.subtopics_send_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = { "application/json" = "Empty" }
}
resource "aws_api_gateway_integration_response" "subtopics_send_options_mock_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_send.id
  http_method = aws_api_gateway_method.subtopics_send_options.http_method
  status_code = aws_api_gateway_method_response.subtopics_send_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = { "application/json" = "" }
  depends_on         = [aws_api_gateway_method.subtopics_send_options]
}

#----------------------------------------------------------
# Lambda Permissions for API Gateway Invocation
#----------------------------------------------------------
resource "aws_lambda_permission" "apigw_invoke_get_data_by_query_id" {
  statement_id  = "AllowAPIGatewayInvokeGetDataByQueryId"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_data_by_query_id.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.my_api.id}/*/${aws_api_gateway_method.data_retrieve_get.http_method}${aws_api_gateway_resource.data_retrieve.path}"
}
resource "aws_lambda_permission" "apigw_invoke_add_data" {
  statement_id  = "AllowAPIGatewayInvokeAddData"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_data.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.my_api.id}/*/${aws_api_gateway_method.data_send_post.http_method}${aws_api_gateway_resource.data_send.path}"
}
resource "aws_lambda_permission" "apigw_invoke_send_email" {
  statement_id  = "AllowAPIGatewayInvokeSendEmail"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.send_email.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.my_api.id}/*/${aws_api_gateway_method.notifications_send_post.http_method}${aws_api_gateway_resource.notifications_send.path}"
}
resource "aws_lambda_permission" "apigw_invoke_subscribe_to_sns" {
  statement_id  = "AllowAPIGatewayInvokeSubscribeToSns"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subscribe_to_sns.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.my_api.id}/*/${aws_api_gateway_method.notifications_subscribe_post.http_method}${aws_api_gateway_resource.notifications_subscribe.path}"
}
resource "aws_lambda_permission" "apigw_invoke_get_queries_by_email" {
  statement_id  = "AllowAPIGatewayInvokeGetQueriesByEmail"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_queries_by_email.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.my_api.id}/*/${aws_api_gateway_method.queries_retrieve_get.http_method}${aws_api_gateway_resource.queries_retrieve.path}"
}
resource "aws_lambda_permission" "apigw_invoke_add_query" {
  statement_id  = "AllowAPIGatewayInvokeAddQuery"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.my_api.id}/*/${aws_api_gateway_method.queries_send_post.http_method}${aws_api_gateway_resource.queries_send.path}"
}
resource "aws_lambda_permission" "apigw_invoke_get_subtopics" {
  statement_id  = "AllowAPIGatewayInvokeGetSubtopics"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_subtopics.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.my_api.id}/*/${aws_api_gateway_method.subtopics_retrieve_get.http_method}${aws_api_gateway_resource.subtopics_retrieve.path}"
}
resource "aws_lambda_permission" "apigw_invoke_add_subtopic" {
  statement_id  = "AllowAPIGatewayInvokeAddSubtopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_subtopic.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.my_api.id}/*/${aws_api_gateway_method.subtopics_send_post.http_method}${aws_api_gateway_resource.subtopics_send.path}"
}


#----------------------------------------------------------
# API Gateway Deployment & Stage
#----------------------------------------------------------
resource "aws_api_gateway_deployment" "my_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      # Integrations
      aws_api_gateway_integration.data_retrieve_get_lambda.id,
      aws_api_gateway_integration.data_send_post_lambda.id,
      aws_api_gateway_integration.notifications_send_post_lambda.id,
      aws_api_gateway_integration.notifications_subscribe_post_lambda.id,
      aws_api_gateway_integration.queries_retrieve_get_lambda.id,
      aws_api_gateway_integration.queries_send_post_lambda.id,
      aws_api_gateway_integration.subtopics_retrieve_get_lambda.id,
      aws_api_gateway_integration.subtopics_send_post_lambda.id,
      # OPTIONS Methods/Integrations
      aws_api_gateway_method.data_retrieve_options.id,
      aws_api_gateway_integration.data_retrieve_options_mock.id,
      aws_api_gateway_method.data_send_options.id,
      aws_api_gateway_integration.data_send_options_mock.id,
      aws_api_gateway_method.notifications_send_options.id,
      aws_api_gateway_integration.notifications_send_options_mock.id,
      aws_api_gateway_method.notifications_subscribe_options.id,
      aws_api_gateway_integration.notifications_subscribe_options_mock.id,
      aws_api_gateway_method.queries_retrieve_options.id,
      aws_api_gateway_integration.queries_retrieve_options_mock.id,
      aws_api_gateway_method.queries_send_options.id,
      aws_api_gateway_integration.queries_send_options_mock.id,
      aws_api_gateway_method.subtopics_retrieve_options.id,
      aws_api_gateway_integration.subtopics_retrieve_options_mock.id,
      aws_api_gateway_method.subtopics_send_options.id,
      aws_api_gateway_integration.subtopics_send_options_mock.id,
      # Lambda Permissions
      aws_lambda_permission.apigw_invoke_get_data_by_query_id.id,
      aws_lambda_permission.apigw_invoke_add_data.id,
      aws_lambda_permission.apigw_invoke_send_email.id,
      aws_lambda_permission.apigw_invoke_subscribe_to_sns.id,
      aws_lambda_permission.apigw_invoke_get_queries_by_email.id,
      aws_lambda_permission.apigw_invoke_add_query.id,
      aws_lambda_permission.apigw_invoke_get_subtopics.id,
      aws_lambda_permission.apigw_invoke_add_subtopic.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "v1" {
  deployment_id = aws_api_gateway_deployment.my_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  stage_name    = "v1"

  # Enable CloudWatch Logs for the API Gateway stage
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format          = jsonencode({ "requestId":"$context.requestId", "ip": "$context.identity.sourceIp", "caller":"$context.identity.caller", "user":"$context.identity.user","requestTime":"$context.requestTime", "httpMethod":"$context.httpMethod","resourcePath":"$context.resourcePath", "status":"$context.status","protocol":"$context.protocol", "responseLength":"$context.responseLength" })
  }

}

# Create a CloudWatch Log Group for API Gateway logs
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.my_api.name}-v1" # Matches typical pattern
  retention_in_days = 7 # Adjust retention as needed

  tags = {
    Name = "APIGatewayLogs-${aws_api_gateway_rest_api.my_api.name}"
  }
}
 resource "aws_iam_role" "api_gateway_cloudwatch_role" {
   name = "api-gateway-cloudwatch-logging-role"
   assume_role_policy = jsonencode({
     Version = "2012-10-17"
     Statement = [{
       Action = "sts:AssumeRole"
       Effect = "Allow"
       Principal = {
         Service = "apigateway.amazonaws.com"
       }
     }]
   })
 }
 resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy_attach" {
    role = aws_iam_role.api_gateway_cloudwatch_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
 }
