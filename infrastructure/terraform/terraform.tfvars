aws_region             = "us-east-1"
project_name           = "e2-eq01-api-sports"
team_code              = "EQ01"
league_id              = 39
season                 = 2024
schedule_expression    = "cron(10 3 * * ? *)"
enable_schedule        = true
api_key_parameter_name = "/e2/eq01/api-sports/key"
force_destroy_bucket   = true

extra_tags = {
  Environment = "academic"
  Owner       = "equipo-eq01"
}
