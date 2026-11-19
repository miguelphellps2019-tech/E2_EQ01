"""AWS Glue Spark job: API-Sports raw JSON -> curated Parquet.

Input layout
------------
s3://<bucket>/raw/source=api_sports/entity=<entity>/ingestion_date=YYYY-MM-DD/run_id=<id>.json

Output layout
-------------
fixtures:  curated/fixtures/league_id=<id>/season=<yyyy>/event_month=<yyyy-MM>/
teams:     curated/teams/league_id=<id>/season=<yyyy>/
standings: curated/standings/league_id=<id>/season=<yyyy>/

Each API endpoint is a complete league-season snapshot. The job reads only the
three objects from the current ingestion run, deduplicates business keys, and
overwrites the affected Hive-style partitions. Historical raw remains available
for audit and explicit reprocessing without increasing the routine scan.
"""

from __future__ import annotations

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import DataFrame
from pyspark.sql.functions import (
    col,
    date_format,
    explode_outer,
    input_file_name,
    row_number,
    to_timestamp,
)
from pyspark.sql.window import Window

ARGS = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "BUCKET",
        "RAW_PREFIX",
        "CURATED_PREFIX",
        "INGESTION_RUN_ID",
        "INGESTION_DATE",
    ],
)

sc = SparkContext.getOrCreate()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(ARGS["JOB_NAME"], ARGS)

BUCKET = ARGS["BUCKET"]
RAW_PREFIX = ARGS["RAW_PREFIX"].strip("/")
CURATED_PREFIX = ARGS["CURATED_PREFIX"].strip("/")
INGESTION_RUN_ID = ARGS["INGESTION_RUN_ID"]
INGESTION_DATE = ARGS["INGESTION_DATE"]

spark.conf.set("spark.sql.session.timeZone", "UTC")
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
spark.conf.set("spark.sql.shuffle.partitions", "24")
spark.conf.set("spark.sql.parquet.compression.codec", "snappy")
spark.conf.set("spark.sql.files.maxRecordsPerFile", "250000")
spark.conf.set("spark.hadoop.mapreduce.fileoutputcommitter.algorithm.version", "2")


def raw_path(entity: str) -> str:
    return (
        f"s3://{BUCKET}/{RAW_PREFIX}/source=api_sports/entity={entity}/"
        f"ingestion_date={INGESTION_DATE}/run_id={INGESTION_RUN_ID}.json"
    )


def curated_path(entity: str) -> str:
    return f"s3://{BUCKET}/{CURATED_PREFIX}/{entity}/"


def read_entity(entity: str) -> DataFrame:
    return (
        spark.read.option("multiLine", "true")
        .json(raw_path(entity))
        .withColumn("_source_file", input_file_name())
    )


def latest_by(df: DataFrame, business_keys: list[str]) -> DataFrame:
    window = Window.partitionBy(*business_keys).orderBy(col("ingested_at").desc())
    return df.withColumn("_row_number", row_number().over(window)).filter(
        col("_row_number") == 1
    ).drop("_row_number")


def write_partitioned(df: DataFrame, entity: str, partition_columns: list[str]) -> None:
    (
        df.repartition(*[col(name) for name in partition_columns])
        .write.mode("overwrite")
        .option("compression", "snappy")
        .partitionBy(*partition_columns)
        .parquet(curated_path(entity))
    )


def transform_fixtures() -> int:
    raw = read_entity("fixtures")
    exploded = raw.select(
        col("metadata.run_id").alias("run_id"),
        to_timestamp(col("metadata.ingested_at")).alias("ingested_at"),
        col("_source_file").alias("source_file"),
        explode_outer(col("payload.response")).alias("r"),
    )

    fixtures = exploded.select(
        col("r.fixture.id").cast("bigint").alias("fixture_id"),
        col("r.league.id").cast("int").alias("league_id"),
        col("r.league.name").cast("string").alias("league_name"),
        col("r.league.country").cast("string").alias("league_country"),
        col("r.league.season").cast("int").alias("season"),
        col("r.league.round").cast("string").alias("round_name"),
        to_timestamp(col("r.fixture.date")).alias("fixture_timestamp"),
        date_format(to_timestamp(col("r.fixture.date")), "yyyy-MM").alias("event_month"),
        col("r.fixture.timezone").cast("string").alias("timezone"),
        col("r.fixture.referee").cast("string").alias("referee"),
        col("r.fixture.venue.id").cast("bigint").alias("venue_id"),
        col("r.fixture.venue.name").cast("string").alias("venue_name"),
        col("r.fixture.venue.city").cast("string").alias("venue_city"),
        col("r.fixture.status.long").cast("string").alias("status_long"),
        col("r.fixture.status.short").cast("string").alias("status_short"),
        col("r.fixture.status.elapsed").cast("int").alias("elapsed_minutes"),
        col("r.teams.home.id").cast("bigint").alias("home_team_id"),
        col("r.teams.home.name").cast("string").alias("home_team_name"),
        col("r.teams.home.winner").cast("boolean").alias("home_winner"),
        col("r.teams.away.id").cast("bigint").alias("away_team_id"),
        col("r.teams.away.name").cast("string").alias("away_team_name"),
        col("r.teams.away.winner").cast("boolean").alias("away_winner"),
        col("r.goals.home").cast("int").alias("home_goals"),
        col("r.goals.away").cast("int").alias("away_goals"),
        col("r.score.halftime.home").cast("int").alias("halftime_home"),
        col("r.score.halftime.away").cast("int").alias("halftime_away"),
        col("r.score.fulltime.home").cast("int").alias("fulltime_home"),
        col("r.score.fulltime.away").cast("int").alias("fulltime_away"),
        col("r.score.extratime.home").cast("int").alias("extratime_home"),
        col("r.score.extratime.away").cast("int").alias("extratime_away"),
        col("r.score.penalty.home").cast("int").alias("penalty_home"),
        col("r.score.penalty.away").cast("int").alias("penalty_away"),
        col("run_id"),
        col("ingested_at"),
        col("source_file"),
    ).filter(col("fixture_id").isNotNull())

    latest = latest_by(fixtures, ["fixture_id"]).cache()
    row_count = latest.count()
    if row_count == 0:
        raise RuntimeError("La transformación fixtures produjo cero filas.")
    write_partitioned(latest, "fixtures", ["league_id", "season", "event_month"])
    latest.unpersist()
    return row_count


def transform_teams() -> int:
    raw = read_entity("teams")
    exploded = raw.select(
        col("metadata.run_id").alias("run_id"),
        to_timestamp(col("metadata.ingested_at")).alias("ingested_at"),
        col("metadata.league_id").cast("int").alias("league_id"),
        col("metadata.season").cast("int").alias("season"),
        col("_source_file").alias("source_file"),
        explode_outer(col("payload.response")).alias("r"),
    )

    teams = exploded.select(
        col("r.team.id").cast("bigint").alias("team_id"),
        col("r.team.name").cast("string").alias("team_name"),
        col("r.team.code").cast("string").alias("team_code"),
        col("r.team.country").cast("string").alias("country"),
        col("r.team.founded").cast("int").alias("founded_year"),
        col("r.team.national").cast("boolean").alias("is_national"),
        col("r.team.logo").cast("string").alias("logo_url"),
        col("r.venue.id").cast("bigint").alias("venue_id"),
        col("r.venue.name").cast("string").alias("venue_name"),
        col("r.venue.address").cast("string").alias("venue_address"),
        col("r.venue.city").cast("string").alias("venue_city"),
        col("r.venue.capacity").cast("int").alias("venue_capacity"),
        col("r.venue.surface").cast("string").alias("venue_surface"),
        col("r.venue.image").cast("string").alias("venue_image_url"),
        col("league_id"),
        col("season"),
        col("run_id"),
        col("ingested_at"),
        col("source_file"),
    ).filter(col("team_id").isNotNull())

    latest = latest_by(teams, ["league_id", "season", "team_id"]).cache()
    row_count = latest.count()
    if row_count == 0:
        raise RuntimeError("La transformación teams produjo cero filas.")
    write_partitioned(latest, "teams", ["league_id", "season"])
    latest.unpersist()
    return row_count


def transform_standings() -> int:
    raw = read_entity("standings")
    leagues = raw.select(
        col("metadata.run_id").alias("run_id"),
        to_timestamp(col("metadata.ingested_at")).alias("ingested_at"),
        col("_source_file").alias("source_file"),
        explode_outer(col("payload.response")).alias("r"),
    )
    groups = leagues.select(
        col("run_id"),
        col("ingested_at"),
        col("source_file"),
        col("r.league.id").cast("int").alias("league_id"),
        col("r.league.name").cast("string").alias("league_name"),
        col("r.league.country").cast("string").alias("league_country"),
        col("r.league.season").cast("int").alias("season"),
        explode_outer(col("r.league.standings")).alias("standing_group"),
    )
    rows = groups.select(
        "*", explode_outer(col("standing_group")).alias("s")
    ).drop("standing_group")

    standings = rows.select(
        col("s.rank").cast("int").alias("rank"),
        col("s.team.id").cast("bigint").alias("team_id"),
        col("s.team.name").cast("string").alias("team_name"),
        col("s.team.logo").cast("string").alias("team_logo_url"),
        col("s.points").cast("int").alias("points"),
        col("s.goalsDiff").cast("int").alias("goal_difference"),
        col("s.group").cast("string").alias("group_name"),
        col("s.form").cast("string").alias("recent_form"),
        col("s.status").cast("string").alias("standing_status"),
        col("s.description").cast("string").alias("description"),
        col("s.all.played").cast("int").alias("all_played"),
        col("s.all.win").cast("int").alias("all_wins"),
        col("s.all.draw").cast("int").alias("all_draws"),
        col("s.all.lose").cast("int").alias("all_losses"),
        col("s.all.goals").getField("for").cast("int").alias("all_goals_for"),
        col("s.all.goals").getField("against").cast("int").alias("all_goals_against"),
        col("s.home.played").cast("int").alias("home_played"),
        col("s.home.win").cast("int").alias("home_wins"),
        col("s.home.draw").cast("int").alias("home_draws"),
        col("s.home.lose").cast("int").alias("home_losses"),
        col("s.away.played").cast("int").alias("away_played"),
        col("s.away.win").cast("int").alias("away_wins"),
        col("s.away.draw").cast("int").alias("away_draws"),
        col("s.away.lose").cast("int").alias("away_losses"),
        to_timestamp(col("s.update")).alias("standing_updated_at"),
        col("league_name"),
        col("league_country"),
        col("league_id"),
        col("season"),
        col("run_id"),
        col("ingested_at"),
        col("source_file"),
    ).filter(col("team_id").isNotNull())

    # Some cups have null group names. A stable placeholder keeps the business
    # key deterministic without changing the user-facing description.
    keyed = standings.withColumn(
        "_group_key", col("group_name")
    ).fillna({"_group_key": "UNGROUPED"})
    latest = latest_by(keyed, ["league_id", "season", "_group_key", "team_id"]).drop(
        "_group_key"
    ).cache()
    row_count = latest.count()
    if row_count == 0:
        raise RuntimeError("La transformación standings produjo cero filas.")
    write_partitioned(latest, "standings", ["league_id", "season"])
    latest.unpersist()
    return row_count


counts = {
    "fixtures": transform_fixtures(),
    "teams": transform_teams(),
    "standings": transform_standings(),
}
print(f"Curated row counts: {counts}")
job.commit()
