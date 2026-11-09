"""Regression: log output must survive a GBK console.

On a zh-CN Windows host the console/log stream is GBK. Log messages containing
characters outside that code page (the quality gate used U+274C / U+2705) raise
UnicodeEncodeError inside logging, so the line is silently dropped and a
"--- Logging error ---" traceback is printed instead.
"""

import io
import logging

import aideepsast


def _gbk_logger(stream):
    logger = logging.getLogger("gbk-quality-gate-test")
    logger.handlers = [logging.StreamHandler(stream)]
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


def test_quality_gate_violation_message_is_gbk_safe():
    buf = io.BytesIO()
    stream = io.TextIOWrapper(buf, encoding="gbk", errors="strict", newline="\n")
    logger = _gbk_logger(stream)

    report = [{"severity": "ERROR", "rule_id": "rule.x", "file": "a.py", "lines": "1"}]
    rc = aideepsast.evaluate_quality_gate(report, "WARNING", logger)
    stream.flush()

    assert rc == 1
    assert b"VIOLATION" in buf.getvalue()


def test_quality_gate_pass_message_is_gbk_safe():
    buf = io.BytesIO()
    stream = io.TextIOWrapper(buf, encoding="gbk", errors="strict", newline="\n")
    logger = _gbk_logger(stream)

    report = [{"severity": "INFO", "rule_id": "rule.y", "file": "b.py", "lines": "2"}]
    rc = aideepsast.evaluate_quality_gate(report, "ERROR", logger)
    stream.flush()

    assert rc == 0
    assert b"Quality gate PASSED" in buf.getvalue()
