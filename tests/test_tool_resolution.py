"""Tests for tool_utils.find_tool executable resolution."""

import os
import shutil
import sys

import pytest

from tool_utils import find_tool, tool_env


def test_find_tool_prefers_sys_executable_dir(tmp_path, monkeypatch):
    """A tool sitting next to sys.executable (unactivated venv) wins."""
    exe_name = "sometool.exe" if os.name == "nt" else "sometool"
    py_name = "python.exe" if os.name == "nt" else "python"
    tool = tmp_path / exe_name
    tool.write_text("")
    monkeypatch.setattr(sys, "executable", str(tmp_path / py_name))
    monkeypatch.setattr(shutil, "which", lambda n: None)
    assert find_tool("sometool") == str(tool)


def test_find_tool_falls_back_to_path(tmp_path, monkeypatch):
    """Falls back to shutil.which when not next to sys.executable."""
    py_name = "python.exe" if os.name == "nt" else "python"
    monkeypatch.setattr(sys, "executable", str(tmp_path / py_name))
    monkeypatch.setattr(shutil, "which", lambda n: os.path.join("usr", "bin", n))
    assert find_tool("semgrep") == os.path.join("usr", "bin", "semgrep")


def test_find_tool_falls_back_to_bare_name(tmp_path, monkeypatch):
    """Returns the bare name when the tool is nowhere to be found."""
    py_name = "python.exe" if os.name == "nt" else "python"
    monkeypatch.setattr(sys, "executable", str(tmp_path / py_name))
    monkeypatch.setattr(shutil, "which", lambda n: None)
    assert find_tool("no-such-tool-xyz") == "no-such-tool-xyz"


def test_semgrep_resolves_to_existing_file():
    """In this project's venv, semgrep must resolve to a real file."""
    assert os.path.isfile(find_tool("semgrep"))


def test_tool_env_forces_utf8_mode():
    """Child tool processes must run in UTF-8 mode regardless of locale.

    On Windows with a CJK locale (e.g. GBK), Python defaults open() to the
    locale encoding, which crashes semgrep on UTF-8 config/source files.
    PYTHONUTF8=1 makes Python default to UTF-8 everywhere.
    """
    env = tool_env()
    assert env["PYTHONUTF8"] == "1"


def test_tool_env_preserves_existing_environment(monkeypatch):
    """tool_env augments os.environ, it does not replace it."""
    monkeypatch.setenv("PATH", os.environ.get("PATH", ""))
    env = tool_env()
    assert "PATH" in env
    assert env is not os.environ


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
