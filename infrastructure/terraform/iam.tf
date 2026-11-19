data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_ingest" {
  name               = "${local.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_ingest" {
  statement {
    sid = "WriteRawObjects"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload"
    ]
    resources = ["${aws_s3_bucket.data_lake.arn}/raw/*"]
  }

  statement {
    sid = "WriteOperationalTable"
    actions = [
      "dynamodb:BatchWriteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem"
    ]
    resources = [
      aws_dynamodb_table.operational.arn,
      "${aws_dynamodb_table.operational.arn}/index/*"
    ]
  }

  statement {
    sid       = "ReadApiKeyOnly"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.api_key_parameter_name}"]
  }

  statement {
    sid       = "StartGlueJob"
    actions   = ["glue:StartJobRun"]
    resources = ["arn:${data.aws_partition.current.partition}:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:job/${local.glue_job_name}"]
  }

  statement {
    sid = "WriteLambdaLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.lambda_name}:*"]
  }
}

resource "aws_iam_role_policy" "lambda_ingest" {
  name   = "${local.lambda_name}-policy"
  role   = aws_iam_role.lambda_ingest.id
  policy = data.aws_iam_policy_document.lambda_ingest.json
}

data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "${local.glue_job_name}-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "glue_data_lake" {
  statement {
    sid = "ListDataLake"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [aws_s3_bucket.data_lake.arn]
  }

  statement {
    sid = "ReadRawAndScript"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]
    resources = [
      "${aws_s3_bucket.data_lake.arn}/raw/*",
      "${aws_s3_bucket.data_lake.arn}/glue-assets/*",
      "${aws_s3_bucket.data_lake.arn}/curated/*",
      "${aws_s3_bucket.data_lake.arn}/glue-temp/*"
    ]
  }

  statement {
    sid = "WriteCuratedAndTemp"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = [
      "${aws_s3_bucket.data_lake.arn}/curated/*",
      "${aws_s3_bucket.data_lake.arn}/glue-temp/*"
    ]
  }
}

resource "aws_iam_role_policy" "glue_data_lake" {
  name   = "${local.glue_job_name}-s3-policy"
  role   = aws_iam_role.glue.id
  policy = data.aws_iam_policy_document.glue_data_lake.json
}

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.resource_prefix}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "InvokeIngestionLambda"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.ingest.arn]
  }

  statement {
    sid       = "SendFailedInvocationToDlq"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.scheduler_dlq.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${local.resource_prefix}-scheduler-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}
