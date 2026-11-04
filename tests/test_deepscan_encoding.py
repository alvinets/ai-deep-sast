"""Regression: deep scan must read Semgrep JSON as UTF-8.

Same defect class as the fast scanner: Semgrep writes UTF-8, the host locale
here is GBK, and `json.load(fh)` on a non-ASCII finding raised
UnicodeDecodeError (unhandled, so the whole scan aborted).
"""

import json
import os
import subprocess

import deepscan


def _orchestrator(output_dir, target="."):
    """Build an Orchestrator without running __init__ (only two attrs needed)."""
    orch = deepscan.Orchestrator.__new__(deepscan.Orchestrator)
    orch.output_dir = str(output_dir)
    orch.target = target
    return orch


def test_existing_report_with_non_ascii_is_loaded(tmp_path):
    payload = {
        "results": [
            {
                "check_id": "config.hardcoded-password-properties",
                "path": "caf\u00e9\u2014secrets.properties",
                "start": {"line": 1},
                "extra": {"severity": "ERROR", "message": "Mot de passe \u2014 expos\u00e9"},
            }
        ]
    }
    with open(os.path.join(str(tmp_path), "semgrep_report.json"), "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)

    results = _orchestrator(tmp_path)._run_semgrep()

    assert len(results) == 1
    assert results[0]["path"] == "caf\u00e9\u2014secrets.properties"


def test_semgrep_run_decodes_utf8_and_sets_env(tmp_path, monkeypatch):
    captured = {}

    def fake_run(cmd, **kwargs):
        captured["kwargs"] = kwargs
        out = next(a.split("=", 1)[1] for a in cmd if a.startswith("--output="))
        with open(out, "w", encoding="utf-8") as f:
            json.dump({"results": [{"check_id": "x", "path": "caf\u00e9.properties"}]}, f,
                      ensure_ascii=False)

        class _Result:
            returncode = 0
            stdout = ""
            stderr = ""

        return _Result()

    monkeypatch.setattr(subprocess, "run", fake_run)

    results = _orchestrator(tmp_path)._run_semgrep()

    assert len(results) == 1
    assert captured["kwargs"].get("encoding") == "utf-8"
    assert captured["kwargs"].get("env", {}).get("PYTHONUTF8") == "1"
