#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

CHANGELOG_HEADER = "# Changelog\n\nAll notable changes to this chart are documented here.\n\n"
METADATA_COMMIT_PATTERNS = (
    r"^chore: update chart metadata$",
    r"^chore: update chart release metadata$",
)


def main() -> int:
    args = parse_args()

    chart_file_path = Path(args.chart_dir) / "Chart.yaml"
    if not chart_file_path.exists():
        print(json.dumps({"skipped": True, "reason": "no-chart-yaml"}), end="")
        return 0

    if should_skip_metadata_update(args.chart_dir):
        print(json.dumps({"skipped": True, "reason": "metadata-up-to-date"}), end="")
        return 0

    if version_already_bumped_in_session(chart_file_path):
        print(json.dumps({"skipped": True, "reason": "already-bumped-this-session"}), end="")
        return 0

    changelog_path = Path(args.chart_dir) / "CHANGELOG.md"
    current_version = read_current_version(chart_file_path)
    labels = normalise_labels(args.pr_labels)
    bump_type = determine_bump_type_for(args.manager, args.update_type, labels)
    new_version = bump_version(current_version, bump_type)
    ensure_version_increases(current_version, new_version)
    descriptions = normalise_change_descriptions(args.change_descriptions)
    release_channel = "beta" if is_prerelease_version(new_version) or "prerelease" in labels else "stable"
    release_date = dt.datetime.now(dt.UTC).date().isoformat()

    sync_chart_metadata(chart_file_path, new_version, descriptions, args.pr_url)
    update_changelog_file(
        changelog_path,
        {
            "version": new_version,
            "release_date": release_date,
            "descriptions": descriptions,
            "pr_url": args.pr_url,
            "release_channel": release_channel,
        },
    )

    print(
        json.dumps(
            {
                "skipped": False,
                "chart": Path(args.chart_dir).name,
                "bumpType": bump_type,
                "currentVersion": current_version,
                "newVersion": new_version,
            }
        ),
        end="",
    )
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--chart-dir", required=True)
    parser.add_argument("--pr-url", default="")  # optional; absent when called from postUpgradeTasks
    parser.add_argument("--pr-labels", default="")
    parser.add_argument("--change-descriptions", default="")
    parser.add_argument("--manager", default="")  # renovate manager (e.g. helmv3, helm-values)
    parser.add_argument("--update-type", default="")  # patch / minor / major / digest
    return parser.parse_args()


def exec_git(args: list[str], allow_failure: bool = False) -> str:
    result = subprocess.run(
        ["git", *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return result.stdout.rstrip("\n")
    if allow_failure:
        return ""
    stderr = result.stderr.strip() or result.stdout.strip() or "git command failed"
    raise RuntimeError(f"git {' '.join(args)} failed: {stderr}")


def should_skip_metadata_update(chart_dir: str) -> bool:
    log_args = ["log"]
    for pattern in METADATA_COMMIT_PATTERNS:
        log_args.extend(["--grep", pattern])
    log_args.extend(["--format=%H", "-n", "1", "--", chart_dir])

    last_metadata_commit = exec_git(log_args, allow_failure=True)
    if not last_metadata_commit:
        return False

    changed_files = [
        line.strip()
        for line in exec_git(["diff", "--name-only", f"{last_metadata_commit}..HEAD", "--", chart_dir], allow_failure=True).splitlines()
        if line.strip() and not line.strip().endswith("/CHANGELOG.md")
    ]
    return len(changed_files) == 0


def version_already_bumped_in_session(chart_file_path: Path) -> bool:
    """Return True if the chart version was already bumped during this postUpgradeTasks session.

    When executionMode is "update", the script runs once per matched dependency update.
    A single image update can match multiple managers (helm-values, custom.regex for appVersion,
    custom.regex for artifacthub.io/images), causing multiple invocations per PR. Each invocation
    reads the already-modified Chart.yaml and bumps the version again. This guard detects that the
    version line was already changed in the working directory (not yet committed) and skips.
    """
    diff = exec_git(["diff", "HEAD", "--", str(chart_file_path)], allow_failure=True)
    return bool(re.search(r"^\+version:", diff, flags=re.MULTILINE))


def read_current_version(chart_file_path: Path) -> str:
    content = chart_file_path.read_text(encoding="utf8")
    match = re.search(r"^version:\s*(\S+)\s*$", content, flags=re.MULTILINE)
    if not match:
        raise RuntimeError(f"Could not find chart version in {chart_file_path}")
    return match.group(1)


def normalise_labels(raw_labels: str) -> list[str]:
    return [label.strip() for label in str(raw_labels).split(",") if label.strip()]


def normalise_change_descriptions(raw_descriptions: str) -> list[str]:
    descriptions = [line.strip() for line in str(raw_descriptions).splitlines() if line.strip()]
    return descriptions or ["Dependency update"]


def determine_bump_type(labels: list[str]) -> str:
    label_set = set(labels)
    if "subchart-update" in label_set:
        if "chart-bump-minor" in label_set or "chart-bump-major" in label_set or "major" in label_set:
            return "minor"
        return "patch"
    if "chart-bump-major" in label_set or "major" in label_set:
        return "major"
    if "chart-bump-minor" in label_set or "minor" in label_set:
        return "minor"
    return "patch"


def determine_bump_type_for(manager: str, update_type: str, labels: list[str]) -> str:
    """Determine bump type from Renovate manager/updateType (postUpgradeTasks) or labels (legacy)."""
    if manager and update_type:
        # helmv3 = subchart: major dep bump → minor chart bump, everything else → patch
        if manager == "helmv3":
            return "minor" if update_type == "major" else "patch"
        # direct deps (helm-values, custom.regex, github-actions, …)
        if update_type == "major":
            return "major"
        if update_type == "minor":
            return "minor"
        return "patch"
    return determine_bump_type(labels)


def bump_version(version: str, bump_type: str) -> str:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(-.+)?", version.strip())
    if not match:
        raise RuntimeError(f"Unsupported chart version: {version}")

    major, minor, patch = (int(match.group(index)) for index in range(1, 4))
    suffix = match.group(4) or ""

    if bump_type == "major":
        return f"{major + 1}.0.0{suffix}"
    if bump_type == "minor":
        return f"{major}.{minor + 1}.0{suffix}"
    return f"{major}.{minor}.{patch + 1}{suffix}"


def ensure_version_increases(current_version: str, new_version: str) -> None:
    if compare_versions(new_version, current_version) <= 0:
        raise RuntimeError(
            f"Version bump must increase chart version: current={current_version}, new={new_version}"
        )


def compare_versions(left: str, right: str) -> int:
    left_key = version_sort_key(left)
    right_key = version_sort_key(right)
    if left_key < right_key:
        return -1
    if left_key > right_key:
        return 1
    return 0


def version_sort_key(version: str) -> tuple[int, int, int, int, str]:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(-.+)?", version.strip())
    if not match:
        raise RuntimeError(f"Unsupported chart version: {version}")

    major, minor, patch = (int(match.group(index)) for index in range(1, 4))
    suffix = (match.group(4) or "").lstrip("-")
    stable_weight = 1 if not suffix else 0
    return major, minor, patch, stable_weight, suffix


def sync_chart_metadata(chart_file_path: Path, new_version: str, descriptions: list[str], pr_url: str) -> None:
    content = chart_file_path.read_text(encoding="utf8")
    content = replace_version(content, new_version)
    content = sync_chart_image_metadata(chart_file_path.parent, content)
    content = replace_annotation_block(
        content,
        "artifacthub.io/changes",
        build_artifacthub_changes_block(descriptions, pr_url),
        block_scalar=True,
    )
    content = sync_prerelease_annotation(content, is_prerelease_version(new_version))
    chart_file_path.write_text(content, encoding="utf8")


def replace_version(content: str, new_version: str) -> str:
    updated_content, count = re.subn(
        r"^version:\s*.+$",
        f"version: {new_version}",
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise RuntimeError("Could not update chart version")
    return updated_content


def sync_chart_image_metadata(chart_dir: Path, content: str) -> str:
    if chart_dir.name != "wireguard":
        return content

    image_name, image_tag = read_primary_image_from_values(chart_dir / "values.yaml")
    content = replace_app_version(content, image_tag)
    content = replace_annotation_block(
        content,
        "artifacthub.io/images",
        build_artifacthub_images_block("wireguard", f"{image_name}:{image_tag}"),
        block_scalar=True,
    )
    return content


def read_primary_image_from_values(values_path: Path) -> tuple[str, str]:
    values_content = values_path.read_text(encoding="utf8")
    image_block_match = re.search(r"^image:\s*$([\s\S]*?)(?=^\S|\Z)", values_content, flags=re.MULTILINE)
    if not image_block_match:
        raise RuntimeError(f"Could not find image block in {values_path}")

    image_block = image_block_match.group(1)
    registry = read_yaml_scalar(image_block, "registry")
    repository = read_yaml_scalar(image_block, "repository")
    tag_with_digest = read_yaml_scalar(image_block, "tag")
    tag = tag_with_digest.split("@", 1)[0]
    image_name = build_image_name(registry, repository)
    return image_name, tag


def read_yaml_scalar(block: str, key: str) -> str:
    match = re.search(rf"^\s{{2}}{re.escape(key)}:\s*(.+?)\s*$", block, flags=re.MULTILINE)
    if not match:
        raise RuntimeError(f"Could not find {key} in values.yaml image block")
    return strip_wrapping_quotes(match.group(1).strip())


def strip_wrapping_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'\"', "'"}:
        return value[1:-1]
    return value


def build_image_name(registry: str, repository: str) -> str:
    if registry and not repository.startswith(f"{registry}/"):
        return f"{registry}/{repository}"
    return repository


def replace_app_version(content: str, new_app_version: str) -> str:
    pattern = re.compile(
        r"^(appVersion:\s*)(['\"]?)([^'\"\s]+)\2(\s*#\s*renovate:\s*image=[^\s]+.*)$",
        flags=re.MULTILINE,
    )

    def repl(match: re.Match[str]) -> str:
        quote = match.group(2)
        value = f"{quote}{new_app_version}{quote}" if quote else new_app_version
        return f"{match.group(1)}{value}{match.group(4)}"

    updated_content, count = pattern.subn(repl, content, count=1)
    if count != 1:
        raise RuntimeError("Could not update chart appVersion")
    return updated_content


def build_artifacthub_changes_block(descriptions: list[str], pr_url: str) -> str:
    lines: list[str] = []
    for description in descriptions:
        escaped_description = description.replace('"', '\\"')
        lines.append("- kind: changed")
        lines.append(f'  description: "{escaped_description}"')
        if pr_url:
            lines.append("  links:")
            lines.append("    - name: Pull Request")
            lines.append(f"      url: {pr_url}")
    return "\n".join(lines)


def build_artifacthub_images_block(name: str, image: str) -> str:
    return f"- name: {name}\n  image: {image}"


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


def update_changelog_file(changelog_path: Path, entry: dict[str, object]) -> None:
    current_content = changelog_path.read_text(encoding="utf8") if changelog_path.exists() else ""
    version = str(entry["version"])

    if f"## {version} - " in current_content:
        return

    rendered_entry = build_changelog_entry(entry).rstrip()
    body = strip_changelog_header(current_content).strip()
    next_body = f"{rendered_entry}\n\n{body}" if body else rendered_entry
    changelog_path.write_text(f"{CHANGELOG_HEADER}{next_body}\n", encoding="utf8")


def build_changelog_entry(entry: dict[str, object]) -> str:
    lines = [f"## {entry['version']} - {entry['release_date']}", ""]

    for description in entry["descriptions"]:
        lines.append(f"- {description}")

    if entry["pr_url"]:
        lines.append(f"- Pull Request: {entry['pr_url']}")

    if entry["release_channel"] != "stable":
        lines.append(f"- Release channel: {entry['release_channel']}")

    lines.append("")
    return "\n".join(lines)


def strip_changelog_header(content: str) -> str:
    return re.sub(
        r"^# Changelog\s*\n\s*All notable changes to this chart are documented here\.\s*\n*",
        "",
        content,
        count=1,
        flags=re.MULTILINE,
    )


def is_prerelease_version(version: str) -> bool:
    return re.search(r"-(alpha|beta|rc)(?:\.|\d|$)", version, flags=re.IGNORECASE) is not None


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # pragma: no cover
        print(str(error), file=sys.stderr)
        raise SystemExit(1)