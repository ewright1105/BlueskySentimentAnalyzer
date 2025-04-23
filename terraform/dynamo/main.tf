provider "aws" {
  region = "us-east-1"
}

locals {
  aws_key = "TEAM8_KEY" # Ensure this key pair exists in your AWS account/region
}

resource "aws_iam_instance_profile" "dynamodb_instance_profile" {
  name = "dynamodb_instance_profile"
  role = aws_iam_role.dynamodb_access_role.name
}

resource "aws_instance" "my_server" {
  ami           = data.aws_ami.amazonlinux.id
  instance_type = var.instance_type
  key_name      = local.aws_key
  # Assign the instance profile to allow EC2 to assume the role
  iam_instance_profile = aws_iam_instance_profile.dynamodb_instance_profile.name

  tags = {
    Name = "my ec2"
  }

  # Added dependency to ensure role/profile exist before instance creation
  depends_on = [aws_iam_instance_profile.dynamodb_instance_profile]
}

resource "aws_iam_role" "dynamodb_access_role" {
  name = "DynamoDBAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "dynamodb_access_policy" {
  name        = "DynamoDBAccessPolicy"
  description = "Allows EC2 instance to access required DynamoDB tables"

  # Use resource references for ARNs instead of hardcoding
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          # Added DescribeTable for potential SDK/CLI use within the instance
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.query_table.arn,
          aws_dynamodb_table.data_table.arn,
          aws_dynamodb_table.subtopics_table.arn, # Added new Subtopics table ARN
          aws_dynamodb_table.counter_table_query.arn,
          aws_dynamodb_table.counter_table_data.arn
          # Add index ARNs if fine-grained access control is needed (optional)
          # "${aws_dynamodb_table.query_table.arn}/index/*",
          # "${aws_dynamodb_table.data_table.arn}/index/*",
        ]
      }
    ]
  })

  # Ensure tables exist before creating the policy that references them
  depends_on = [
    aws_dynamodb_table.query_table,
    aws_dynamodb_table.data_table,
    aws_dynamodb_table.subtopics_table, # Added dependency on new table
    aws_dynamodb_table.counter_table_query,
    aws_dynamodb_table.counter_table_data
  ]
}

resource "aws_iam_role_policy_attachment" "dynamodb_role_attachment" {
  role       = aws_iam_role.dynamodb_access_role.name
  policy_arn = aws_iam_policy.dynamodb_access_policy.arn
}

resource "aws_dynamodb_table" "counter_table_query" {
  name           = "CountersQuery"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "CounterName"

  attribute {
    name = "CounterName"
    type = "S"
  }

  tags = {
    Name        = "counter_table_query"
    Environment = "production"
  }
}

resource "aws_dynamodb_table" "counter_table_data" {
  name           = "CountersData"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "CounterName"

  attribute {
    name = "CounterName"
    type = "S"
  }

  tags = {
    Name        = "counter_table_data" # Corrected tag name from original
    Environment = "production"
  }
}

resource "aws_dynamodb_table" "query_table" {
  name           = "Queries"
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
    Name        = "query_table"
    Environment = "production"
  }
}

# --- NEW Subtopics Table ---
resource "aws_dynamodb_table" "subtopics_table" {
  name           = "Subtopics"
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
    Name        = "subtopics_table"
    Environment = "production"
  }
}


# --- MODIFIED Data Table ---
resource "aws_dynamodb_table" "data_table" {
  name         = "Data"
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
  # Note: Removed DataID attribute as it's replaced by the new composite primary key

  global_secondary_index {
    name            = "TopicID"
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
    Name        = "data_table"
    Environment = "production"
  }
}
