provider "aws" {
  region = "us-east-1"
}

variable "cognito_domain_prefix" {
  description = "Domain prefix for Cognito Hosted UI"
  type        = string
  default     = "team8-auth-team888"  # Pick a globally unique name
}

resource "random_id" "unique_suffix" {
  byte_length = 8
}

# -----------------------------------
# Cognito User Pool (Auth)
# -----------------------------------
resource "aws_cognito_user_pool" "team_8_user_pool" {
  name = "team_8_user_pool"

  // Set up password policy
  password_policy {
    minimum_length      = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

    auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  // Optional: Adjust MFA and verification settings as needed
  mfa_configuration = "OFF"

// Email verification settings
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"

  // Verification message template (email confirmation)
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

}

# Cognito App Client with OAuth (for Amplify integration)
resource "aws_cognito_user_pool_client" "team_8_user_pool_client" {
  name         = "team_8_user_pool_client"
  user_pool_id = aws_cognito_user_pool.team_8_user_pool.id
  generate_secret = false
}

# -----------------------------------
# Cognito Identity Pool
# -----------------------------------
resource "aws_cognito_identity_pool" "team_8_identity_pool" {
  identity_pool_name               = "team_8_identity_pool"
  allow_unauthenticated_identities = true

  cognito_identity_providers {
    client_id     = aws_cognito_user_pool_client.team_8_user_pool_client.id
    provider_name = "cognito-idp.us-east-1.amazonaws.com/${aws_cognito_user_pool.team_8_user_pool.id}"
  }
}
 
# -----------------------------------
# IAM Policy for S3 Access (For Authenticated Users Only)
# -----------------------------------
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

# -----------------------------------
# IAM Role for Authenticated Users (Full S3 Access)
# -----------------------------------
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

# -----------------------------------
# IAM Role Attachment to Identity Pool (Authenticated)
# -----------------------------------
resource "aws_cognito_identity_pool_roles_attachment" "authenticated_role_attachment" {
  identity_pool_id = aws_cognito_identity_pool.team_8_identity_pool.id

  roles = {
    authenticated = aws_iam_role.authenticated_role.arn
  }
}

#----------------------------------
# S3 Bucket (Storage)
# -----------------------------------
resource "aws_s3_bucket" "team_8_storage" {
  bucket = "amplify-notes-drive-${random_id.unique_suffix.hex}"
}

# Updated S3 Object for Storage Policy
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
          "Resource": "arn:aws:s3:::amplify-notes-drive-${random_id.unique_suffix.hex}/media/*",
          "Principal": "*",
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

# -----------------------------------
# Amplify App (Frontend + Backend Integration)
# -----------------------------------
resource "aws_amplify_app" "team_8" {
  name        = "team_8"
  repository  = "https://github.com/514-2245-2-team8/514-2245-2-team8"
  access_token = var.github_token

  build_spec = <<-EOT
    version: 1.0
    frontend:
      phases:
        preBuild:
          commands:
            - cd all_amplify && npm install
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: all_amplify/dist
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  environment_variables = {
    VITE_REGION              = "us-east-1"
    VITE_USER_POOL_ID        = aws_cognito_user_pool.team_8_user_pool.id
    VITE_USER_POOL_CLIENT_ID = aws_cognito_user_pool_client.team_8_user_pool_client.id
    VITE_IDENTITY_POOL_ID    = aws_cognito_identity_pool.team_8_identity_pool.id
    VITE_BUCKET_NAME         = aws_s3_bucket.team_8_storage.bucket
    # Removed Lambda ARN reference if not using Lambda
  }
}

# Amplify Backend Environment to incorporate Auth, Data, and Storage
resource "aws_amplify_backend_environment" "team_8_backend" {
  app_id          = aws_amplify_app.team_8.id
  environment_name = "dev"
}

# Amplify Branch Deployment
resource "aws_amplify_branch" "terraform" {
  app_id      = aws_amplify_app.team_8.id
  branch_name = "terraform"
}

# -----------------------------------
# Output Amplify URL for Later Use
# -----------------------------------
output "amplify_app_domain" {
  value = aws_amplify_app.team_8.default_domain
}


