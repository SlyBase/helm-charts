# Changelog

All notable changes to this chart are documented here.

## 0.9.1 - 2026-05-21

- Fix schema validation failure when chart is used as a Helm dependency: added `global` property to `values.schema.json` so Helm's automatic global values injection no longer conflicts with `additionalProperties: false` at the root level

## 0.9.0 - 2026-05-18

- Update ghcr.io/wg-easy/wg-easy to 15.3.0

## 0.8.0 - 2026-05-18

- Update ghcr.io/wg-easy/wg-easy to 15.3.0

## 0.7.0 - 2026-05-18

- Update ghcr.io/wg-easy/wg-easy to 15.3.0

## 0.6.3 - 2026-03-12

- Fixed runtimeClassName value to be an empty string instead of an empty object

## 0.6.2 - 2026-02-26

- Update ghcr.io/wg-easy/wg-easy
- Pull Request: https://github.com/slydlake/helm-charts/pull/117

## 0.3.0 - 2026-02-04

- Registry value added. Added functionality to _helpers.tpl to support it.
- Better comments for documentation in values.yaml.
- Added missing values in values.schema.yaml.

## 0.2.1 - 2025-11-27

- Provided better samples for the first start. Readme help a lot more for first installation.

## 0.1.20 - 2025-10-27

- readme info about decrepation of helm chart releases, use OCI registry instead.

## 0.1.19 - 2025-10-12

- Pinned chart version

## 0.1.18 - 2025-09-24

- Pin image tag to 15.1.0 with digest for better security
- Image digest for better security
- securityContext to privileged true

## 0.1.16 - 2025-09-18

- externalIPs in values.yaml

## 0.1.7 - 2025-09-16

- changed to MIT license

## 0.1.6 - 2025-08-30

- externalIPs in service type LoadBalancer. Thanks to b4u-mw
- service name in ingress. Thanks to b4u-mw
- No force of storageClass or existingClaim (by using default class)
- hostNetwork
- updateStrategy naming in template

## 0.1.5 - 2025-08-30

- values schema required fields

## 0.1.3 - 2025-08-24

- Updated values schema required fields

## 0.1.1 - 2025-08-19

- Added values schema

## 0.1.0 - 2025-08-19

- Initial release of wg-easy chart.
