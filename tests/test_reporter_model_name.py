"""Regression: the deep-scan report must name the model that actually ran.

The Markdown header hardcoded "Opus 4 (Anthropic)" regardless of which
endpoint/model was used, so a report produced by a local or third-party
OpenAI-compatible model was mislabelled.
"""

import pytest

from finding_store import FindingStore
from deepscan_reporter import DeepScanReporter


@pytest.fixture
def store(tmp_path):
    return FindingStore(db_path=str(tmp_path / "modelname.db"))


def test_report_shows_configured_model_name(store, tmp_path):
    reporter = DeepScanReporter(
        store, output_dir=str(tmp_path / "r1"), model_name="qwen38-efi"
    )
    md = open(reporter.generate_report(), encoding="utf-8").read()
    assert "**Model**: qwen38-efi" in md
    assert "Opus 4" not in md


def test_report_falls_back_to_env_model(store, tmp_path, monkeypatch):
    monkeypatch.setenv("LLM_MODEL", "gpt-4o-mini")
    reporter = DeepScanReporter(store, output_dir=str(tmp_path / "r2"))
    md = open(reporter.generate_report(), encoding="utf-8").read()
    assert "**Model**: gpt-4o-mini" in md


def test_report_marks_model_unknown_when_unset(store, tmp_path, monkeypatch):
    monkeypatch.delenv("LLM_MODEL", raising=False)
    reporter = DeepScanReporter(store, output_dir=str(tmp_path / "r3"))
    md = open(reporter.generate_report(), encoding="utf-8").read()
    assert "**Model**: unknown" in md
