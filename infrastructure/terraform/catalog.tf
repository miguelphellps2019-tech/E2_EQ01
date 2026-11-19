locals {
  fixtures_columns = [
    { name = "fixture_id", type = "bigint" },
    { name = "league_name", type = "string" },
    { name = "league_country", type = "string" },
    { name = "round_name", type = "string" },
    { name = "fixture_timestamp", type = "timestamp" },
    { name = "timezone", type = "string" },
    { name = "referee", type = "string" },
    { name = "venue_id", type = "bigint" },
    { name = "venue_name", type = "string" },
    { name = "venue_city", type = "string" },
    { name = "status_long", type = "string" },
    { name = "status_short", type = "string" },
    { name = "elapsed_minutes", type = "int" },
    { name = "home_team_id", type = "bigint" },
    { name = "home_team_name", type = "string" },
    { name = "home_winner", type = "boolean" },
    { name = "away_team_id", type = "bigint" },
    { name = "away_team_name", type = "string" },
    { name = "away_winner", type = "boolean" },
    { name = "home_goals", type = "int" },
    { name = "away_goals", type = "int" },
    { name = "halftime_home", type = "int" },
    { name = "halftime_away", type = "int" },
    { name = "fulltime_home", type = "int" },
    { name = "fulltime_away", type = "int" },
    { name = "extratime_home", type = "int" },
    { name = "extratime_away", type = "int" },
    { name = "penalty_home", type = "int" },
    { name = "penalty_away", type = "int" },
    { name = "run_id", type = "string" },
    { name = "ingested_at", type = "timestamp" },
    { name = "source_file", type = "string" }
  ]

  teams_columns = [
    { name = "team_id", type = "bigint" },
    { name = "team_name", type = "string" },
    { name = "team_code", type = "string" },
    { name = "country", type = "string" },
    { name = "founded_year", type = "int" },
    { name = "is_national", type = "boolean" },
    { name = "logo_url", type = "string" },
    { name = "venue_id", type = "bigint" },
    { name = "venue_name", type = "string" },
    { name = "venue_address", type = "string" },
    { name = "venue_city", type = "string" },
    { name = "venue_capacity", type = "int" },
    { name = "venue_surface", type = "string" },
    { name = "venue_image_url", type = "string" },
    { name = "run_id", type = "string" },
    { name = "ingested_at", type = "timestamp" },
    { name = "source_file", type = "string" }
  ]

  standings_columns = [
    { name = "rank", type = "int" },
    { name = "team_id", type = "bigint" },
    { name = "team_name", type = "string" },
    { name = "team_logo_url", type = "string" },
    { name = "points", type = "int" },
    { name = "goal_difference", type = "int" },
    { name = "group_name", type = "string" },
    { name = "recent_form", type = "string" },
    { name = "standing_status", type = "string" },
    { name = "description", type = "string" },
    { name = "all_played", type = "int" },
    { name = "all_wins", type = "int" },
    { name = "all_draws", type = "int" },
    { name = "all_losses", type = "int" },
    { name = "all_goals_for", type = "int" },
    { name = "all_goals_against", type = "int" },
    { name = "home_played", type = "int" },
    { name = "home_wins", type = "int" },
    { name = "home_draws", type = "int" },
    { name = "home_losses", type = "int" },
    { name = "away_played", type = "int" },
    { name = "away_wins", type = "int" },
    { name = "away_draws", type = "int" },
    { name = "away_losses", type = "int" },
    { name = "standing_updated_at", type = "timestamp" },
    { name = "league_name", type = "string" },
    { name = "league_country", type = "string" },
    { name = "run_id", type = "string" },
    { name = "ingested_at", type = "timestamp" },
    { name = "source_file", type = "string" }
  ]
}

resource "aws_glue_catalog_database" "analytics" {
  name        = local.database_name
  description = "Curated API-Sports data exposed to Amazon Athena"
}

resource "aws_glue_catalog_table" "fixtures" {
  database_name = aws_glue_catalog_database.analytics.name
  name          = "fixtures"
  description   = "Latest fixture snapshot, stored as Parquet and partitioned by league, season, and month"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                                = "TRUE"
    classification                          = "parquet"
    "parquet.compression"                  = "SNAPPY"
    "projection.enabled"                   = "true"
    "projection.league_id.type"            = "integer"
    "projection.league_id.range"           = "1,100000"
    "projection.season.type"               = "integer"
    "projection.season.range"              = "2010,2035"
    "projection.event_month.type"          = "date"
    "projection.event_month.range"         = "2010-01,2035-12"
    "projection.event_month.format"        = "yyyy-MM"
    "projection.event_month.interval"      = "1"
    "projection.event_month.interval.unit" = "MONTHS"
    "storage.location.template"            = "s3://${aws_s3_bucket.data_lake.id}/curated/fixtures/league_id=$${league_id}/season=$${season}/event_month=$${event_month}/"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_lake.id}/curated/fixtures/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.fixtures_columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }

  partition_keys {
    name = "league_id"
    type = "int"
  }

  partition_keys {
    name = "season"
    type = "int"
  }

  partition_keys {
    name = "event_month"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "teams" {
  database_name = aws_glue_catalog_database.analytics.name
  name          = "teams"
  description   = "Teams and venues returned by API-Football"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                      = "TRUE"
    classification                = "parquet"
    "parquet.compression"        = "SNAPPY"
    "projection.enabled"         = "true"
    "projection.league_id.type"  = "integer"
    "projection.league_id.range" = "1,100000"
    "projection.season.type"     = "integer"
    "projection.season.range"    = "2010,2035"
    "storage.location.template"  = "s3://${aws_s3_bucket.data_lake.id}/curated/teams/league_id=$${league_id}/season=$${season}/"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_lake.id}/curated/teams/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.teams_columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }

  partition_keys {
    name = "league_id"
    type = "int"
  }

  partition_keys {
    name = "season"
    type = "int"
  }
}

resource "aws_glue_catalog_table" "standings" {
  database_name = aws_glue_catalog_database.analytics.name
  name          = "standings"
  description   = "Latest league standings by team"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                      = "TRUE"
    classification                = "parquet"
    "parquet.compression"        = "SNAPPY"
    "projection.enabled"         = "true"
    "projection.league_id.type"  = "integer"
    "projection.league_id.range" = "1,100000"
    "projection.season.type"     = "integer"
    "projection.season.range"    = "2010,2035"
    "storage.location.template"  = "s3://${aws_s3_bucket.data_lake.id}/curated/standings/league_id=$${league_id}/season=$${season}/"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_lake.id}/curated/standings/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.standings_columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }

  partition_keys {
    name = "league_id"
    type = "int"
  }

  partition_keys {
    name = "season"
    type = "int"
  }
}
