# Changelog

All notable changes to this chart are documented here.

## 0.4.10 - 2026-05-14

- Update docker.io/linuxserver/wireguard to 1.0.20250521-r1-ls112

## 0.4.9 - 2026-05-07

- Update docker.io/linuxserver/wireguard to 1.0.20250521-r1-ls111

## 0.4.8 - 2026-04-24

- Update docker.io/linuxserver/wireguard to 1.0.20250521-r1-ls110

## 0.4.7 - 2026-04-16

- Update docker.io/linuxserver/wireguard to 1.0.20250521-r1-ls109

## 0.4.6 - 2026-04-09

- Update docker.io/linuxserver/wireguard to 1.0.20250521-r1-ls108

## 0.4.5 - 2026-04-03

- Update docker.io/linuxserver/wireguard to 1.0.20250521-r1-ls107

## 0.4.4 - 2026-03-29

- Update docker.io/linuxserver/wireguard to 1.0.20250521-r1-ls106

## 0.4.3 - 2026-03-12

- Update [docker.io/linuxserver/wireguard](https://redirect.github.com/linuxserver/docker-wireguard/packages) ([source](https://redirect.github.com/linuxserver/docker-wireguard)) to 1.0.20250521-r1-ls105
- Pull Request: https://github.com/slydlake/helm-charts/pull/211

## 0.4.2 - 2026-03-12

- Update dependencies
- Pull Request: https://github.com/slydlake/helm-charts/pull/158

## 0.4.1 - 2026-02-26

- Update docker.io/linuxserver/wireguard to 1.0.20250521-r1-ls103
- Pull Request: https://github.com/slydlake/helm-charts/pull/147

## 0.4.0 - 2026-02-16

- runtimeClassName added. Thanks to Crypt0s
- Pull Request: https://github.com/slydlake/helm-charts/pull/126

## 0.3.7 - 2026-02-13

- Update docker.io/linuxserver/wireguard to ([source](https://redirect.github.com/linuxserver/docker-wireguard))
- Pull Request: https://github.com/slydlake/helm-charts/pull/125

## 0.3.6 - 2026-02-13

- Update docker.io/linuxserver/wireguard to ([source](https://redirect.github.com/linuxserver/docker-wireguard))
- Pull Request: https://github.com/slydlake/helm-charts/pull/122

## 0.3.2 - 2026-02-04

- Update docker.io/linuxserver/wireguard to ([source](https://redirect.github.com/linuxserver/docker-wireguard))
- Pull Request: https://github.com/slydlake/helm-charts/pull/103

## 0.3.1 - 2025-12-15

- Update docker.io/linuxserver/wireguard to 1.0.20250521-r0-ls93
- Update linuxserver/wireguard to 1.0.20250521-r0-ls93
- Pull Request: https://github.com/slydlake/helm-charts/pull/90

## 0.3.0 - 2025-12-04

- Registry value added. Added functionality to _helpers.tpl to support it.
- Better comments for documentation in values.yaml.
- Added missing values in values.schema.yaml.

## 0.2.6 - 2025-11-27

- Update linuxserver/wireguard to 1.0.20250521-r0-ls92
- Pull Request: https://github.com/slydlake/helm-charts/pull/80

## 0.2.5 - 2025-11-20

- Update linuxserver/wireguard to 1.0.20250521-r0-ls91
- Pull Request: https://github.com/slydlake/helm-charts/pull/78

## 0.2.4 - 2025-11-18

- Client mode with existingSecret now automatically updates when source secret changes (helm upgrade or GitOps reconcile).

## 0.2.3 - 2025-11-08

- Fixed 'imagePullSecrets' schema to expect array of objects instead of strings (thanks @ScionOfDesign)
- Provided better samples for the first start. Readme help a lot more for first installation.
- Pull Request: https://github.com/slydlake/helm-charts/pull/64

## 0.2.2 - 2025-10-30

- Provided better samples for the first start. Readme help a lot more for first installation.

## 0.2.1 - 2025-10-27

- Update linuxserver/wireguard:1.0.20250521-r0-ls90 to Docker digest 394cc11
- Pull Request: https://github.com/slydlake/helm-charts/pull/54

## 0.2.0 - 2025-10-27

- refactor: removed .digest values from image definitions for CI pipeline compatibility. Use image tags with digests instead.

## 0.1.22 - 2025-10-23

- chore(deps): update linuxserver/wireguard docker tag to v1.0.20250521-r0-ls90
- Pull Request: https://github.com/slydlake/helm-charts/pull/37

## 0.1.21 - 2025-10-17

- chore(deps): update linuxserver/wireguard docker tag to v1.0.20250521-r0-ls89
- Pull Request: https://github.com/slydlake/helm-charts/pull/34

## 0.1.20 - 2025-10-12

- readme info about decrepation of helm chart releases, use OCI registry instead.

## 0.1.19 - 2025-10-12

- Fixed schema validation: securityContext and podSecurityContext now allow all Kubernetes fields (e.g., sysctls).

## 0.1.18 - 2025-10-12

- PUID and PGID provided now as string.

## 0.1.17 - 2025-10-11

- Pinned wireguard version to schema 1.0.20250521-r0-ls88

## 0.1.16 - 2025-10-11

- Pinned wireguard version to schema 1.0.20250521-r0-ls88

## 0.1.15 - 2025-09-24

- Digest field for the image to improve security
- Pinned appVersion and image to 1.0.20250521
- PUID and PGID environment variables set to .Values.wireguard.PUID and .Values.wireguard.PGID
- Security context improvements for minimal privilege principle
- Sample values files moved to samples/ directory

## 0.1.14 - 2025-09-24

- Digest field for the image to improve security
- Pinned appVersion and image to 1.0.20250521
- PUID and PGID environment variables set to .Values.wireguard.PUID and .Values.wireguard.PGID
- Security context improvements for minimal privilege principle
- Sample values files moved to samples/ directory

## 0.1.13 - 2025-09-16

- changed to MIT license
- Formating of values.yaml

## 0.1.12 - 2025-08-30

- No force of storageClass or existingClaim (by using default class)
- hostNetwork

## 0.1.11 - 2025-08-25

- values schema required fields

## 0.1.10 - 2025-08-24

- New values for client: preUp, postUp, preDown, postDown

## 0.1.9 - 2025-08-23

- New values: dnsPolicy, dnsConfig, initContainers support, sidecar support

## 0.1.8 - 2025-08-19

- values schema, added enum types

## 0.1.7 - 2025-08-19

- updated sample yaml files values.client.test.yaml and values.server.test.yaml
- updated readme
- sample secret file into repo

## 0.1.6 - 2025-08-16

- Release 0.1.6

## 0.1.5 - 2025-08-16

- Release 0.1.5

## 0.1.4 - 2025-08-16

- Release 0.1.4

## 0.1.3 - 2025-08-16

- Release 0.1.3

## 0.1.2 - 2025-08-16

- Release 0.1.2

## 0.1.1 - 2025-08-16

- Release 0.1.1

## 0.1.0 - 2025-08-16

- Release 0.1.0
