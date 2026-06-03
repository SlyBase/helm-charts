# helm-charts

Collection of signed Helm charts for self-hosted apps. Each chart lives under `charts/<chart>/` with its own `Chart.yaml`, `values.yaml`, `values.schema.json`, `templates/`, and `samples/`.

Charts are distributed via OCI (`ghcr.io/slybase/charts`) and signed with Cosign — see [README-SIGNING.md](README-SIGNING.md).

## Chart structure

- `charts/<chart>/Chart.yaml` — version, appVersion, ArtifactHub annotations (`artifacthub.io/changes`)
- `charts/<chart>/values.yaml` + `values.schema.json` — changes to `values.yaml` must always be reflected in `values.schema.json` (new fields, type changes, removed fields)
- `charts/<chart>/templates/` — Deployment/StatefulSet, Service, Ingress, HPA, PVC, ServiceMonitor
- `charts/<chart>/samples/` — sample values used for installs and doc examples; update alongside template/value changes
- `charts/<chart>/CHANGELOG.md` — human-readable release history

## Release & versioning workflow

Releases are driven by **release-please** + **git tags**, not by hand-editing `version:` in `Chart.yaml`.

1. **Renovate** opens PRs with dependency bumps as conventional commits. The commit type encodes the chart bump (see `renovate.json` packageRules):
   - subchart (`helmv3`) major → `feat` (chart **minor**); subchart minor/patch/digest → `fix` (chart **patch**)
   - direct dep (`helm-values`/`custom.regex`) major → `feat!` breaking (chart **major**); minor → `feat`; patch/digest → `fix`
   - Renovate edits `appVersion` / `artifacthub.io/images` / subchart versions directly, but does **not** touch `version:`.
2. **release-please** (`.github/workflows/release-please.yml`, config `release-please-config.json` + `.release-please-manifest.json`) keeps one release PR per chart, bumping `Chart.yaml:version` (via `extra-files`) and generating `CHANGELOG.md`.
3. A bridge step runs `.github/scripts/sync-artifacthub-changes.py` on the release PR to derive the `artifacthub.io/changes` (+ `artifacthub.io/prerelease`) annotation from the new CHANGELOG entry — single source of truth.
4. Merging a release PR creates a per-chart tag (`<chart>-v<version>`, e.g. `wordpress-v4.5.0`) + GitHub Release, which triggers `oci-release.yaml` to package, push, Cosign-sign and upload ArtifactHub metadata.

Feature PRs use conventional commits (`feat:`/`fix:`/`feat!:`) the same way to drive their chart's bump. PR validation (lint/template) lives in `pr-chart-validate.yml`.

## WordPress chart

The most complex chart — uses init containers and ConfigMaps/Secrets for plugins, themes, MU-plugins, and custom init scripts. Integrates with MariaDB (subchart or external), Memcached, and Prometheus exporters. See [charts/wordpress/README.md](charts/wordpress/README.md) and [charts/wordpress/samples/](charts/wordpress/samples/).

**Workload controller (`controllerType`):** the chart renders either a Deployment or a StatefulSet:

- `controllerType: deployment` (default, backwards-compatible) — single shared PVC (`pvc.yaml`), suitable for `replicaCount: 1` or RWX storage.
- `controllerType: statefulset` — each replica gets its own ReadWriteOnce volume via `volumeClaimTemplates` (true HA without an RWX share-manager SPOF). Adds a headless Service and `statefulset.*` tunables (`podManagementPolicy`, `updateStrategy`, `persistentVolumeClaimRetentionPolicy`). `storage.existingClaim` is not supported here.

The Pod spec is shared between both controllers via the `wordpress.podTemplate` partial in [templates/_pod.tpl](charts/wordpress/templates/_pod.tpl) — **edit pod-level changes there, not in `deployment.yaml`/`statefulset.yaml`** (those only hold controller-level fields). After editing `_pod.tpl`, confirm the Deployment render is unchanged with a `helm template` before/after diff.

**After every change to the WordPress chart, run the verify script before committing:**

```bash
./charts/wordpress/samples/verify/verify.sh
```

This script installs the chart via `install.sh`, waits for all pods (WordPress, MariaDB, Valkey) to become Ready, checks init-container and main-container logs for errors, and runs HTTP + metrics smoke tests. Fix any reported failures before pushing. Clean up afterwards with:

```bash
./charts/wordpress/samples/verify/uninstall.sh
```

## Key files

| Purpose | Path |
|---|---|
| Detect changed charts in CI | `.github/actions/detect-changed-charts/action.yml` |
| Release automation (per-chart) | `.github/workflows/release-please.yml`, `release-please-config.json`, `.release-please-manifest.json` |
| OCI publish on release tag | `.github/workflows/oci-release.yaml` |
| CHANGELOG → ArtifactHub annotation bridge | `.github/scripts/sync-artifacthub-changes.py` |
| Script usage docs | `.github/scripts/README.md` |
| Signing docs | `README-SIGNING.md` |
