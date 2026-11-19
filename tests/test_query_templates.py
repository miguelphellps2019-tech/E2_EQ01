from pathlib import Path

from scripts.run_athena_queries import render_sql


def test_query_templates_are_fully_rendered() -> None:
    query_dir = Path(__file__).resolve().parents[1] / "athena" / "queries"
    for path in query_dir.glob("*.sql"):
        rendered = render_sql(path, "demo_db", 39, 2024)
        assert "{{" not in rendered
        assert "demo_db" in rendered
        assert "39" in rendered
        assert "2024" in rendered
        assert "2025" in rendered
