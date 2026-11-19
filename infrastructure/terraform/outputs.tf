output "bucket_name" {
  description = "S3 data lake bucket containing raw/, curated/, and athena-results/."
  value       = aws_s3_bucket.data_lake.id
}

output "lambda_function_name" {
  value = aws_lambda_function.ingest.function_name
}

output "glue_job_name" {
  value = aws_glue_job.raw_to_curated.name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.operational.name
}

output "glue_database_name" {
  value = aws_glue_catalog_database.analytics.name
}

output "athena_workgroup_name" {
  value = aws_athena_workgroup.analytics.name
}

output "scheduler_name" {
  value = aws_scheduler_schedule.daily_ingestion.name
}

output "scheduler_dlq_url" {
  value = aws_sqs_queue.scheduler_dlq.url
}

output "role_arns" {
  value = {
    data_engineer = aws_iam_role.data_engineer.arn
    analyst       = aws_iam_role.analyst.arn
    data_owner    = aws_iam_role.data_owner.arn
    auditor       = aws_iam_role.auditor.arn
  }
}

output "manual_lambda_invoke_command" {
  value = "aws lambda invoke --region ${var.aws_region} --function-name ${aws_lambda_function.ingest.function_name} --cli-binary-format raw-in-base64-out --payload '{}' /tmp/ingestion-response.json && cat /tmp/ingestion-response.json"
}

output "api_key_bootstrap_command" {
  value = "aws ssm put-parameter --region ${var.aws_region} --name ${var.api_key_parameter_name} --type SecureString --value '<API_KEY>' --overwrite"
}

output "aws_region" {
  value = var.aws_region
}

output "league_id" {
  value = var.league_id
}

output "season" {
  value = var.season
}

output "glue_error_log_group_name" {
  value = aws_cloudwatch_log_group.glue_error.name
}

output "glue_output_log_group_name" {
  value = aws_cloudwatch_log_group.glue_output.name
}
