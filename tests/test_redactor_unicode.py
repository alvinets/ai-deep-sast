"""Regression tests for the secret-redaction scan path.

Two independent defects are covered:

1. `run_semgrep_for_secrets` passed its default config string
   ("p/secrets,config/custom-secrets.yaml") as a SINGLE `--config` argument.
   Semgrep treats that as one registry path, returns HTTP 404 + exit code 7,
   and the function swallows it into `[]` — silently disabling redaction
   before source code is sent to the LLM.
2. Semgrep emits UTF-8 JSON, but the output was decoded with the host locale
   codec (GBK on zh-CN Windows). Any non-ASCII byte in a finding raised
   UnicodeDecodeError in subprocess's reader thread, emptying stdout and
   again yielding `[]` via the JSONDecodeError branch.
"""

import subprocess

from redactor import run_semgrep_for_secrets

LOCAL_RULES = "config/custom-secrets.yaml"


def test_secret_scan_reads_non_ascii_output(tmp_path):
    """A non-ASCII path in semgrep's JSON must not blank out the findings."""
    fixture = tmp_path / "caf\u00e9\u2014secrets.properties"
    fixture.write_text(
        "db.password=S3cr3t\u2014value\napi_key=AbCdEf123456\u2014\n",
        encoding="utf-8",
    )

    findings = run_semgrep_for_secrets(str(fixture), semgrep_config=LOCAL_RULES, timeout=180)

    assert findings, "non-ASCII semgrep output was dropped (redaction would silently no-op)"
    assert any(f.get("check_id") for f in findings)


def test_default_config_is_split_into_separate_flags(monkeypatch):
    """A comma-separated config list must become one --config per entry."""
    captured = {}

    class _Result:
        returncode = 0
        stdout = '{"results": []}'
        stderr = ""

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        captured["kwargs"] = kwargs
        return _Result()

    monkeypatch.setattr(subprocess, "run", fake_run)

    run_semgrep_for_secrets("target.properties")

    cmd = captured["cmd"]
    config_values = [cmd[i + 1] for i, a in enumerate(cmd) if a == "--config"]
    assert config_values == ["p/secrets", LOCAL_RULES], f"configs not split: {config_values}"
    assert "p/secrets,config/custom-secrets.yaml" not in cmd


def test_output_is_decoded_as_utf8(monkeypatch):
    """The subprocess must be told to decode UTF-8 explicitly."""
    captured = {}

    class _Result:
        returncode = 0
        stdout = '{"results": []}'
        stderr = ""

    def fake_run(cmd, **kwargs):
        captured["kwargs"] = kwargs
        return _Result()

    monkeypatch.setattr(subprocess, "run", fake_run)

    run_semgrep_for_secrets("target.properties", semgrep_config=LOCAL_RULES)

    assert captured["kwargs"].get("encoding") == "utf-8"
