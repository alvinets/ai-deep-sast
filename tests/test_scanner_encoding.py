"""Regression: the fast scanner must parse Semgrep JSON as UTF-8.

Semgrep writes UTF-8 JSON to `security-reports/semgrep_report.json`. Reading it
with the host locale codec (GBK on zh-CN Windows) raises UnicodeDecodeError on
any non-ASCII finding (e.g. an accented path or message), and that exception is
not covered by the `json.JSONDecodeError` handler.
"""

import json
import logging
import os
import subprocess

import aideepsast


def _fake_run_writing(payload):
    def fake_run(cmd, **kwargs):
        out = next(a.split("=", 1)[1] for a in cmd if a.startswith("--output="))
        with open(out, "w", encoding="utf-8") as f:
            f.write(payload)

        class _Result:
            returncode = 0
            stdout = ""
            stderr = ""

        return _Result()

    return fake_run


def test_scan_parses_non_ascii_semgrep_json(tmp_path, monkeypatch):
    payload = json.dumps(
        {
            "results": [
                {
                    "check_id": "config.hardcoded-password-properties",
                    "path": "caf\u00e9\u2014secrets.properties",
                    "start": {"line": 1},
                    "extra": {"severity": "ERROR", "message": "Mot de passe \u2014 expos\u00e9"},
                }
            ],
            "errors": [],
        },
        ensure_ascii=False,
    )
    monkeypatch.setattr(subprocess, "run", _fake_run_writing(payload))

    data = aideepsast.run_semgrep_scan(
        target=".", config="config/custom-secrets.yaml",
        output_dir=str(tmp_path), timeout=10, logger=logging.getLogger("test"),
    )

    assert len(data["results"]) == 1
    assert data["results"][0]["path"] == "caf\u00e9\u2014secrets.properties"


def test_scan_decodes_output_as_utf8(tmp_path, monkeypatch):
    captured = {}
    inner = _fake_run_writing('{"results": [], "errors": []}')

    def spy(cmd, **kwargs):
        captured["kwargs"] = kwargs
        return inner(cmd, **kwargs)

    monkeypatch.setattr(subprocess, "run", spy)

    aideepsast.run_semgrep_scan(
        target=".", config="config/custom-secrets.yaml",
        output_dir=str(tmp_path), timeout=10, logger=logging.getLogger("test"),
    )

    assert captured["kwargs"].get("encoding") == "utf-8"
    assert captured["kwargs"].get("env", {}).get("PYTHONUTF8") == "1"
