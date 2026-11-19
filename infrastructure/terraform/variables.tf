variable "aws_region" {
  description = "AWS Region for every resource. Keep all services in one Region to avoid cross-Region transfer charges."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Lowercase project slug used in AWS resource names."
  type        = string
  default     = "e2-eq01-api-sports"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name)) && length(var.project_name) <= 36
    error_message = "project_name must start with a lowercase letter, use only lowercase letters/numbers/hyphens, and be at most 36 characters."
  }
}

variable "team_code" {
  description = "Team identifier required by the assignment."
  type        = string
  default     = "EQ01"

  validation {
    condition     = can(regex("^EQ[0-9A-Za-z]{2,8}$", var.team_code))
    error_message = "team_code must start with EQ and contain 2 to 8 additional alphanumeric characters."
  }
}

variable "league_id" {
  description = "API-Football league ID. 39 is the English Premier League."
  type        = number
  default     = 39

  validation {
    condition     = var.league_id > 0 && floor(var.league_id) == var.league_id
    error_message = "league_id must be a positive integer."
  }
}

variable "season" {
  description = "API-Football season. 2024 is used because it is available to the 2026 free plan; paid plans can use current seasons."
  type        = number
  default     = 2024

  validation {
    condition     = var.season >= 2010 && var.season <= 2034 && floor(var.season) == var.season
    error_message = "season must be an integer between 2010 and 2034."
  }
}

variable "schedule_expression" {
  description = "EventBridge Scheduler expression. Default: every day at 03:10 UTC."
  type        = string
  default     = "cron(10 3 * * ? *)"
}

variable "enable_schedule" {
  description = "Enable or disable the daily ingestion schedule without deleting it."
  type        = bool
  default     = true
}

variable "api_key_parameter_name" {
  description = "Existing SSM Parameter Store SecureString name containing the API-Sports key. The value is intentionally excluded from Terraform state."
  type        = string
  default     = "/e2/eq01/api-sports/key"

  validation {
    condition     = startswith(var.api_key_parameter_name, "/") && length(var.api_key_parameter_name) > 1
    error_message = "api_key_parameter_name must be an absolute SSM path beginning with /."
  }
}

variable "api_key" {
  description = "API-Sports key passed as an encrypted Lambda environment variable. Use when an SCP blocks SSM. Provide via TF_VAR_api_key, never in a file. Empty = read from SSM."
  type        = string
  default     = ""
  sensitive   = true
}

variable "athena_bytes_scanned_cutoff" {
  description = "Maximum bytes a single Athena query may scan in this workgroup. Minimum supported value is 10 MiB."
  type        = number
  default     = 104857600

  validation {
    condition     = var.athena_bytes_scanned_cutoff >= 10485760
    error_message = "Athena's per-query cutoff must be at least 10 MiB (10485760 bytes)."
  }
}

variable "force_destroy_bucket" {
  description = "Lab convenience. When true, terraform destroy also removes objects and versions from the S3 bucket."
  type        = bool
  default     = true
}

variable "extra_tags" {
  description = "Additional tags applied to supported resources."
  type        = map(string)
  default     = {}
}
