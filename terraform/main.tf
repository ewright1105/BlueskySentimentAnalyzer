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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1" # Added for random_id
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
  default     = "us-east-2" # <-- CHANGE AS NEEDED (Ensure consistency)
}

variable "lambda_src_path" {
  description = "Path to the directory containing the Node.js Lambda source code files (blueskyLambda.js, node_modules, etc.)"
  type        = string
  default     = "./" # <-- CHANGE THIS
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

# --- Names of DynamoDB Tables to be CREATED by this config ---
variable "queries_table_name" {
  description = "Name of the DynamoDB table for queries"
  type        = string
  default     = "Queries"
}

variable "query_counters_table_name" {
  description = "Name of the DynamoDB table for query counters"
  type        = string
  default     = "CountersQuery"
}

variable "data_table_name" {
  description = "Name of the DynamoDB table for data"
  type        = string
  default     = "Data"
}

variable "data_counters_table_name" {
  description = "Name of the DynamoDB table for data counters"
  type        = string
  default     = "CountersData"
}

variable "subtopics_table_name" {
  description = "Name of the DynamoDB table for subtopics"
  type        = string
  default     = "Subtopics"
}

# --- SES Configuration ---
# Note: The send_email Lambda code MUST be updated to retrieve the sender email
# from a secure source like Secrets Manager or Parameter Store, or be hardcoded (not recommended).

# --- EventBridge Scheduler Variables ---
variable "scheduler_group_name" {
  description = "Name of the EventBridge Scheduler group used for schedules"
  type        = string
  default     = "default" # Match the group name used/expected in the Node.js code
}

# --- Bluesky Credentials ---
# Note: The AnalyzeBlueskySentiment Lambda code MUST be updated to retrieve credentials
# securely from Secrets Manager or Parameter Store.

# --- Amplify/Cognito Variables ---
variable "cognito_domain_prefix" {
  description = "Domain prefix for Cognito Hosted UI (must be globally unique)"
  type        = string
  default     = "team8-auth-team888-someuniqueval" # <-- CHANGE TO BE GLOBALLY UNIQUE
}

#----------------------------------------------------------
# Random ID for Uniqueness
#----------------------------------------------------------
resource "random_id" "unique_suffix" {
  byte_length = 8
}

#----------------------------------------------------------
# DynamoDB Table Resources
#----------------------------------------------------------

resource "aws_dynamodb_table" "counter_table_query" {
  name           = var.query_counters_table_name # Use variable for name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "CounterName"

  attribute {
    name = "CounterName"
    type = "S"
  }

  tags = {
    Name        = "counter_table_query" # Tag for identification
    Environment = "production" # Or appropriate environment tag
    ManagedBy   = "Terraform"
  }
}

resource "aws_dynamodb_table" "counter_table_data" {
  name           = var.data_counters_table_name # Use variable for name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "CounterName"

  attribute {
    name = "CounterName"
    type = "S"
  }

  tags = {
    Name        = "counter_table_data" # Tag for identification
    Environment = "production" # Or appropriate environment tag
    ManagedBy   = "Terraform"
  }
}

resource "aws_dynamodb_table" "query_table" {
  name           = var.queries_table_name # Use variable for name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "QueryID"
  range_key      = "Topic" # Topic remains part of the primary key here

  attribute {
    name = "QueryID"
    type = "N"
  }

  attribute {
    name = "Topic"
    type = "S"
  }

  # Attributes below are not part of the key but must be defined if used in GSIs
  attribute {
    name = "Email"
    type = "S"
  }

  attribute {
    name = "NumIntervals"
    type = "N"
  }

  attribute {
    name = "PostsToAnalyze"
    type = "N"
  }

  attribute {
    name = "IntervalLength"
    type = "N"
  }

  # GSIs remain the same
  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "Email"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "NumIntervalsIndex"
    hash_key        = "NumIntervals"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "PostsToAnalyzeIndex"
    hash_key        = "PostsToAnalyze"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "IntervalLengthIndex"
    hash_key        = "IntervalLength"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }

  tags = {
    Name        = "query_table" # Tag for identification
    Environment = "production" # Or appropriate environment tag
    ManagedBy   = "Terraform"
  }
}

resource "aws_dynamodb_table" "subtopics_table" {
  name           = var.subtopics_table_name # Use variable for name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "QueryID"    # Link subtopic back to the main Query
  range_key      = "Subtopic" # Unique name or ID for the subtopic within the query

  attribute {
    name = "QueryID"
    type = "N"
  }

  attribute {
    name = "Subtopic" # Could be the actual name or a generated subtopic ID
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist" # Optional: TTL for subtopic definitions
    enabled        = true
  }

  tags = {
    Name        = "subtopics_table" # Tag for identification
    Environment = "production" # Or appropriate environment tag
    ManagedBy   = "Terraform"
  }
}

resource "aws_dynamodb_table" "data_table" {
  name         = var.data_table_name # Use variable for name
  billing_mode = "PAY_PER_REQUEST"
  hash_key  = "DataID"
  range_key = "QueryID"

  attribute {
    name = "DataID"
    type = "N"
  }
  attribute {
    name = "QueryID"
    type = "N"
  }

  attribute {
    name = "Topic"
    type = "S"
  }

  # Data attributes remain the same
  attribute {
    name = "PostsAnalyzed"
    type = "N"
  }
  attribute {
    name = "PositivePosts"
    type = "N"
  }
  attribute {
    name = "NeutralPosts"
    type = "N"
  }
  attribute {
    name = "NegativePosts"
    type = "N"
  }
  attribute {
    name = "MixedPosts"
    type = "N"
  }

  global_secondary_index {
    name            = "TopicID" # Consider renaming GSI for clarity if needed, e.g., TopicIndex
    hash_key        = "Topic"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "PostsAnalyzedIndex"
    hash_key        = "PostsAnalyzed"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "PositivePostsIndex"
    hash_key        = "PositivePosts"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "NeutralPostsIndex"
    hash_key        = "NeutralPosts"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "NegativePostsIndex"
    hash_key        = "NegativePosts"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "MixedPostsIndex"
    hash_key        = "MixedPosts"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }

  tags = {
    Name        = "data_table" # Tag for identification
    Environment = "production" # Or appropriate environment tag
    ManagedBy   = "Terraform"
  }
}


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
  name               = "EventBridgeSchedulerInvokeLambdaRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
  name        = "EventBridgeSchedulerInvokeLambdaPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
  description = "Policy allowing EventBridge Scheduler to invoke the target Lambda"
  policy      = data.aws_iam_policy_document.scheduler_invocation_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "scheduler_invocation_attach" {
  role       = aws_iam_role.scheduler_invocation_role.name
  policy_arn = aws_iam_policy.scheduler_invocation_policy.arn
}


#----------------------------------------------------------
# Lambda Function: get_queries_by_email
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "get_queries_by_email_lambda_role" {
  name               = "GetQueriesByEmailLambdaRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
      # Reference the table ARN using the variable - Terraform will resolve this
      aws_dynamodb_table.query_table.arn,
      "${aws_dynamodb_table.query_table.arn}/index/EmailIndex" # Reference the GSI ARN
    ]
  }
}

resource "aws_iam_policy" "get_queries_by_email_lambda_policy" {
  name   = "GetQueriesByEmailLambdaPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
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
  function_name    = "getQueries" # Ensure unique name
  filename         = data.archive_file.get_queries_by_email_zip.output_path
  source_code_hash = data.archive_file.get_queries_by_email_zip.output_base64sha256
  handler          = "getQuery.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.get_queries_by_email_lambda_role.arn

  environment {
    variables = {
      QUERIES_TABLE_NAME = var.queries_table_name # Pass table name variable
    }
  }

  tags = {
    Name = "GetQueriesByEmailLambda"
  }

  depends_on = [
     aws_iam_role_policy_attachment.get_queries_by_email_lambda_attach,
     aws_dynamodb_table.query_table # Explicit dependency on the table it uses
  ]
}

#----------------------------------------------------------
# Lambda Function: add_query
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "add_query_lambda_role" {
  name               = "AddQueryLambdaRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
      aws_dynamodb_table.query_table.arn,          # Reference table ARN
      aws_dynamodb_table.counter_table_query.arn   # Reference counter table ARN
    ]
  }
  statement {
    actions = [
      "scheduler:CreateSchedule"
    ]
    # Resource needs to be specific enough, including the group name
    resources = ["arn:aws:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/${var.scheduler_group_name}/*"]
  }
  statement {
    actions = [
      "iam:PassRole"
    ]
    resources = [
      aws_iam_role.scheduler_invocation_role.arn # Allow passing the scheduler role
    ]
  }
}

resource "aws_iam_policy" "add_query_lambda_policy" {
  name   = "AddQueryLambdaPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
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
  function_name    = "addQuery" # Ensure unique name
  filename         = data.archive_file.add_query_zip.output_path
  source_code_hash = data.archive_file.add_query_zip.output_base64sha256
  handler          = "addQuery.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.add_query_lambda_role.arn
  timeout          = 30

  environment {
    variables = {
      TARGET_LAMBDA_ARN       = aws_lambda_function.analyze_bluesky_sentiment.arn
      SCHEDULER_ROLE_ARN      = aws_iam_role.scheduler_invocation_role.arn
      QUERIES_TABLE_NAME      = var.queries_table_name        # Pass table name variable
      QUERY_COUNTERS_TABLE_NAME = var.query_counters_table_name # Pass counter table name variable
      SCHEDULER_GROUP_NAME    = var.scheduler_group_name
    }
  }

  tags = {
    Name = "AddQueryLambda"
  }

  depends_on = [
    aws_iam_role_policy_attachment.add_query_lambda_attach,
    aws_iam_role_policy_attachment.scheduler_invocation_attach,
    aws_dynamodb_table.query_table, # Explicit dependencies
    aws_dynamodb_table.counter_table_query
    # Terraform should infer dependency on analyze_bluesky_sentiment lambda via ARN reference
  ]
}

#----------------------------------------------------------
# Lambda Function: add_data
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "add_data_lambda_role" {
  name               = "AddDataLambdaRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
      aws_dynamodb_table.data_table.arn,         # Reference table ARN
      aws_dynamodb_table.counter_table_data.arn  # Reference counter table ARN
    ]
  }
}

resource "aws_iam_policy" "add_data_lambda_policy" {
  name   = "AddDataLambdaPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
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
  function_name    = "addData" # Ensure unique name
  filename         = data.archive_file.add_data_zip.output_path
  source_code_hash = data.archive_file.add_data_zip.output_base64sha256
  handler          = "addData.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.add_data_lambda_role.arn

  environment {
    variables = {
      DATA_TABLE_NAME      = var.data_table_name          # Pass table name variable
      DATA_COUNTERS_TABLE_NAME = var.data_counters_table_name # Pass counter table name variable
    }
  }

  tags = {
    Name = "AddDataLambda"
  }

  depends_on = [
      aws_iam_role_policy_attachment.add_data_lambda_attach,
      aws_dynamodb_table.data_table, # Explicit dependencies
      aws_dynamodb_table.counter_table_data
  ]
}

#----------------------------------------------------------
# Lambda Function: get_data_by_query_id
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "get_data_by_query_id_lambda_role" {
  name               = "GetDataByQueryIdLambdaRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
      # Using Query on primary key (DataID, QueryID) or Scan. If querying specifically by QueryID often, a GSI is better.
      # The lambda code dictates the required action (Scan or Query)
      "dynamodb:Scan",
      "dynamodb:Query" # Include Query if the lambda might use it (e.g., on the PK or a GSI)
    ]
    resources = [
      aws_dynamodb_table.data_table.arn, # Grant access to the table
      "${aws_dynamodb_table.data_table.arn}/index/*" # Grant access to all GSIs if Query is used on them
    ]
  }
}

resource "aws_iam_policy" "get_data_by_query_id_lambda_policy" {
  name   = "GetDataByQueryIdLambdaPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
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
  function_name    = "getData" # Ensure unique name
  filename         = data.archive_file.get_data_by_query_id_zip.output_path
  source_code_hash = data.archive_file.get_data_by_query_id_zip.output_base64sha256
  handler          = "getData.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.get_data_by_query_id_lambda_role.arn

  environment {
    variables = {
      DATA_TABLE_NAME = var.data_table_name # Pass table name variable
    }
  }

  tags = {
    Name = "getData"
  }

  depends_on = [
      aws_iam_role_policy_attachment.get_data_by_query_id_lambda_attach,
      aws_dynamodb_table.data_table # Explicit dependency
  ]
}

#----------------------------------------------------------
# Lambda Function: subscribe_to_sns
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "subscribe_to_sns_lambda_role" {
  name               = "SubscribeTosnsLambdaRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
      aws_sns_topic.notifications.arn # Reference the SNS topic ARN
    ]
  }
}

resource "aws_iam_policy" "subscribe_to_sns_lambda_policy" {
  name   = "SubscribeToSNSLambdaPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
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
  function_name    = "subscribeEmailToSNS" # Ensure unique name
  filename         = data.archive_file.subscribe_to_sns_zip.output_path
  source_code_hash = data.archive_file.subscribe_to_sns_zip.output_base64sha256
  handler          = "subscribeToSns.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.subscribe_to_sns_lambda_role.arn
  timeout          = 10

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.notifications.arn # Pass SNS topic ARN
    }
  }

  tags = {
    Name = "SubscribeTosnsLambda"
  }

  depends_on = [
    aws_iam_role_policy_attachment.subscribe_to_sns_lambda_attach,
    aws_sns_topic.notifications # Explicit dependency
  ]
}

#----------------------------------------------------------
# Lambda Function: send_email
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "send_email_lambda_role" {
  name               = "SendEmailLambdaRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
    resources = ["*"] # Restrict if possible to specific identities/ARNs
    # Consider adding condition for source ARN if sending triggered by SNS
    # Condition = { "ArnLike": { "aws:SourceArn": aws_sns_topic.notifications.arn }} # Example if triggered by SNS
  }
  # Optional: Add permissions to fetch sender email from Secrets Manager/Parameter Store
  # statement {
  #   actions = ["secretsmanager:GetSecretValue"]
  #   resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:your-ses-sender-secret-*"]
  # }
}

resource "aws_iam_policy" "send_email_lambda_policy" {
  name   = "SendEmailLambdaPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
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
  function_name    = "sendSNSToSpecificEmail" # Ensure unique name
  filename         = data.archive_file.send_email_zip.output_path
  source_code_hash = data.archive_file.send_email_zip.output_base64sha256
  handler          = "sendEmail.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.send_email_lambda_role.arn
  timeout          = 10

  environment {
    variables = {
      # SENDER_EMAIL removed. Update sendEmail.py to fetch/define it securely.
      # Example: SENDER_EMAIL_SECRET_ARN = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:your-ses-sender-secret-*"
    }
  }

  tags = {
    Name = "SendEmailLambda"
  }

  depends_on = [aws_iam_role_policy_attachment.send_email_lambda_attach]
}


#----------------------------------------------------------
# Lambda Function: AnalyzeBlueskySentiment
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "analyze_bluesky_sentiment_role" {
  name               = "AnalyzeBlueskySentimentRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
      "dynamodb:Scan" # Keep scan if needed, but prefer Query on GSI if possible
      #"dynamodb:Query" # Add if querying GSIs
    ]
    resources = [
      aws_dynamodb_table.query_table.arn,
      aws_dynamodb_table.data_table.arn,
      aws_dynamodb_table.counter_table_data.arn # Check Lambda code uses this exact name
      # Add GSI ARNs if Query action is added:
      # "${aws_dynamodb_table.query_table.arn}/index/*",
      # "${aws_dynamodb_table.data_table.arn}/index/*",
    ]
  }
  statement {
    actions = [
      "comprehend:DetectSentiment"
    ]
    resources = ["*"] # Comprehend actions usually apply account-wide
  }
  statement {
    actions = [
      "scheduler:DeleteSchedule"
    ]
    resources = [
      # Be specific with the schedule name pattern
      "arn:aws:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/${var.scheduler_group_name}/BlueskyAnalysis-Query-*"
    ]
  }
  # *** ADD PERMISSIONS TO FETCH BLUESKY CREDENTIALS ***
  # statement {
  #   actions = ["secretsmanager:GetSecretValue"]
  #   resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:YOUR_BLUESKY_SECRET_NAME-*"]
  # }
}

resource "aws_iam_policy" "analyze_bluesky_sentiment_policy" {
  name        = "AnalyzeBlueskySentimentPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
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
  excludes    = ["*.tf", "*.tfvars", ".terraform", "*.zip", ".git", "terraform.tfstate*", ".terraform.lock.hcl"] # Added common terraform files to exclude
}

# --- Lambda Definition ---
resource "aws_lambda_function" "analyze_bluesky_sentiment" {
  function_name = "my-ts-lambda-function" # Make name unique and descriptive
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
      # Verify the exact env var name the Lambda code expects for the data counter table
      COUNTERS_TABLE_NAME   = var.data_counters_table_name
      SCHEDULER_GROUP_NAME  = var.scheduler_group_name
      # BLUESKY_HANDLE and BLUESKY_APP_PASSWORD removed. Update blueskyLambda.js to fetch securely.
      AWS_NODEJS_CONNECTION_REUSE_ENABLED = "1"
      # Optionally pass Secret ARN or Parameter names if needed by the code:
      # BLUESKY_SECRET_ARN = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:YOUR_BLUESKY_SECRET_NAME-*"
    }
  }

  tags = {
    Name = "AnalyzeBlueskySentimentLambda"
  }

  depends_on = [
    aws_iam_role_policy_attachment.analyze_bluesky_sentiment_attach,
    aws_dynamodb_table.query_table, # Explicit dependencies
    aws_dynamodb_table.data_table,
    aws_dynamodb_table.counter_table_data
  ]
}


#----------------------------------------------------------
# Lambda Function: get_subtopics
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "get_subtopics_lambda_role" {
  name               = "GetSubtopicsLambdaRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
      "dynamodb:Query" # Assuming query by partition key (QueryID) is needed
    ]
    resources = [
      aws_dynamodb_table.subtopics_table.arn, # Reference table ARN
      "${aws_dynamodb_table.subtopics_table.arn}/index/*" # If using GSIs in the future
    ]
  }
}

resource "aws_iam_policy" "get_subtopics_lambda_policy" {
  name   = "GetSubtopicsLambdaPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
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
  function_name    = "getSubtopics" # Make function name consistent and unique
  filename         = data.archive_file.get_subtopics_zip.output_path
  source_code_hash = data.archive_file.get_subtopics_zip.output_base64sha256
  handler          = "getSubtopics.lambda_handler" # Assumes handler is in getSubtopics.py
  runtime          = var.python_runtime
  role             = aws_iam_role.get_subtopics_lambda_role.arn

  environment {
    variables = {
      SUBTOPICS_TABLE_NAME = var.subtopics_table_name # Pass table name variable
    }
  }

  tags = {
    Name = "GetSubtopicsLambda"
  }

  depends_on = [
      aws_iam_role_policy_attachment.get_subtopics_lambda_attach,
      aws_dynamodb_table.subtopics_table # Explicit dependency
   ]
}

#----------------------------------------------------------
# Lambda Function: add_subtopic
#----------------------------------------------------------

# --- IAM Role & Policy ---
resource "aws_iam_role" "add_subtopic_lambda_role" {
  name               = "AddSubtopicLambdaRole-${random_id.unique_suffix.hex}" # Ensure unique name
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
      aws_dynamodb_table.subtopics_table.arn # Reference table ARN
    ]
  }
}

resource "aws_iam_policy" "add_subtopic_lambda_policy" {
  name   = "AddSubtopicLambdaPolicy-${random_id.unique_suffix.hex}" # Ensure unique name
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
  function_name    = "addSubtopic" # Ensure unique name
  filename         = data.archive_file.add_subtopic_zip.output_path
  source_code_hash = data.archive_file.add_subtopic_zip.output_base64sha256
  handler          = "addSubtopic.lambda_handler"
  runtime          = var.python_runtime
  role             = aws_iam_role.add_subtopic_lambda_role.arn

  environment {
    variables = {
      # Verify the exact env var name the Lambda code expects
      DYNAMODB_TABLE_NAME = var.subtopics_table_name
    }
  }

  tags = {
    Name = "AddSubtopicLambda"
  }

  depends_on = [
      aws_iam_role_policy_attachment.add_subtopic_lambda_attach,
      aws_dynamodb_table.subtopics_table # Explicit dependency
  ]
}


#----------------------------------------------------------
# API Gateway Resources
#----------------------------------------------------------
# 1. Create the REST API
resource "aws_api_gateway_rest_api" "my_api" {
  name        = "PROJECT-API" # Make name unique
  description = "API Gateway triggering Lambdas"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
  # Enable CloudWatch Logs Role
   binary_media_types = ["*/*"] # Needed for certain integrations / proxy behaviour sometimes
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

# 3. Define Methods and Integrations (Including CORS OPTIONS methods)
# --- /data/retrieve (GET -> get_data_by_query_id) ---
resource "aws_api_gateway_method" "data_retrieve_get" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.data_retrieve.id
  http_method   = "GET"
  authorization = "NONE" # Consider adding Auth later (e.g., COGNITO_USER_POOLS)
}
resource "aws_api_gateway_integration" "data_retrieve_get_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.data_retrieve.id
  http_method           = aws_api_gateway_method.data_retrieve_get.http_method
  integration_http_method = "POST" # Must be POST for Lambda Proxy integration
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
    response_parameters = { "method.response.header.Access-Control-Allow-Origin" = "'*'" } # Consider restricting origin
    # No response_templates needed for AWS_PROXY
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
  response_models = { "application/json" = "Empty" } # Reference built-in Empty model
}
resource "aws_api_gateway_integration_response" "data_retrieve_options_mock_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.data_retrieve.id
  http_method = aws_api_gateway_method.data_retrieve_options.http_method
  status_code = aws_api_gateway_method_response.data_retrieve_options_200.status_code
  response_parameters = {
    # Adjust allowed headers/methods as needed for your frontend
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'", # Added X-Amz-User-Agent commonly needed
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'", # Only GET is defined for this resource
    "method.response.header.Access-Control-Allow-Origin"  = "'*'" # Consider restricting origin
  }
  response_templates = { "application/json" = "" } # Empty body for OPTIONS
  depends_on = [aws_api_gateway_method.data_retrieve_options]
}

# --- /data/send (POST -> add_data) ---
resource "aws_api_gateway_method" "data_send_post" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.data_send.id
  http_method   = "POST"
  authorization = "NONE" # Consider Auth
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
    # No response_templates needed for AWS_PROXY
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
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
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
  authorization = "NONE" # Consider Auth
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
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
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
  authorization = "NONE" # Consider Auth
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
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
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
  authorization = "NONE" # Consider Auth
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
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
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
  authorization = "NONE" # Consider Auth
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
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
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
  authorization = "NONE" # Consider Auth
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
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
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
  authorization = "NONE" # Consider Auth
}
resource "aws_api_gateway_integration" "subtopics_send_post_lambda" {
  rest_api_id           = aws_api_gateway_rest_api.my_api.id
  resource_id           = aws_api_gateway_resource.subtopics_send.id
  http_method           = aws_api_gateway_method.subtopics_send_post.http_method
  integration_http_method = "POST"
  type                  = "AWS_PROXY"
  uri                   = aws_lambda_function.add_subtopic.invoke_arn
}
resource "aws_api_gateway_method_response" "subtopics_send_post_201" { # Using 201 Created for successful POST
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.subtopics_send.id
  http_method = aws_api_gateway_method.subtopics_send_post.http_method
  status_code = "201" # Use 201 for resource creation
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
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = { "application/json" = "" }
  depends_on         = [aws_api_gateway_method.subtopics_send_options]
}

#----------------------------------------------------------
# Lambda Permissions for API Gateway Invocation
#----------------------------------------------------------
# Note: Source ARN uses a wildcard for the stage initially.
# You might want to replace '*' with '${aws_api_gateway_stage.v1.name}' once the stage is defined.

resource "aws_lambda_permission" "apigw_invoke_get_data_by_query_id" {
  statement_id  = "AllowAPIGatewayInvokeGetDataByQueryId"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_data_by_query_id.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/${aws_api_gateway_method.data_retrieve_get.http_method}${aws_api_gateway_resource.data_retrieve.path}"
}
resource "aws_lambda_permission" "apigw_invoke_add_data" {
  statement_id  = "AllowAPIGatewayInvokeAddData"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_data.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/${aws_api_gateway_method.data_send_post.http_method}${aws_api_gateway_resource.data_send.path}"
}
resource "aws_lambda_permission" "apigw_invoke_send_email" {
  statement_id  = "AllowAPIGatewayInvokeSendEmail"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.send_email.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/${aws_api_gateway_method.notifications_send_post.http_method}${aws_api_gateway_resource.notifications_send.path}"
}
resource "aws_lambda_permission" "apigw_invoke_subscribe_to_sns" {
  statement_id  = "AllowAPIGatewayInvokeSubscribeToSns"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subscribe_to_sns.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/${aws_api_gateway_method.notifications_subscribe_post.http_method}${aws_api_gateway_resource.notifications_subscribe.path}"
}
resource "aws_lambda_permission" "apigw_invoke_get_queries_by_email" {
  statement_id  = "AllowAPIGatewayInvokeGetQueriesByEmail"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_queries_by_email.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/${aws_api_gateway_method.queries_retrieve_get.http_method}${aws_api_gateway_resource.queries_retrieve.path}"
}
resource "aws_lambda_permission" "apigw_invoke_add_query" {
  statement_id  = "AllowAPIGatewayInvokeAddQuery"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/${aws_api_gateway_method.queries_send_post.http_method}${aws_api_gateway_resource.queries_send.path}"
}
resource "aws_lambda_permission" "apigw_invoke_get_subtopics" {
  statement_id  = "AllowAPIGatewayInvokeGetSubtopics"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_subtopics.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/${aws_api_gateway_method.subtopics_retrieve_get.http_method}${aws_api_gateway_resource.subtopics_retrieve.path}"
}
resource "aws_lambda_permission" "apigw_invoke_add_subtopic" {
  statement_id  = "AllowAPIGatewayInvokeAddSubtopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_subtopic.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/${aws_api_gateway_method.subtopics_send_post.http_method}${aws_api_gateway_resource.subtopics_send.path}"
}


#----------------------------------------------------------
# API Gateway Deployment & Stage
#----------------------------------------------------------
resource "aws_api_gateway_deployment" "my_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id

  # Trigger redeployment when relevant API Gateway configurations change
  triggers = {
    redeployment = sha1(jsonencode(flatten([
      # Include resources, methods, integrations, responses for all endpoints
      # Data Retrieve
      aws_api_gateway_resource.data_retrieve.id,
      aws_api_gateway_method.data_retrieve_get.id,
      aws_api_gateway_integration.data_retrieve_get_lambda.id,
      aws_api_gateway_method_response.data_retrieve_get_200.id,
      aws_api_gateway_integration_response.data_retrieve_get_lambda_resp.id,
      aws_api_gateway_method.data_retrieve_options.id,
      aws_api_gateway_integration.data_retrieve_options_mock.id,
      aws_api_gateway_method_response.data_retrieve_options_200.id,
      aws_api_gateway_integration_response.data_retrieve_options_mock_resp.id,
      # Data Send
      aws_api_gateway_resource.data_send.id,
      aws_api_gateway_method.data_send_post.id,
      aws_api_gateway_integration.data_send_post_lambda.id,
      aws_api_gateway_method_response.data_send_post_200.id,
      aws_api_gateway_integration_response.data_send_post_lambda_resp.id,
      aws_api_gateway_method.data_send_options.id,
      aws_api_gateway_integration.data_send_options_mock.id,
      aws_api_gateway_method_response.data_send_options_200.id,
      aws_api_gateway_integration_response.data_send_options_mock_resp.id,
      # Notifications Send
      aws_api_gateway_resource.notifications_send.id,
      aws_api_gateway_method.notifications_send_post.id,
      aws_api_gateway_integration.notifications_send_post_lambda.id,
      aws_api_gateway_method_response.notifications_send_post_200.id,
      aws_api_gateway_integration_response.notifications_send_post_lambda_resp.id,
      aws_api_gateway_method.notifications_send_options.id,
      aws_api_gateway_integration.notifications_send_options_mock.id,
      aws_api_gateway_method_response.notifications_send_options_200.id,
      aws_api_gateway_integration_response.notifications_send_options_mock_resp.id,
      # Notifications Subscribe
      aws_api_gateway_resource.notifications_subscribe.id,
      aws_api_gateway_method.notifications_subscribe_post.id,
      aws_api_gateway_integration.notifications_subscribe_post_lambda.id,
      aws_api_gateway_method_response.notifications_subscribe_post_200.id,
      aws_api_gateway_integration_response.notifications_subscribe_post_lambda_resp.id,
      aws_api_gateway_method.notifications_subscribe_options.id,
      aws_api_gateway_integration.notifications_subscribe_options_mock.id,
      aws_api_gateway_method_response.notifications_subscribe_options_200.id,
      aws_api_gateway_integration_response.notifications_subscribe_options_mock_resp.id,
      # Queries Retrieve
      aws_api_gateway_resource.queries_retrieve.id,
      aws_api_gateway_method.queries_retrieve_get.id,
      aws_api_gateway_integration.queries_retrieve_get_lambda.id,
      aws_api_gateway_method_response.queries_retrieve_get_200.id,
      aws_api_gateway_integration_response.queries_retrieve_get_lambda_resp.id,
      aws_api_gateway_method.queries_retrieve_options.id,
      aws_api_gateway_integration.queries_retrieve_options_mock.id,
      aws_api_gateway_method_response.queries_retrieve_options_200.id,
      aws_api_gateway_integration_response.queries_retrieve_options_mock_resp.id,
      # Queries Send
      aws_api_gateway_resource.queries_send.id,
      aws_api_gateway_method.queries_send_post.id,
      aws_api_gateway_integration.queries_send_post_lambda.id,
      aws_api_gateway_method_response.queries_send_post_200.id,
      aws_api_gateway_integration_response.queries_send_post_lambda_resp.id,
      aws_api_gateway_method.queries_send_options.id,
      aws_api_gateway_integration.queries_send_options_mock.id,
      aws_api_gateway_method_response.queries_send_options_200.id,
      aws_api_gateway_integration_response.queries_send_options_mock_resp.id,
      # Subtopics Retrieve
      aws_api_gateway_resource.subtopics_retrieve.id,
      aws_api_gateway_method.subtopics_retrieve_get.id,
      aws_api_gateway_integration.subtopics_retrieve_get_lambda.id,
      aws_api_gateway_method_response.subtopics_retrieve_get_200.id,
      aws_api_gateway_integration_response.subtopics_retrieve_get_lambda_resp.id,
      aws_api_gateway_method.subtopics_retrieve_options.id,
      aws_api_gateway_integration.subtopics_retrieve_options_mock.id,
      aws_api_gateway_method_response.subtopics_retrieve_options_200.id,
      aws_api_gateway_integration_response.subtopics_retrieve_options_mock_resp.id,
      # Subtopics Send
      aws_api_gateway_resource.subtopics_send.id,
      aws_api_gateway_method.subtopics_send_post.id,
      aws_api_gateway_integration.subtopics_send_post_lambda.id,
      aws_api_gateway_method_response.subtopics_send_post_201.id, # Use the correct status code response
      aws_api_gateway_integration_response.subtopics_send_post_lambda_resp.id,
      aws_api_gateway_method.subtopics_send_options.id,
      aws_api_gateway_integration.subtopics_send_options_mock.id,
      aws_api_gateway_method_response.subtopics_send_options_200.id,
      aws_api_gateway_integration_response.subtopics_send_options_mock_resp.id,
      # Also trigger on Lambda changes if their ARNs change (unlikely with stable names)
      aws_lambda_function.get_data_by_query_id.arn,
      aws_lambda_function.add_data.arn,
      aws_lambda_function.send_email.arn,
      aws_lambda_function.subscribe_to_sns.arn,
      aws_lambda_function.get_queries_by_email.arn,
      aws_lambda_function.add_query.arn,
      aws_lambda_function.get_subtopics.arn,
      aws_lambda_function.add_subtopic.arn
    ])))
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
    # Example detailed JSON format
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

# IAM Role for API Gateway to push logs to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-logging-role-${var.aws_region}-${random_id.unique_suffix.hex}" # Make name unique
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
   # Use the AWS managed policy for this purpose
   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}


# ----------------------------------------------------------
# Cognito Resources (Auth)
# ----------------------------------------------------------
resource "aws_cognito_user_pool" "team_8_user_pool" {
  name = "team_8_user_pool" # Ensure unique name

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
  mfa_configuration        = "OFF"

  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  # Optionally configure domain prefix here if needed for Hosted UI
  # domain = var.cognito_domain_prefix
}

resource "aws_cognito_user_pool_client" "team_8_user_pool_client" {
  name         = "team_8_user_pool_client" # Unique name
  user_pool_id = aws_cognito_user_pool.team_8_user_pool.id
  generate_secret = false
}

resource "aws_cognito_identity_pool" "team_8_identity_pool" {
  identity_pool_name               = "team_8_identity_pool" # Ensure unique name
  allow_unauthenticated_identities = true # Set to false if you don't need guest access to AWS resources

  cognito_identity_providers {
    client_id = aws_cognito_user_pool_client.team_8_user_pool_client.id
    provider_name = "cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.team_8_user_pool.id}"
  }
}
#-----------------------------------
#IAM Policy for S3 Access (For Authenticated Users Only)
#-----------------------------------
resource "aws_iam_policy" "s3_access_policy" {
  name        = "s3-access-policy"
  description = "IAM policy for authenticated users to access S3"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::amplify-notes-drive-${random_id.unique_suffix.hex}/*"
      }
    ]
  })
}

#-----------------------------------
#IAM Role for Authenticated Users (Full S3 Access)
#-----------------------------------
resource "aws_iam_role" "authenticated_role" {
  name = "authenticated-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.team_8_identity_pool.id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "authenticated_role_policy" {
  role       = aws_iam_role.authenticated_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

#-----------------------------------
#IAM Role Attachment to Identity Pool (Authenticated)
#-----------------------------------
resource "aws_cognito_identity_pool_roles_attachment" "authenticated_role_attachment" {
  identity_pool_id = aws_cognito_identity_pool.team_8_identity_pool.id

  roles = {
    authenticated = aws_iam_role.authenticated_role.arn
  }
}

resource "aws_s3_bucket" "team_8_storage" {
  bucket = "amplify-notes-drive-${random_id.unique_suffix.hex}"
}
#----------------------------------
#Updated S3 Object for Storage Policy
#-------------------------------------
resource "aws_s3_object" "team_8_storage_policy" {
  bucket = aws_s3_bucket.team_8_storage.bucket
  key    = "storage-policy.json"
  content = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "s3:GetObject",
          "Resource": "arn:aws:s3:::amplify-notes-drive-${random_id.unique_suffix.hex}/media/",
          "Principal": "",
          "Condition": {
            "StringEquals": {
              "aws:userid": "*"
            }
          }
        }
      ]
    }
  EOT
}

#----------------------------------------------------------
# Amplify App (Frontend + Backend Integration)
#----------------------------------------------------------
resource "aws_amplify_app" "team_8" {
  name        = "team_8" # Make name more unique and descriptive
  repository  = "https://github.com/514-2245-2-team8/514-2245-2-team8" 
  access_token = var.github_token # Provided via variable

  # Define build settings for your frontend framework (Vite example)
  build_spec = <<-EOT
    version: 1.0
    frontend:
      phases:
        preBuild:
          commands:
            - cd all_amplify # Adjust path to your amplify project root within the repo
            - npm install
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: all_amplify/dist # Adjust path to your build output dir
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  # Environment variables passed to the Amplify build process
  environment_variables = {
    # === Amplify Auth Config ===
    VITE_REGION              = var.aws_region # CRUCIAL: Use the same region as backend
    VITE_USER_POOL_ID        = aws_cognito_user_pool.team_8_user_pool.id
    VITE_USER_POOL_CLIENT_ID = aws_cognito_user_pool_client.team_8_user_pool_client.id
    VITE_IDENTITY_POOL_ID    = aws_cognito_identity_pool.team_8_identity_pool.id
    # === Amplify Storage Config ===
    VITE_BUCKET_NAME         = aws_s3_bucket.team_8_storage.bucket
    # === Your Custom API Config ===
    # Pass the API Gateway Invoke URL for the 'v1' stage
    VITE_API_ENDPOINT        = aws_api_gateway_stage.v1.invoke_url
  }
}

# Amplify doesn't typically need a separate backend environment resource when defined this way
# The app itself connects to the resources via environment variables.

# Amplify Branch Deployment (Connects a Git branch to the Amplify App)
resource "aws_amplify_branch" "main_branch" {
  app_id      = aws_amplify_app.team_8.id
  branch_name = "main" # MAKE SURE this branch exists in your GitHub repo and contains the code to be deployed
}
