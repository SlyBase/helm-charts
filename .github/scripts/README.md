# GitHub Scripts

Helper scripts used by the release automation.

## sync-artifacthub-changes.py

Bridges release-please (single source of truth for chart version + CHANGELOG)
to ArtifactHub. Invoked by `.github/workflows/release-please.yml` on each release
PR, after release-please has bumped `Chart.yaml:version` and written the new
`CHANGELOG.md` section.

What it does:
- Reads the top (newest) section of `charts/<chart>/CHANGELOG.md`.
- Renders the matching `artifacthub.io/changes` block in `Chart.yaml`
  (Features → `added`, Bug Fixes → `fixed`, everything else → `changed`),
  including the PR/commit link when present.
- Adds or removes `artifacthub.io/prerelease` based on the chart version suffix
  (`-alpha`/`-beta`/`-rc`).
- With `--images-from`, restores `artifacthub.io/images` verbatim from a
  reference `Chart.yaml` (the current `main`), undoing a release-please rewrite
  from a stale snapshot that would otherwise revert Renovate's image tags.

It does **not** generate `version`, `appVersion` or `artifacthub.io/images` —
those are owned by release-please (`version`) and Renovate (`appVersion`,
`images`). `--images-from` only copies the existing `main` images block back.

Arguments:
- `--chart-dir` — path to the chart directory, e.g. `charts/wordpress`
- `--images-from` — optional reference `Chart.yaml` (e.g. `origin/main`) to
  restore `artifacthub.io/images` from

Usage:

```bash
python3 .github/scripts/sync-artifacthub-changes.py --chart-dir charts/wordpress \
  --images-from /path/to/main/Chart.yaml
```

Self-check (stdlib only, also run by pre-commit):

```bash
python3 .github/scripts/test_sync_artifacthub_changes.py
```
