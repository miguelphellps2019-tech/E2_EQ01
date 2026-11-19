terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project   = var.project_name
        Team      = var.team_code
        ManagedBy = "Terraform"
        Course    = "E2-Ruta-1"
      },
      var.extra_tags
    )
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "random_id" "bucket_suffix" {
  byte_length = 3
}

locals {
  resource_prefix = substr(replace(lower(var.project_name), "_", "-"), 0, 36)
  bucket_name     = "${local.resource_prefix}-${data.aws_caller_identity.current.account_id}-${random_id.bucket_suffix.hex}"
  lambda_name    = "${local.resource_prefix}-ingest"
  glue_job_name  = "${local.resource_prefix}-raw-to-curated"
  database_name  = replace("${local.resource_prefix}_analytics", "-", "_")
  workgroup_name = "${local.resource_prefix}-wg"
  ddb_table_name = "${local.resource_prefix}-operational"
}
