data "aws_iam_policy_document" "account_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "data_engineer" {
  name               = "${local.resource_prefix}-data-engineer"
  description        = "Writes raw/curated data and operates Lambda and Glue; cannot read the API key or change access policies."
  assume_role_policy = data.aws_iam_policy_document.account_assume_role.json
}

data "aws_iam_policy_document" "data_engineer" {
  statement {
    sid       = "ListDataPrefixes"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data_lake.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "raw/*",
        "curated/*",
        "glue-assets/*",
        "glue-temp/*"
      ]
    }
  }

  statement {
    sid = "ManagePipelineObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      "${aws_s3_bucket.data_lake.arn}/raw/*",
      "${aws_s3_bucket.data_lake.arn}/curated/*",
      "${aws_s3_bucket.data_lake.arn}/glue-assets/*",
      "${aws_s3_bucket.data_lake.arn}/glue-temp/*"
    ]
  }

  statement {
    sid = "OperatePipeline"
    actions = [
      "lambda:InvokeFunction",
      "lambda:GetFunction",
      "glue:StartJobRun",
      "glue:GetJob",
      "glue:GetJobRun",
      "glue:GetJobRuns"
    ]
    resources = [
      aws_lambda_function.ingest.arn,
      aws_glue_job.raw_to_curated.arn
    ]
  }

  statement {
    sid = "InspectOperationalData"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.operational.arn,
      "${aws_dynamodb_table.operational.arn}/index/*"
    ]
  }
}

resource "aws_iam_role_policy" "data_engineer" {
  name   = "pipeline-operations"
  role   = aws_iam_role.data_engineer.id
  policy = data.aws_iam_policy_document.data_engineer.json
}

resource "aws_iam_role" "analyst" {
  name               = "${local.resource_prefix}-analyst"
  description        = "Reads curated Parquet through Athena; cannot read raw data or write lake data."
  assume_role_policy = data.aws_iam_policy_document.account_assume_role.json
}

data "aws_iam_policy_document" "analyst" {
  statement {
    sid = "RunAthenaQueries"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
      "athena:GetWorkGroup"
    ]
    resources = [aws_athena_workgroup.analytics.arn]
  }

  statement {
    sid = "ListAthenaMetadata"
    actions = [
      "athena:ListQueryExecutions",
      "athena:ListNamedQueries",
      "athena:GetNamedQuery",
      "athena:BatchGetNamedQuery"
    ]
    resources = ["*"]
  }

  statement {
    sid = "ReadGlueCatalog"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
      aws_glue_catalog_database.analytics.arn,
      "arn:${data.aws_partition.current.partition}:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.analytics.name}/*"
    ]
  }

  statement {
    sid = "InspectAthenaResultsBucket"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [aws_s3_bucket.data_lake.arn]
  }

  statement {
    sid       = "ListCuratedAndResults"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data_lake.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "curated/*",
        "athena-results/*"
      ]
    }
  }

  statement {
    sid       = "ReadCurated"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data_lake.arn}/curated/*"]
  }

  statement {
    sid = "UseAthenaResults"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["${aws_s3_bucket.data_lake.arn}/athena-results/*"]
  }
}

resource "aws_iam_role_policy" "analyst" {
  name   = "curated-athena-read-only"
  role   = aws_iam_role.analyst.id
  policy = data.aws_iam_policy_document.analyst.json
}

resource "aws_iam_role" "data_owner" {
  name               = "${local.resource_prefix}-data-owner"
  description        = "Reviews governance, retention, and access configuration; does not execute processing jobs."
  assume_role_policy = data.aws_iam_policy_document.account_assume_role.json
}

data "aws_iam_policy_document" "data_owner" {
  statement {
    sid = "ReviewStorageGovernance"
    actions = [
      "s3:GetBucketEncryption",
      "s3:GetBucketLifecycleConfiguration",
      "s3:GetBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketVersioning",
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.data_lake.arn]
  }

  statement {
    sid = "ReviewCatalog"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartitions"
    ]
    resources = ["*"]
  }

  statement {
    sid = "ReviewRoles"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies"
    ]
    resources = [
      aws_iam_role.data_engineer.arn,
      aws_iam_role.analyst.arn,
      aws_iam_role.data_owner.arn,
      aws_iam_role.auditor.arn
    ]
  }
}

resource "aws_iam_role_policy" "data_owner" {
  name   = "governance-read-only"
  role   = aws_iam_role.data_owner.id
  policy = data.aws_iam_policy_document.data_owner.json
}

resource "aws_iam_role" "auditor" {
  name               = "${local.resource_prefix}-security-auditor"
  description        = "Read-only inspection of CloudTrail event history, CloudWatch logs, IAM, and resource configuration."
  assume_role_policy = data.aws_iam_policy_document.account_assume_role.json
}

data "aws_iam_policy_document" "auditor" {
  statement {
    sid = "AuditEventsAndLogs"
    actions = [
      "cloudtrail:LookupEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents"
    ]
    resources = ["*"]
  }

  statement {
    sid = "AuditIam"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListRoles",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies"
    ]
    resources = ["*"]
  }

  statement {
    sid = "AuditResourceConfiguration"
    actions = [
      "s3:GetBucketEncryption",
      "s3:GetBucketLifecycleConfiguration",
      "s3:GetBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketVersioning",
      "dynamodb:DescribeTable",
      "glue:GetJob",
      "glue:GetJobRuns",
      "athena:GetWorkGroup",
      "scheduler:GetSchedule"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "auditor" {
  name   = "security-audit-read-only"
  role   = aws_iam_role.auditor.id
  policy = data.aws_iam_policy_document.auditor.json
}
