"""Encoding regression: rule loaders must read UTF-8 files regardless of locale.

On a zh-CN Windows host Python's default text encoding is GBK. The CodeGuard
rule pack (config/codeguard/*.md) contains non-ASCII characters, so opening it
without an explicit encoding raised UnicodeDecodeError and broke deep scans.
"""

from asvs_loader import ASVSLoader
from codeguard_loader import CodeGuardLoader


def test_codeguard_loader_reads_rules_regardless_of_locale():
    loader = CodeGuardLoader()
    count = loader.load()
    assert count > 0, "CodeGuard rule pack failed to load"
    assert loader.is_loaded


def test_asvs_loader_reads_rules_regardless_of_locale():
    loader = ASVSLoader()
    count = loader.load()
    assert count > 0, "ASVS rule pack failed to load"


def test_codeguard_loader_roundtrips_non_ascii_rule_file(tmp_path):
    """A rule file containing non-ASCII text must load on a GBK-default host."""
    (tmp_path / "codeguard-9-unicode.md").write_text(
        "# Unicode rule\n\nEm dash \u2014 accents \u00e9\u00e8 and CJK \u4e2d\u6587.\n",
        encoding="utf-8",
    )

    loader = CodeGuardLoader(rules_dir=str(tmp_path))
    assert loader.load() == 1
    assert loader.is_loaded
