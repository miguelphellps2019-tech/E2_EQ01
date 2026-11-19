-- Consulta 1: desempeño como local por equipo.
-- Los bytes reales se capturan con scripts/run_athena_queries.py.
SELECT
    home_team_name,
    COUNT(*) AS home_matches,
    SUM(CASE WHEN home_goals > away_goals THEN 1 ELSE 0 END) AS home_wins,
    SUM(CASE WHEN home_goals = away_goals THEN 1 ELSE 0 END) AS home_draws,
    SUM(CASE WHEN home_goals < away_goals THEN 1 ELSE 0 END) AS home_losses,
    ROUND(
        100.0 * SUM(CASE WHEN home_goals > away_goals THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS home_win_pct
FROM {{DATABASE}}.fixtures
WHERE league_id = {{LEAGUE_ID}}
  AND season = {{SEASON}}
  AND event_month BETWEEN '{{SEASON}}-01' AND '{{NEXT_SEASON}}-12'
  AND status_short = 'FT'
GROUP BY home_team_name
ORDER BY home_win_pct DESC, home_matches DESC, home_team_name;
