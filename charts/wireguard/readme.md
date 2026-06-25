# WireGuard - Server and Client for Kubernetes

## Introduction
[WireGuard®](https://github.com/linuxserver/docker-wireguard) is an extremely simple yet fast and modern VPN that utilizes state-of-the-art cryptography.

> **Note:** Soon only OCI registries will be supported. Please migrate to this OCI-based installation method shown below.

## TL;DR

You can find different sample YAML files (server, client, client with full wg0.conf configuration) in the GitHub repo in the subfolder "samples".

> **Note:** You have to enable the server or client mode in the values wireguard.server.enable = true or wireguard.client.enable = true. By default it is false.

```yaml
# ./samples/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: wireguard
  labels:
    pod-security.kubernetes.io/enforce: privileged
```

```yaml
# ./samples/server.values.yaml
wireguard:
  timezone: "Europe/Berlin"
  server:
    enabled: true
    config:
      address: vpn.example.com
      peers: "macbook1,iphone1"
```


Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
helm install wireguard oci://ghcr.io/slybase/charts/wireguard --values ./samples/server.values.yaml -n wireguard
```

## Prerequisites

You have to set a namespace with privileged security (see sample namespace.yaml) or you can create it with:
```bash
kubectl create namespace wireguard && kubectl label namespace wireguard pod-security.kubernetes.io/enforce=privileged --overwrite
```

## Security

By default the container runs as `root` (`runAsUser: 0`) with the `NET_ADMIN` capability but **without** `privileged: true`. The broad privileged flag (which grants *all* capabilities plus device access and `SYS_ADMIN`) is intentionally dropped: the underlying [linuxserver/wireguard](https://github.com/linuxserver/docker-wireguard) image runs an s6-overlay init that only needs the container's **default** capability set (`SETUID`/`SETGID`/`CHOWN`/…) to start, plus `NET_ADMIN` for `wg-quick` (interface creation and, in server mode, routing/NAT). The chart keeps those defaults and adds only `NET_ADMIN` — verified working for server mode.

Because of the s6-overlay init:
- `allowPrivilegeEscalation: true` **is** required (the s6 `suexec` step needs it); without it the container crashes with `s6-overlay-suexec: fatal: unable to setgid to root`
- the container's default capability set is kept (the chart does **not** `drop: [ALL]`), so `pod-security.kubernetes.io/enforce: privileged` is still required on the namespace (see Prerequisites) and the chart cannot meet the `restricted`/`baseline` Pod Security Standard

What the chart hardens by default:
- **`privileged: false`** — the broad privileged flag is no longer set (this is the v2.0.0 default; see [Notable changes](#notable-changes))
- `seccompProfile: RuntimeDefault` for the pod and the container
- `serviceAccount.automount: false` — the chart never talks to the Kubernetes API

**Kernel module:** most modern kernels (and Talos) already provide the WireGuard module, so the chart does **not** add `SYS_MODULE` by default. If `wg0` fails to come up because the module is missing, set `wireguard.loadKernelModule: true` to add the `SYS_MODULE` capability.

> **Full-tunnel client note:** a CLIENT with `AllowedIPs: 0.0.0.0/0` uses fwmark policy routing, which may require allow-listing the `net.ipv4.conf.all.src_valid_mark` sysctl on your nodes (or running `privileged`). Override `securityContext` if your setup needs it.

To override these defaults completely, set `securityContext` in your values (see the commented example in `values.yaml`).

## Server mode
Sample see in TL;DR.

### Bonus
Output the created peer configurations. Just replace the "namespace" and "releasename" with your values.
```bash
export namespace=wireguard
export releasename=server

export POD=$(kubectl -n $namespace get pods -l "app.kubernetes.io/name=wireguard,app.kubernetes.io/instance=$releasename" -o jsonpath='{.items[0].metadata.name}')

kubectl -n $namespace exec "$POD" -- sh -c 'for peer in "$@"; do echo -e "\n\n--- Peer ${peer} ---"; cat "/config/peer_${peer}/peer_${peer}.conf"; done' sh $(kubectl -n $namespace get pod "$POD" -o jsonpath="{.spec.containers[0].env[?(@.name=='PEERS')].value}" | jq -r -R 'split(",")[]')
```

## Client mode
In the client mode, you have to set a few settings. The important one is to create a secret that includes privatekey, publickey and presharedkey as a key. You get this information from the WireGuard server peer conf.
You can find a sample of the secret file (in both variants) in the repo.

> **Note:** When using `wireguard.client.config.existingSecret`, the chart detects changes to the secret during `helm upgrade` (or GitOps reconcile) and automatically triggers a pod rollout with the updated configuration. This ensures your WireGuard client uses the latest keys after each upgrade.

```yaml
# ./samples/client.secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: client-secret
  namespace: wireguard
type: Opaque
stringData:
  privatekey: ...
  publickey: ...
  presharedkey: ...
```

```yaml
# ./samples/client.values.yaml
wireguard:
  timezone: "Europe/Berlin"
  client:
    enabled: true
    config:
      existingSecret: "client-secret"
      persistentKeepalive: 25
      endpoint: "vpn.example.com:51820"
```

Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
kubectl apply -f ./samples/client.secret.yaml
helm install wireguard-client oci://ghcr.io/slybase/charts/wireguard --values ./samples/client.values.yaml -n wireguard
```


## Start up with your wg0.conf
You can set your own wg0.conf file as a secret. If you do this, this will ignore the default values wireguard.server.config or wireguard.client.config.

In this example we set up a wg0.conf for a client, but of course this could also be done for a server.

```yaml
# ./samples/clientFullConfig.secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: wg-config
  namespace: wireguard
type: Opaque
stringData:
  wg0.conf: |-
    [Interface]
    .....
```
```yaml
# ./samples/clientFullConfig.values.yaml
wireguard:
  timezone: "Europe/Berlin"
  existingSecret: "wg-config"
  client:
    enabled: true
    config:
      persistentKeepalive: 25
      endpoint: "vpn.example.com:51820"
```


Install with Helm:
```bash
kubectl apply -f ./samples/namespace.yaml
kubectl apply -f ./samples/clientFullConfig.secret.yaml
helm install wireguard-client oci://ghcr.io/slybase/charts/wireguard --values ./samples/clientFullConfig.values.yaml -n wireguard
```

## Advanced Configuration

### Common Labels and Annotations

`commonLabels` and `commonAnnotations` are applied to every resource created by this chart (Deployment, Service, PVC, ServiceAccount, NetworkPolicy, ...). Useful for GitOps (ArgoCD), cost allocation, and audit. See `samples/commonLabels.values.yaml` for an example.

### NetworkPolicy

The chart can create a `NetworkPolicy` to restrict traffic to/from the WireGuard pod (disabled by default via `networkPolicy.enabled: false`):

- **Ingress** (server mode only): allows UDP traffic to the WireGuard port (`service.port`). By default, traffic is allowed from anywhere; restrict it with `networkPolicy.ingress.from`.
- **Egress**: always allows DNS lookups to `kube-system`. `networkPolicy.allowExternalEgress` (default `true`) additionally allows UDP egress to `0.0.0.0/0`, required for the server to reach peers and for clients to reach their configured endpoint.
- `networkPolicy.ingress.extraRules` / `networkPolicy.egress.extraRules` allow appending raw NetworkPolicy rule blocks.

See `samples/networkpolicy.values.yaml` for an example.

### Pod Disruption Budget

Set `podDisruptionBudget.minAvailable` or `podDisruptionBudget.maxUnavailable` to create a `PodDisruptionBudget` for the deployment. Empty (default) disables it.

### Topology Spread Constraints and Priority Class

`topologySpreadConstraints` and `priorityClassName` are passed through to the pod spec for advanced scheduling control.

## Notable changes

### To 2.0.0
- ⚠️ **`privileged: true` is no longer the default.** The container now runs with the s6-overlay default capability set plus `NET_ADMIN` and `privileged: false` (verified for server mode). The namespace still needs `pod-security.kubernetes.io/enforce: privileged` because the default capabilities are kept (no `drop: [ALL]`). To restore the old behaviour, set `securityContext` explicitly. See [Security](#security).
- ⚠️ **`updateStrategy.type` now defaults to `Recreate`** (was `RollingUpdate`). Server mode uses a single ReadWriteOnce PVC; `RollingUpdate` would deadlock the new pod waiting for the old one to release the volume.
- Added **`wireguard.loadKernelModule`** (default `false`): adds the `SYS_MODULE` capability so the container can load the WireGuard kernel module on hosts where it is not already present.
