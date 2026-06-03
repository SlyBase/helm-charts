#!/usr/bin/env python3
"""Sync the ``artifacthub.io/changes`` annotation in Chart.yaml from CHANGELOG.md.

This is the bridge between release-please (the single source of truth for the
chart version + human changelog) and ArtifactHub. release-please bumps
``version:`` in Chart.yaml (via extra-files) and generates the top CHANGELOG.md
section for the new release. This script reads that top section and renders the
matching ``artifacthub.io/changes`` block, so the changelog only has to be
maintained in one place.

It also keeps the ``artifacthub.io/prerelease`` annotation in sync with the
chart version (set when the version carries an -alpha/-beta/-rc suffix).

The ``artifacthub.io/images`` annotation is NOT touched here; it is maintained
directly by Renovate's custom.regex manager.

Usage:
    sync-artifacthub-changes.py --chart-dir charts/wordpress
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# release-please changelog section heading -> ArtifactHub change kind.
# ArtifactHub kinds: added, changed, deprecated, removed, fixed, security.
SECTION_KIND_MAP = {
    "features": "added",
    "bug fixes": "fixed",
    "dependencies": "changed",
    "performance improvements": "changed",
    "reverts": "changed",
    "documentation": "changed",
    "miscellaneous chores": "changed",
}
DEFAULT_KIND = "changed"


def main() -> int:
    args = parse_args()

    chart_dir = Path(args.chart_dir)
    chart_file_path = chart_dir / "Chart.yaml"
    changelog_path = chart_dir / "CHANGELOG.md"

    if not chart_file_path.exists():
        print(f"skip: no Chart.yaml in {chart_dir}", file=sys.stderr)
        return 0
    if not changelog_path.exists():
        print(f"skip: no CHANGELOG.md in {chart_dir}", file=sys.stderr)
        return 0

    version = read_current_version(chart_file_path)
    changes = parse_top_changelog_entry(changelog_path.read_text(encoding="utf8"), version)

    if not changes:
        print(
            f"warning: no changelog entries found for {chart_dir.name} {version}; "
            "leaving artifacthub.io/changes untouched",
            file=sys.stderr,
        )
        # Still keep the prerelease annotation consistent with the version.
        content = chart_file_path.read_text(encoding="utf8")
        content = sync_prerelease_annotation(content, is_prerelease_version(version))
        chart_file_path.write_text(content, encoding="utf8")
        return 0

    content = chart_file_path.read_text(encoding="utf8")
    content = replace_annotation_block(
        content,
        "artifacthub.io/changes",
        build_artifacthub_changes_block(changes),
        block_scalar=True,
    )
    content = sync_prerelease_annotation(content, is_prerelease_version(version))
    chart_file_path.write_text(content, encoding="utf8")

    print(f"synced {len(changes)} change entr{'y' if len(changes) == 1 else 'ies'} for {chart_dir.name} {version}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chart-dir", required=True, help="Path to the chart directory, e.g. charts/wordpress")
    return parser.parse_args()


def read_current_version(chart_file_path: Path) -> str:
    content = chart_file_path.read_text(encoding="utf8")
    match = re.search(r"^version:\s*(\S+)\s*$", content, flags=re.MULTILINE)
    if not match:
        raise RuntimeError(f"Could not find chart version in {chart_file_path}")
    return match.group(1)


# --- CHANGELOG.md parsing -------------------------------------------------


def parse_top_changelog_entry(changelog: str, version: str) -> list[dict[str, str]]:
    """Return the change entries of the changelog section matching ``version``.

    Handles the release-please ``simple`` format, e.g.::

        ## [4.5.0](https://.../compare/...) (2026-06-03)

        ### Features

        * **deps:** Update docker.io/mariadb to 12.3.0 ([#363](https://...))

    as well as the legacy plain format ``## 4.5.0 - 2026-06-03`` with ``- `` bullets.
    """
    block = extract_version_block(changelog, version)
    if block is None:
        return []

    entries: list[dict[str, str]] = []
    current_kind = DEFAULT_KIND
    for raw_line in block.splitlines():
        line = raw_line.rstrip()
        heading = re.match(r"^#{3,4}\s+(.+?)\s*$", line)
        if heading:
            current_kind = SECTION_KIND_MAP.get(heading.group(1).strip().lower(), DEFAULT_KIND)
            continue

        bullet = re.match(r"^[-*]\s+(.*)$", line.strip())
        if not bullet:
            continue

        description, link = split_description_and_link(bullet.group(1).strip())
        if description:
            entries.append({"kind": current_kind, "description": description, "link": link})

    return entries


def extract_version_block(changelog: str, version: str) -> str | None:
    """Slice the changelog text belonging to the ``## <version>`` heading."""
    lines = changelog.splitlines()
    start: int | None = None
    escaped = re.escape(version)
    # Matches "## [4.5.0]..." (release-please) and "## 4.5.0 - ..." (legacy).
    heading_re = re.compile(rf"^##\s+\[?{escaped}\]?[\s\)\(.-]")

    for index, line in enumerate(lines):
        if heading_re.match(line):
            start = index + 1
            break
    if start is None:
        return None

    end = len(lines)
    for index in range(start, len(lines)):
        if re.match(r"^##\s+", lines[index]):
            end = index
            break
    return "\n".join(lines[start:end]).strip()


def split_description_and_link(text: str) -> tuple[str, str]:
    """Strip a trailing markdown link ``([name](url))`` and return (description, url)."""
    link = ""
    match = re.search(r"\(\[[^\]]+\]\((?P<url>[^)]+)\)\)\s*$", text)
    if match:
        link = match.group("url").strip()
        text = text[: match.start()].rstrip()
    # Drop a bare trailing markdown link without surrounding parens, just in case.
    text = re.sub(r"\s*\(\[[^\]]+\]\([^)]+\)\)\s*$", "", text).strip()
    # Strip markdown bold markers (release-please renders the commit scope as
    # "**deps:** ..."); ArtifactHub shows the description as plain text.
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text).strip()
    return text, link


# --- Chart.yaml annotation helpers (shared logic) -------------------------


def build_artifacthub_changes_block(changes: list[dict[str, str]]) -> str:
    lines: list[str] = []
    for change in changes:
        escaped_description = change["description"].replace('"', '\\"')
        lines.append(f"- kind: {change['kind']}")
        lines.append(f'  description: "{escaped_description}"')
        if change.get("link"):
            lines.append("  links:")
            lines.append("    - name: GitHub")
            lines.append(f"      url: {change['link']}")
    return "\n".join(lines)


def sync_prerelease_annotation(content: str, is_prerelease: bool) -> str:
    key = "artifacthub.io/prerelease"
    if is_prerelease:
        return replace_annotation_block(content, key, '"true"', block_scalar=False)
    return remove_annotation(content, key)


def replace_annotation_block(content: str, key: str, value: str, *, block_scalar: bool) -> str:
    lines = content.splitlines()
    annotations_start, annotations_end = ensure_annotations_section(lines)
    entry_start, entry_end = find_annotation_entry(lines, annotations_start, annotations_end, key)

    if block_scalar:
        new_entry = [f"  {key}: |", *[f"    {line}" for line in value.splitlines()]]
    else:
        new_entry = [f"  {key}: {value}"]

    if entry_start is None:
        insert_at = annotations_end
        lines[insert_at:insert_at] = new_entry
    else:
        lines[entry_start:entry_end] = new_entry

    return "\n".join(lines) + "\n"


def remove_annotation(content: str, key: str) -> str:
    lines = content.splitlines()
    annotations_bounds = find_annotations_section(lines)
    if annotations_bounds is None:
        return content

    annotations_start, annotations_end = annotations_bounds
    entry_start, entry_end = find_annotation_entry(lines, annotations_start, annotations_end, key)
    if entry_start is None:
        return content

    del lines[entry_start:entry_end]
    return "\n".join(lines) + "\n"


def ensure_annotations_section(lines: list[str]) -> tuple[int, int]:
    bounds = find_annotations_section(lines)
    if bounds is not None:
        return bounds

    insert_at = len(lines)
    for index, line in enumerate(lines):
        if re.match(r"^(keywords|dependencies):", line):
            insert_at = index
            break

    lines[insert_at:insert_at] = ["annotations:"]
    return find_annotations_section(lines)  # type: ignore[return-value]


def find_annotations_section(lines: list[str]) -> tuple[int, int] | None:
    for start_index, line in enumerate(lines):
        if line == "annotations:":
            end_index = start_index + 1
            while end_index < len(lines):
                current = lines[end_index]
                if current.startswith("  ") or current == "":
                    end_index += 1
                    continue
                break
            return start_index + 1, end_index
    return None


def find_annotation_entry(
    lines: list[str], annotations_start: int, annotations_end: int, key: str
) -> tuple[int | None, int | None]:
    prefix = f"  {key}:"
    for index in range(annotations_start, annotations_end):
        if not lines[index].startswith(prefix):
            continue

        end_index = index + 1
        while end_index < annotations_end:
            current = lines[end_index]
            if current.startswith("    ") or current == "":
                end_index += 1
                continue
            break
        return index, end_index

    return None, None


def is_prerelease_version(version: str) -> bool:
    return re.search(r"-(alpha|beta|rc)(?:\.|\d|$)", version, flags=re.IGNORECASE) is not None


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # pragma: no cover
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
