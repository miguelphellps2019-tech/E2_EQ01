resource "aws_athena_workgroup" "analytics" {
  name        = local.workgroup_name
  description = "Controlled Athena workgroup for ${var.project_name}"
  state       = "ENABLED"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_bytes_scanned_cutoff

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${aws_s3_bucket.data_lake.id}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

locals {
  query_01 = replace(
    replace(
      replace(
        replace(file("${path.module}/../../athena/queries/01_home_win_rate.sql"), "{{DATABASE}}", aws_glue_catalog_database.analytics.name),
        "{{LEAGUE_ID}}",
        tostring(var.league_id)
      ),
      "{{NEXT_SEASON}}",
      tostring(var.season + 1)
    ),
    "{{SEASON}}",
    tostring(var.season)
  )

  query_02 = replace(
    replace(
      replace(
        replace(file("${path.module}/../../athena/queries/02_goals_by_month.sql"), "{{DATABASE}}", aws_glue_catalog_database.analytics.name),
        "{{LEAGUE_ID}}",
        tostring(var.league_id)
      ),
      "{{NEXT_SEASON}}",
      tostring(var.season + 1)
    ),
    "{{SEASON}}",
    tostring(var.season)
  )

  query_03 = replace(
    replace(
      replace(
        replace(file("${path.module}/../../athena/queries/03_reconcile_standings.sql"), "{{DATABASE}}", aws_glue_catalog_database.analytics.name),
        "{{LEAGUE_ID}}",
        tostring(var.league_id)
      ),
      "{{NEXT_SEASON}}",
      tostring(var.season + 1)
    ),
    "{{SEASON}}",
    tostring(var.season)
  )
}

resource "aws_athena_named_query" "home_win_rate" {
  name        = "01-home-win-rate"
  description = "Home performance by team"
  database    = aws_glue_catalog_database.analytics.name
  workgroup   = aws_athena_workgroup.analytics.id
  query       = local.query_01
}

resource "aws_athena_named_query" "goals_by_month" {
  name        = "02-goals-by-month"
  description = "Matches and goals by event month"
  database    = aws_glue_catalog_database.analytics.name
  workgroup   = aws_athena_workgroup.analytics.id
  query       = local.query_02
}

resource "aws_athena_named_query" "reconcile_standings" {
  name        = "03-reconcile-standings"
  description = "Compare official standings points with points calculated from fixtures"
  database    = aws_glue_catalog_database.analytics.name
  workgroup   = aws_athena_workgroup.analytics.id
  query       = local.query_03
}
