variable "github_token" {
  description = "GitHub personal access token for Amplify to connect to the repo"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "amplify_repo_url" {
  description = "GitHub repository URL for the Amplify app"
  type        = string
  default     = "https://github.com/514-2245-2-team8/514-2245-2-team8"
}

variable "amplify_branch_name" {
  description = "The branch of the repo to deploy"
  type        = string
  default     = "main"
}
