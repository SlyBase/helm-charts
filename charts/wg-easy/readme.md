# wg-easy - A WireGuard Server with a Web-UI for Kubernetes

## Introduction
[wg-easy](https://github.com/wg-easy/wg-easy) is the easiest way to run a WireGuard VPN with a Web-based Admin UI.

> **Note:** Soon only OCI registries will be supported. Please migrate to this OCI-based installation method shown below.


## TL;DR

You can find sample YAML files in the GitHub repo in the subfolder "samples".

> **Note:** By default, the init mode (config.init.enabled) is turned on. So you have to set up the values correctly or disable it.

```yaml
# ./samples/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: wg-easy
  labels:
    pod-security.kubernetes.io/enforce: privileged
```

```yaml
# ./samples/simple.values.yaml
config:
  init:
    enabled: false
service:
  ui:
    nodePort: 30201 # port for the UI (browser)
  wireguard:
    nodePort: 30200 # port for the wireguard server (to open in firewall)
```

Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
helm install wgeasy oci://ghcr.io/slybase/charts/wg-easy --values ./samples/simple.values.yaml -n wg-easy
```


## Prerequisites

You have to set a namespace with privileged security (see sample namespace.yaml) or you can create it with:
```bash
kubectl create namespace wg-easy && kubectl label namespace wg-easy pod-security.kubernetes.io/enforce=privileged pod-security.kubernetes.io/warn=privileged --overwrite
```

## Security

By default the container runs `privileged: true` with the `NET_ADMIN` and `SYS_MODULE` capabilities. This is required by the [wg-easy](https://github.com/wg-easy/wg-easy) image to create the `wg0` interface and, if not already present on the host, to load the WireGuard kernel module.

As a result:
- `pod-security.kubernetes.io/enforce: privileged` is required on the namespace (see Prerequisites)
- the chart **cannot** meet the `restricted` or `baseline` Pod Security Standard with the default `securityContext`

What the chart hardens by default regardless:
- `seccompProfile: RuntimeDefault` for the pod and the container
- `serviceAccount.automount: false` — the chart never talks to the Kubernetes API

If the WireGuard kernel module is already loaded on every host node, you can try running without `privileged: true` using `capabilities: {add: [NET_ADMIN, SYS_MODULE], drop: [ALL]}` instead - see the commented example in `values.yaml`. This is untested and not the default.

## Initialization Mode and Metrics

To provide the secrets and values to set up init mode correctly and optionally enable the Prometheus metrics.

```yaml
# ./samples/advanced.secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: wg-metrics
  namespace: wg-easy
data:
  token: <token in Base64> # this is the token for the metrics
---
apiVersion: v1
kind: Secret
metadata:
  name: wg-secret
  namespace: wg-easy
data:
  password: <password in Base64>
  username: <username in Base64>
type: Opaque
```
> **Note:** The initial username and password is not checked for complexity. Make sure to set a long enough username and password. Otherwise, the user won't be able to log in.

> **Note:** You have to enable the Prometheus metrics in the Web UI manually and copy this token as plain text (not Base64) in the UI. This can't be done automatically. The secret here is used for the serviceMonitor, for Prometheus autodetection.

```yaml
# ./samples/advanced.values.yaml
config:
  init:
    existingSecret: "wg-secret"
    host: "vpn.example.com"
serviceMonitor:
  create: true
  existingSecret: "wg-metrics"
  existingSecretKey: "token"
service:
  ui:
    nodePort: 30201
  wireguard:
    nodePort: 30200

```

Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
kubectl apply -f ./samples/advanced.secrets.yaml
helm install wgeasy oci://ghcr.io/slybase/charts/wg-easy --values ./samples/advanced.values.yaml -n wg-easy
```

## Advanced Configuration

### Common Labels and Annotations

`commonLabels` and `commonAnnotations` are applied to every resource created by this chart (StatefulSet, Services, PVC, ServiceAccount, NetworkPolicy, ...). Useful for GitOps (ArgoCD), cost allocation, and audit. See `samples/commonLabels.values.yaml` for an example.

### NetworkPolicy

The chart can create a `NetworkPolicy` to restrict traffic to/from the wg-easy pod (disabled by default via `networkPolicy.enabled: false`):

- **Ingress**: allows UDP traffic to the WireGuard port (`service.wireguard.port`) and TCP traffic to the Web UI/metrics port (`service.ui.port`). By default, traffic is allowed from anywhere; restrict it with `networkPolicy.ingress.from`.
- **Egress**: always allows DNS lookups to `kube-system`. `networkPolicy.allowExternalEgress` (default `true`) additionally allows UDP egress to `0.0.0.0/0`, required for peer connectivity.
- `networkPolicy.ingress.extraRules` / `networkPolicy.egress.extraRules` allow appending raw NetworkPolicy rule blocks.

See `samples/networkpolicy.values.yaml` for an example.

### Pod Disruption Budget

Set `podDisruptionBudget.minAvailable` or `podDisruptionBudget.maxUnavailable` to create a `PodDisruptionBudget` for the StatefulSet. Empty (default) disables it.

### Topology Spread Constraints and Priority Class

`topologySpreadConstraints` and `priorityClassName` are passed through to the pod spec for advanced scheduling control.

## Known Issues

### CrashLoopBackOff on nftables-only kernels (e.g. Talos Linux)

The wg-easy v15 image bundles `wg-quick`, which shells out to **iptables-legacy** to set up NAT/forwarding (`iptables -t nat -A POSTROUTING ...`). On hosts whose kernel does not provide the legacy `ip_tables`/`iptable_nat` modules and only supports nftables (e.g. Talos Linux, Debian 13+, recent Raspberry Pi/Ubuntu kernels), this fails with:

```
modprobe: FATAL: Module ip_tables not found in directory /lib/modules/<kernel>
iptables v1.8.11 (legacy): can't initialize iptables table `nat': Table does not exist (do you need to insmod?)
```

As a result, `wg0` never comes up, the startup probe fails, and the pod CrashLoopBackOffs.

This is an upstream limitation of the wg-easy v15 image (tracked in [wg-easy/wg-easy#2220](https://github.com/wg-easy/wg-easy/issues/2220)), not specific to this chart — there is currently no chart-level workaround. If your nodes only support nftables, wg-easy v15 will not run until upstream addresses this.
