-- Consulta 3: reconcilia los puntos oficiales de standings contra los calculados desde fixtures.
WITH team_results AS (
    SELECT
        home_team_id AS team_id,
        CASE
            WHEN home_goals > away_goals THEN 3
            WHEN home_goals = away_goals THEN 1
            ELSE 0
        END AS points
    FROM {{DATABASE}}.fixtures
    WHERE league_id = {{LEAGUE_ID}}
      AND season = {{SEASON}}
      AND event_month BETWEEN '{{SEASON}}-01' AND '{{NEXT_SEASON}}-12'
      AND status_short = 'FT'

    UNION ALL

    SELECT
        away_team_id AS team_id,
        CASE
            WHEN away_goals > home_goals THEN 3
            WHEN away_goals = home_goals THEN 1
            ELSE 0
        END AS points
    FROM {{DATABASE}}.fixtures
    WHERE league_id = {{LEAGUE_ID}}
      AND season = {{SEASON}}
      AND event_month BETWEEN '{{SEASON}}-01' AND '{{NEXT_SEASON}}-12'
      AND status_short = 'FT'
),
calculated AS (
    SELECT
        team_id,
        COUNT(*) AS played_from_fixtures,
        SUM(points) AS calculated_points
    FROM team_results
    GROUP BY team_id
)
SELECT
    s.rank,
    s.team_name,
    s.all_played AS official_played,
    c.played_from_fixtures,
    s.points AS official_points,
    c.calculated_points,
    s.points - c.calculated_points AS point_difference
FROM {{DATABASE}}.standings AS s
LEFT JOIN calculated AS c
    ON s.team_id = c.team_id
WHERE s.league_id = {{LEAGUE_ID}}
  AND s.season = {{SEASON}}
ORDER BY s.rank;
