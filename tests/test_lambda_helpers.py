from __future__ import annotations

import importlib
import os
from datetime import datetime, timezone

os.environ.update(
    {
        "AWS_ACCESS_KEY_ID": "testing",
        "AWS_SECRET_ACCESS_KEY": "testing",
        "AWS_SESSION_TOKEN": "testing",
        "AWS_DEFAULT_REGION": "us-east-1",
        "AWS_EC2_METADATA_DISABLED": "true",
        "API_KEY_PARAMETER_NAME": "/test/key",
        "BUCKET_NAME": "test-bucket",
        "DDB_TABLE_NAME": "test-table",
        "GLUE_JOB_NAME": "test-job",
        "LEAGUE_ID": "39",
        "SEASON": "2024",
    }
)

app = importlib.import_module("src.lambda_ingest.app")


def test_logical_errors_supports_dictionary() -> None:
    assert app._logical_api_errors({"errors": {"season": "invalid"}}) == [
        "season: invalid"
    ]


def test_raw_key_is_deterministic() -> None:
    now = datetime(2026, 11, 18, 3, 10, tzinfo=timezone.utc)
    assert app._raw_key("fixtures", "20261118-league-39-season-2024", now) == (
        "raw/source=api_sports/entity=fixtures/ingestion_date=2026-11-18/"
        "run_id=20261118-league-39-season-2024.json"
    )


def test_fixture_item_shape() -> None:
    payload = {
        "response": [
            {
                "fixture": {
                    "id": 123,
                    "date": "2024-08-17T14:00:00+00:00",
                    "status": {"short": "FT", "long": "Match Finished"},
                },
                "league": {"id": 39, "season": 2024, "round": "Regular Season - 1"},
                "teams": {
                    "home": {"id": 1, "name": "Home"},
                    "away": {"id": 2, "name": "Away"},
                },
                "goals": {"home": 2, "away": 1},
            }
        ]
    }
    now = datetime(2026, 11, 18, tzinfo=timezone.utc)
    item = app._fixture_items(payload, "run-1", now)[0]
    assert item["pk"] == "FIXTURE#123"
    assert item["gsi1pk"] == "LEAGUE#39#SEASON#2024"
    assert item["home_goals"] == 2
    assert item["away_goals"] == 1
    assert item["expires_at"] > int(now.timestamp())


def test_validate_payload_rejects_empty_response() -> None:
    try:
        app._validate_api_payload("fixtures", {"errors": [], "response": []})
    except app.ApiSportsError as exc:
        assert "cero registros" in str(exc)
    else:
        raise AssertionError("Se esperaba ApiSportsError")


def test_run_id_rejects_path_characters() -> None:
    try:
        app._validated_run_id("../../secret")
    except ValueError:
        pass
    else:
        raise AssertionError("Se esperaba ValueError")


def test_api_key_prefers_environment_variable(monkeypatch) -> None:
    monkeypatch.setenv("API_KEY", "  env-key  ")

    def fail_ssm(**_kwargs):
        raise AssertionError("SSM no debe consultarse si API_KEY existe")

    monkeypatch.setattr(app.ssm, "get_parameter", fail_ssm)
    assert app._api_key() == "env-key"


def test_api_key_falls_back_to_ssm(monkeypatch) -> None:
    monkeypatch.delenv("API_KEY", raising=False)
    monkeypatch.setattr(
        app.ssm,
        "get_parameter",
        lambda **_kwargs: {"Parameter": {"Value": "ssm-key"}},
    )
    assert app._api_key() == "ssm-key"
