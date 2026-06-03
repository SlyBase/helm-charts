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

It does **not** touch `version`, `appVersion` or `artifacthub.io/images` — those
are owned by release-please (`version`) and Renovate (`appVersion`, `images`).

Arguments:
- `--chart-dir` — path to the chart directory, e.g. `charts/wordpress`

Usage:

```bash
python3 .github/scripts/sync-artifacthub-changes.py --chart-dir charts/wordpress
```
