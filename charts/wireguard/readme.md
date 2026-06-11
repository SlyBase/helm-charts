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

The container runs as `root` (`runAsUser: 0`) with `privileged: true` and the `NET_ADMIN` capability. This is required by the underlying [linuxserver/wireguard](https://github.com/linuxserver/docker-wireguard) image:

- its s6-overlay init system needs root capabilities beyond `NET_ADMIN` (e.g. `CAP_SETUID`/`CAP_SETGID`) to start up — running with a restricted capability set (`drop: [ALL]`, `add: [NET_ADMIN]`) without `privileged: true` causes the container to crash with `s6-overlay-suexec: fatal: unable to setgid to root`
- `wg-quick` (interface creation, and in server mode routing/NAT) needs `NET_ADMIN`, and on some host kernels `SYS_MODULE` to load the WireGuard kernel module

As a result:
- `pod-security.kubernetes.io/enforce: privileged` is required on the namespace (see Prerequisites)
- the chart **cannot** meet the `restricted` or `baseline` Pod Security Standard

What the chart hardens by default regardless:
- `seccompProfile: RuntimeDefault` for the pod and the container
- `capabilities: {drop: [ALL], add: [NET_ADMIN]}` (`SYS_MODULE` is commented out — only needed if the host kernel doesn't already have the WireGuard module loaded)
- `serviceAccount.automount: false` — the chart never talks to the Kubernetes API

`allowPrivilegeEscalation: false` is intentionally **not** set: Kubernetes rejects the combination `privileged: true` + `allowPrivilegeEscalation: false` (`cannot set allowPrivilegeEscalation to false and privileged to true`), and `privileged: true` is a hard functional requirement as described above.

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
