data "archive_file" "lambda_ingest" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/lambda_ingest"
  output_path = "${path.module}/build/lambda_ingest.zip"
}

resource "aws_cloudwatch_log_group" "lambda_ingest" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "ingest" {
  function_name = local.lambda_name
  description   = "Daily API-Sports ingestion into S3 raw, DynamoDB, and AWS Glue"
  role          = aws_iam_role.lambda_ingest.arn
  handler       = "app.lambda_handler"
  runtime       = "python3.12"
  architectures = ["arm64"]

  filename         = data.archive_file.lambda_ingest.output_path
  source_code_hash = data.archive_file.lambda_ingest.output_base64sha256

  memory_size                    = 512
  timeout                        = 120
  reserved_concurrent_executions = 1

  environment {
    variables = {
      API_KEY               = var.api_key
      API_BASE_URL          = "https://v3.football.api-sports.io"
      API_KEY_PARAMETER_NAME = var.api_key_parameter_name
      BUCKET_NAME           = aws_s3_bucket.data_lake.id
      RAW_PREFIX            = "raw"
      DDB_TABLE_NAME        = aws_dynamodb_table.operational.name
      GLUE_JOB_NAME         = local.glue_job_name
      LEAGUE_ID             = tostring(var.league_id)
      SEASON                = tostring(var.season)
      ENDPOINTS             = "fixtures,teams,standings"
      FIXTURE_TTL_DAYS      = "400"
      RUN_TTL_DAYS          = "30"
      HTTP_TIMEOUT_SECONDS  = "25"
      HTTP_MAX_ATTEMPTS     = "3"
      LOG_LEVEL             = "INFO"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_ingest,
    aws_iam_role_policy.lambda_ingest
  ]
}

resource "aws_cloudwatch_log_group" "glue_error" {
  name              = "/aws-glue/jobs/${local.resource_prefix}/error"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "glue_output" {
  name              = "/aws-glue/jobs/${local.resource_prefix}/output"
  retention_in_days = 14
}

resource "aws_glue_job" "raw_to_curated" {
  name              = local.glue_job_name
  description       = "Convert API-Sports raw JSON snapshots to partitioned Parquet curated tables"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 20
  max_retries       = 1
  execution_class   = "STANDARD"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.data_lake.id}/${aws_s3_object.glue_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                         = "python"
    "--enable-metrics"                       = "true"
    "--enable-glue-datacatalog"              = "true"
    "--custom-logGroup-prefix"               = "/aws-glue/jobs/${local.resource_prefix}"
    "--custom-logStream-prefix"              = local.resource_prefix
    "--TempDir"                              = "s3://${aws_s3_bucket.data_lake.id}/glue-temp/"
    "--BUCKET"                               = aws_s3_bucket.data_lake.id
    "--RAW_PREFIX"                           = "raw"
    "--CURATED_PREFIX"                       = "curated"
    "--INGESTION_RUN_ID"                     = "manual-or-scheduled"
    "--INGESTION_DATE"                           = "1970-01-01"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.glue_service_role,
    aws_iam_role_policy.glue_data_lake,
    aws_s3_object.glue_script,
    aws_cloudwatch_log_group.glue_error,
    aws_cloudwatch_log_group.glue_output
  ]
}

resource "aws_sqs_queue" "scheduler_dlq" {
  name                      = "${local.resource_prefix}-scheduler-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_scheduler_schedule" "daily_ingestion" {
  name        = "${local.resource_prefix}-daily-ingestion"
  description = "Asynchronous daily trigger for API-Sports ingestion"
  state       = var.enable_schedule ? "ENABLED" : "DISABLED"

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.ingest.arn
    role_arn = aws_iam_role.scheduler.arn
    input = jsonencode({
      source  = "eventbridge-scheduler"
      purpose = "daily-api-sports-ingestion"
    })

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }

  depends_on = [aws_iam_role_policy.scheduler]
}

resource "aws_lambda_permission" "allow_scheduler" {
  statement_id  = "AllowExecutionFromEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.daily_ingestion.arn
}
