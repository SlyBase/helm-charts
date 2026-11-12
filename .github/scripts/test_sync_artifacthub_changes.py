#!/usr/bin/env python3
"""Self-check for sync-artifacthub-changes.py (stdlib only, no framework).

Run: python3 .github/scripts/test_sync_artifacthub_changes.py
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

_SCRIPT = Path(__file__).with_name("sync-artifacthub-changes.py")
_spec = importlib.util.spec_from_file_location("sync_artifacthub_changes", _SCRIPT)
assert _spec is not None and _spec.loader is not None
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)


def chart(images_tag: str) -> str:
    """A minimal Chart.yaml whose images annotation pins apache-exporter."""
    return (
        "apiVersion: v2\n"
        "name: wordpress\n"
        "version: 5.5.69\n"
        "appVersion: 7.0.1\n"
        "annotations:\n"
        "  artifacthub.io/changes: |\n"
        "    - kind: fixed\n"
        '      description: "deps: update apache-exporter to v1.1.3"\n'
        "  artifacthub.io/images: |\n"
        "    - name: metrics-apache\n"
        f"      image: docker.io/lusotycoon/apache-exporter:{images_tag}\n"
        "    - name: mariadb\n"
        "      image: docker.io/mariadb:12.3.3-noble\n"
    )


def test_sync_images_restores_reverted_block():
    # release-please rewrote Chart.yaml from a stale snapshot: images reverted
    # to v1.1.2 while main (the reference) already carries v1.1.3.
    stale = chart("v1.1.2")
    main = chart("v1.1.3")
    result = mod.sync_images_annotation(stale, main)
    assert "apache-exporter:v1.1.3" in result, result
    assert "apache-exporter:v1.1.2" not in result, result
    # Only images is touched: version, appVersion and changes stay intact.
    assert "version: 5.5.69" in result
    assert "appVersion: 7.0.1" in result
    assert 'description: "deps: update apache-exporter to v1.1.3"' in result


def test_extract_annotation_block_absent_returns_none():
    assert mod.extract_annotation_block(chart("v1.1.3"), "artifacthub.io/nope") is None


def test_sync_images_noop_when_reference_has_no_images():
    stale = chart("v1.1.2")
    reference = "apiVersion: v2\nname: wordpress\nversion: 5.5.69\n"
    assert mod.sync_images_annotation(stale, reference) == stale


def test_sync_images_idempotent_when_already_current():
    current = chart("v1.1.3")
    assert mod.sync_images_annotation(current, current) == current


def _run_main(images_tag: str, changelog: str) -> str:
    """Run main() on a temp chart with a current-main reference; return Chart.yaml."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        chart_dir = root / "chart"
        chart_dir.mkdir()
        (chart_dir / "Chart.yaml").write_text(chart(images_tag), encoding="utf8")
        (chart_dir / "CHANGELOG.md").write_text(changelog, encoding="utf8")
        reference = root / "main-Chart.yaml"
        reference.write_text(chart("v1.1.3"), encoding="utf8")
        argv = sys.argv
        sys.argv = ["prog", "--chart-dir", str(chart_dir), "--images-from", str(reference)]
        try:
            assert mod.main() == 0
        finally:
            sys.argv = argv
        return (chart_dir / "Chart.yaml").read_text(encoding="utf8")


def test_main_restores_images_with_changelog_entries():
    changelog = (
        "# Changelog\n\n"
        "## [5.5.69](https://example.com) (2026-11-05)\n\n"
        "### Bug Fixes\n\n"
        "* **deps:** update apache-exporter to v1.1.3 ([#862](https://example.com/862))\n"
    )
    out = _run_main("v1.1.2", changelog)
    assert "apache-exporter:v1.1.3" in out, out
    assert "apache-exporter:v1.1.2" not in out, out


def test_main_restores_images_without_changelog_entries():
    changelog = (
        "# Changelog\n\n"
        "## [5.5.68](https://example.com) (2026-11-01)\n\n"
        "### Bug Fixes\n\n"
        "* older entry\n"
    )
    out = _run_main("v1.1.2", changelog)
    assert "apache-exporter:v1.1.3" in out, out
    assert "apache-exporter:v1.1.2" not in out, out


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"ok  {t.__name__}")
    print(f"{len(tests)} passed")
