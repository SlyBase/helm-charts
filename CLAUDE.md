# helm-charts

Collection of signed Helm charts for self-hosted apps. Each chart lives under `charts/<chart>/` with its own `Chart.yaml`, `values.yaml`, `values.schema.json`, `templates/`, and `samples/`.

Charts are distributed via OCI (`ghcr.io/slybase/charts`) and signed with Cosign — see [README-SIGNING.md](README-SIGNING.md).

## Chart structure

- `charts/<chart>/Chart.yaml` — version, appVersion, ArtifactHub annotations (`artifacthub.io/changes`)
- `charts/<chart>/values.yaml` + `values.schema.json` — changes to `values.yaml` must always be reflected in `values.schema.json` (new fields, type changes, removed fields)
- `charts/<chart>/templates/` — Deployment/StatefulSet, Service, Ingress, HPA, PVC, ServiceMonitor
- `charts/<chart>/samples/` — sample values used for installs and doc examples; update alongside template/value changes
- `charts/<chart>/CHANGELOG.md` — human-readable release history

## Dependency update workflow

1. Renovate opens a PR with dependency bumps (regex updates `appVersion` directly in `Chart.yaml`)
2. Renovate's `postUpgradeTasks` (configured in `renovate.json`) runs `.github/scripts/update-chart-metadata.py` during PR creation
3. That script bumps the chart version, updates `artifacthub.io/changes`, and appends to `CHANGELOG.md`

Local testing helpers: `.github/scripts/README.md` (`test-renovate.sh`, `test-appversion-regex.sh`, `test-renovate-full.sh`)

## WordPress chart

The most complex chart — uses init containers and ConfigMaps/Secrets for plugins, themes, MU-plugins, and custom init scripts. Integrates with MariaDB (subchart or external), Memcached, and Prometheus exporters. See [charts/wordpress/README.md](charts/wordpress/README.md) and [charts/wordpress/samples/](charts/wordpress/samples/).

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
| Post-merge metadata updater | `.github/scripts/update-chart-metadata.py` |
| Script usage docs | `.github/scripts/README.md` |
| Signing docs | `README-SIGNING.md` |
