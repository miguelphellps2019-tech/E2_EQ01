-- Consulta 2: partidos y goles por mes de competencia.
-- event_month es una partición; el filtro por liga y temporada evita escaneos innecesarios.
SELECT
    event_month,
    COUNT(*) AS matches,
    SUM(COALESCE(home_goals, 0) + COALESCE(away_goals, 0)) AS total_goals,
    ROUND(
        1.0 * SUM(COALESCE(home_goals, 0) + COALESCE(away_goals, 0)) / COUNT(*),
        2
    ) AS goals_per_match
FROM {{DATABASE}}.fixtures
WHERE league_id = {{LEAGUE_ID}}
  AND season = {{SEASON}}
  AND event_month BETWEEN '{{SEASON}}-01' AND '{{NEXT_SEASON}}-12'
  AND status_short = 'FT'
GROUP BY event_month
ORDER BY event_month;
