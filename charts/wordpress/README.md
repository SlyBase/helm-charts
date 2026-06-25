# WordPress - Helm Chart for Kubernetes

## Introduction
This Helm chart installs WordPress in a Kubernetes cluster with many advanced features. It is based on the official WordPress image and provides automation for installation, user management, plugin installation, and metrics for prometheus (WordPress and Apache).

## TL;DR

You can find different sample YAML files (external database, integrated MariaDB and advanced configuration) in the GitHub repo in the subfolder "samples".

> **Note:** No default site is set as "Home", so you will see no landing page. You have to log in to /wp-admin to install a theme.


### Installation with integrated MariaDB chart

```yaml
# ./samples/mariaDB.secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: wordpress-test-secret
type: Opaque
stringData:
  wordpress.username: admin
  wordpress.password: S3cr3tP@ssw0rd
  wordpress.email: admin@example.com
  mariadb-root-password: S3cureDBP@ss
  mariadb-password: Sup3rS3cureP@ss
```

```yaml
# ./samples/mariaDB.values.yaml
wordpress:
  init:
    enabled: true
    existingSecret: "wordpress-test-secret"
    title: "My WordPress Site"
  url: "https://example.com"
mariadb:
  auth:
    database: "wordpress_db"
    username: "wordpress_db_user"
    existingSecret: "wordpress-test-secret"
```

Install with Helm:
```bash
kubectl apply -f ./samples/mariaDB.secrets.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/mariaDB.values.yaml
```

## Features

### Automatic WordPress Installation
- **Init Container**: Automatic initial installation of WordPress with predefined admin credentials.
- **Configuration**: Set admin username, password, email, first name, last name, and blog title.
- **Debug Mode**: Enable debugging for the installation.
- **Permalinks**: Configure permalink structures (e.g., post name, day and name).

### User Management
- **Automatic User Generation**: Create additional users with roles (Administrator, Editor, etc.).
- **Email Notification**: Automatically send emails with generated passwords.

### Language
- **Language**: Set the WordPress language (e.g., de_DE for German).

### Plugin Installation
- **Automatic Installation**: Install plugins from WordPress.org, local ZIPs, URLs, or Composer packages.
- **Composer Support**: Install plugins via Composer (e.g., `humanmade/s3-uploads`) that aren't available in WordPress.org.
- **Versioning**: Specify plugin versions (WordPress.org and Composer syntax supported).
- **Activation and Auto-Updates**: Activate plugins after installation and enable auto-updates.

### Theme Installation
- **Automatic Installation**: Install themes from WordPress.org, local ZIPs, URLs, or Composer packages.
- **Composer Support**: Install themes via Composer (e.g., `wpackagist-theme/astra`).
- **Versioning**: Specify theme versions (WordPress.org and Composer syntax supported).
- **Activation and Auto-Updates**: Activate themes after installation and enable auto-updates.
- **Custom Themes**: Support for custom theme ZIPs via direct URLs.

### WordPress Multisite
- **Subdirectory and Subdomain modes**: Configure multisite with either `example.com/blog` or `blog.example.com` style URLs.
- **Automatic Site Creation**: Define sub-sites declaratively in values and they are created/updated on every init.
- **Network-wide Plugin/Theme Activation**: Use `networkActivate` for plugins or `networkEnable` for themes to make them available across all sites.
- **Independent Main Site and Sub-Site Control**: `activate` controls the main site, `sites[]` controls sub-sites — both can be combined.
- **Per-Site User Roles**: Assign users to specific sub-sites with individual roles.
- **Site Pruning**: Optionally archive sites not defined in the configuration.
- **URL Plugin/Theme Slug Override**: Use the `slug` property for URL-based plugins/themes to enable full feature support (autoupdate, sites, network activation).

### Database
- **External Database**: Use an external MariaDB/MySQL database.
- **Embedded MariaDB**: Enable the integrated MariaDB chart for local database.
- **Memcached**: Enable Memcached for caching.
- **Redis**: Enable Redis as alternative caching.
- **Valkey**: Enable Valkey (Redis fork) as alternative caching.

### High Availability / Workload Controller
- **`controllerType`**: Run WordPress as a `deployment` (default, single shared PVC) or a `statefulset`.
- **Per-Pod ReadWriteOnce storage**: With `controllerType: statefulset`, each replica gets its own RWO volume via `volumeClaimTemplates` — true HA without depending on a single RWX share-manager (no shared single point of failure).
- **Headless Service** for stable Pod DNS, plus `statefulset.*` tunables: `podManagementPolicy`, `updateStrategy`, and `persistentVolumeClaimRetentionPolicy`.

### Metrics and Monitoring
- **WordPress Metrics**: Automatically install a WordPress Plugin for Prometheus metrics.
  - See details on GitHub Repo of (SlyMetrics Plugin from slydlake)[https://github.com/slydlake/slymetrics]
- **Apache Metrics**: Sidecar container for Apache metrics.
  - See details on GitHub Repo of (apache exporter from Lusitaniae)[https://github.com/Lusitaniae/apache_exporter]
- **Grafana Dashboard**: Automatically deploy Grafana dashboard for WordPress metrics visualization.
  - Requires Grafana with dashboard sidecar (e.g., kube-prometheus-stack)
  - Automatically discovered via `grafana_dashboard: "1"` labe


### Additional Configuration Files in values
- **Custom wp-config.php**: Additional constants like WP_MEMORY_LIMIT.
- **.htaccess Configuration**: Customize Apache URL rewriting and directives via `wordpress.htaccess`.
- **Apache Default Site Config**: Modify `/etc/apache2/sites-available/000-default.conf` using `apache.customDefaultSiteConfig`.
- **Apache Ports Config**: Adjust `/etc/apache2/ports.conf` with `apache.customPortsConfig`.
- **Apache PHP Config**: Set PHP settings like upload limits via `apache.customPhpConfig`.

### Custom commands in init container
- **Execute custom shell commands** after init.sh via ConfigMap (`wordpress.init.customInitConfigMap.name`)
- Perfect for custom setup tasks like updating plugins or creating pages
- Configure with `name` and optional `key` (defaults to "commands.sh")
- See `samples/customInit.configmap.yaml` and `samples/customInit.values.yaml`

### MU-Plugins (Must-Use Plugins)
- **Deploy MU-Plugins via ConfigMaps** - automatically activated PHP code that cannot be deactivated
- Each ConfigMap data key becomes a PHP file in `wp-content/mu-plugins/`
- Reference multiple ConfigMaps in `wordpress.muPluginsConfigMaps`
- See `samples/muPlugins.configmap.yaml` and `samples/muPlugins.values.yaml`

### SMTP
- **MU-plugin based**: A PHP MU-plugin is generated from chart values and mounted directly into `wp-content/mu-plugins/` — no external plugin installation needed and always current on rolling updates.
- Forces PHPMailer to use the configured SMTP server for all outgoing WordPress mail.
- Credentials (password, username, from-address) are read from a Kubernetes Secret at runtime — nothing sensitive in values.
- See `samples/smtp.values.yaml` and `samples/smtp.secrets.yaml`

### NetworkPolicy
- **Automatic traffic restriction**: Generates a `NetworkPolicy` for the WordPress pod when `networkPolicy.enabled: true`.
- DB egress auto-wired to the MariaDB subchart or `externalDatabase.host`.
- Cache egress auto-wired to whichever backend is active (Memcached, Redis, or Valkey).
- DNS egress (UDP/TCP 53) always included.
- Optional internet egress (`allowExternalEgress`) for wp-cli plugin downloads and SMTP.
- Ingress `from` rules and extra egress rules are fully configurable.
- See `samples/networkpolicy.values.yaml`

### PrometheusRule
- **Bundled alerting rules**: Creates a `PrometheusRule` resource when `metrics.prometheusRule.enabled: true` (requires `metrics.apache.enabled` or `metrics.wordpress.enabled`).
- Default alerts: `WordPressPodDown`, `WordPressApacheExporterScrapeFailing`, `WordPressApacheHighBusyWorkers`.
- Configurable `additionalLabels` to match your Prometheus Operator `ruleSelector`.
- Extend with `extraRules` or disable individual default rules via `defaultRules.*`.
- See `samples/prometheusrule.values.yaml`

### Secondary Ingress
- **Multiple Ingress objects** from one release: `ingress.secondary[]` generates additional Ingress resources alongside the primary one.
- Typical use-case: separate `wp-admin` Ingress with IP allowlist and a different TLS certificate.
- Each secondary entry supports its own `className`, `annotations`, `hosts`, and `tls`.
- Annotations are merged with `commonAnnotations` (entry-specific wins).
- See `samples/secondary-ingress.values.yaml`

### Backup CronJob
- **Scheduled database backup** to a PVC: a `CronJob` runs `mariadb-dump` and compresses the output with gzip.
- Optional file backup (`backup.includeFiles: true`) tars `wp-content` — only enable when your PVC supports multiple concurrent readers (RWX or VolumeSnapshot). Leave `false` for RWO storage (default).
- Optional **S3 sync** via rclone sidecar (`backup.s3.enabled`): after the dump completes the rclone container syncs the timestamped folder to any S3-compatible bucket.
- Backup PVC is annotated `helm.sh/resource-policy: keep` — it survives `helm uninstall`.
- See `samples/backup.values.yaml` and `samples/backup-s3.secrets.yaml`

### Backup restore
- **One-shot restore Job** (`backup.restore.enabled`) replays a backup created by the CronJob: it restores the database dump (and `wp-content` when the backup included files).
- Runs as a Helm **`pre-upgrade` hook** so it completes against the running database before the new WordPress pods roll.
- Restores from the **backup PVC** (default) or pulls the backup from **S3** first (`backup.restore.fromS3: true`).
- Pick a backup with `backup.restore.timestamp` (the `YYYYMMDD-HHMMSS` folder), or leave it empty to restore the newest. Set `backup.restore.enabled: false` again after a successful restore so it does not re-run on the next upgrade.

### VolumeSnapshot
- **Declarative CSI VolumeSnapshot** (`backup.volumeSnapshot.enabled`) of the WordPress data PVC — requires the external-snapshotter CRDs and a `VolumeSnapshotClass` on the cluster.
- A new timestamped VolumeSnapshot is rendered on each `helm upgrade`; combine with your storage backend's retention to prune old snapshots.
- `backup.volumeSnapshot.className` selects a specific class (empty = cluster default).

### commonLabels / commonAnnotations
- **Apply labels or annotations to every resource** created by the chart via `commonLabels` and `commonAnnotations`.
- Resource-specific annotations always win over `commonAnnotations` (merge: specific overrides common).
- Useful for GitOps tools (ArgoCD), service-mesh sidecar injection, cost-allocation, and audit tags.
- See `samples/commonLabels.values.yaml`

### Application Passwords (MCP / REST API access)
- **Create Application Passwords** during init for the admin user and any additional users
- The raw password (visible only once after creation) is stored in a Kubernetes Secret and survives `helm uninstall`
- Idempotent: existing passwords are reused; only re-created when the K8s Secret is gone but the WP entry is missing (or vice-versa)
- Uses WP-CLI in the init container — no REST API auth required during setup
- See `samples/token.values.yaml`

### JWT Authentication (MCP / REST API access)
- **Auto-installs `jwt-authentication-for-wp-rest-api`** in the init container when `wordpress.init.jwt.enabled: true` — no manual entry in `wordpress.plugins` needed
- The JWT signing secret is auto-generated on first install and preserved across `helm upgrade` via Helm's `lookup`
- Bring your own secret: set `wordpress.init.jwt.secret` (inline value) or point to an existing K8s Secret via `wordpress.init.jwt.existingSecret` + `wordpress.init.jwt.secretKey` (key name within that Secret, default `JWT_AUTH_SECRET_KEY`)
- The secret is injected into `wp-config.php` as `define('JWT_AUTH_SECRET_KEY', getenv('JWT_AUTH_SECRET_KEY'))` via the chart-managed Secret
- See `samples/token.values.yaml`


## Security by default

- **Pod Security Context**: Configured by default for secure permissions. Runs as `runAsUser`/`runAsGroup`/`fsGroup` `33` (www-data).
- **Container Security Context**: RunAsNonRoot and additional security measures enabled.
- **ServiceAccount token**: `serviceAccount.automount` defaults to `false` — the WordPress pod needs no Kubernetes API access. The chart automatically forces the token on only when the Application Password feature must write a Secret via the ServiceAccount.


## WordPress configuration

### Mandatory parameters
- `wordpress.url`: The WordPress site URL. Used to automatically set `WP_HOME` and `WP_SITEURL` — both as environment variables in the container and as PHP constants in `wp-config.php` (via `WORDPRESS_CONFIG_EXTRA`). If no protocol is provided, it is auto-prefixed with `https://` (when Ingress TLS is configured) or `http://` (otherwise).
- `storage`: Set your storage settings for WordPress
- By default `mariadb.enabled` is true. You have to set `mariadb.auth` and `mariadb.persistence`. Alternatively, it is also possible to use an external database.

> **Note:** If you need full manual control over `WP_HOME` / `WP_SITEURL` (e.g. different values for each, or a reverse proxy setup), set `wordpress.configExtraInject: false` to disable the automatic injection into `wp-config.php` and define the constants yourself via `wordpress.configExtra`. The environment variables `WP_HOME` and `WP_SITEURL` in the container are always derived from `wordpress.url`.

### Recommended parameters
- `wordpress.init`: Admin credentials and blog setup
- `service.type`: If you want to access WordPress internally set it to NodePort

### Additional parameters
- `wordpress.plugins`: List of plugins to install
- `wordpress.themes`: List of themes to install
- `wordpress.users`: Additional users
- `wordpress.language`: Language (e.g., de_DE)
- `wordpress.permalinks.structure`: Set the wordpress post structure
- `metrics.wordpress`: Enable WordPress metrics
- `metrics.apache`: Enable Apache metrics
- `memcached.enabled`: Enable embedded memcached
- `redis.enabled`: Enable embedded redis
- `valkey.enabled`: Enable embedded valkey

> **Note:** Cache backends are mutually exclusive. Enable at most one of `memcached.enabled`, `redis.enabled`, `valkey.enabled` (validated by `values.schema.json` and templates).

### Caching backends (compact)

Enable exactly **one** backend via its `enabled` flag.

- **Memcached** (`memcached.enabled`)
  - Subchart on port `11211`
  - Injects: `WP_CACHE`, `WP_CACHE_KEY_SALT`, `$memcached_servers`
  - Additional init logic for PHP extensions `memcache`/`memcached`
- **Redis** (`redis.enabled`)
  - Subchart on port `6379`
  - Injects: `WP_CACHE`, `WP_CACHE_KEY_SALT`, `WP_REDIS_HOST`, `WP_REDIS_PORT`, optional `WP_REDIS_PASSWORD`
  - No extra PHP-extension init required (`redis-cache` uses Predis)
- **Valkey** (`valkey.enabled`)
  - Same behavior as Redis (Valkey is Redis-compatible), also on port `6379`
  - Same inject pattern as Redis

Common options for all backends:

- `createConfig`: Enables/disables automatic config injection
- `cacheKeySalt`: Explicit salt value
- `cacheKeySaltSecret.{name,key}`: Salt from an existing Secret
- Redis/Valkey auth password from `auth.password` or `auth.existingSecret`

Minimal example (Redis):

```yaml
redis:
  enabled: true
  createConfig: true
  cacheKeySalt: ""
  cacheKeySaltSecret:
    name: ""
    key: "WP_CACHE_KEY_SALT"
  auth:
    password: ""
    existingSecret: ""
    existingSecretPasswordKey: "redis-password"
```

Quick check (same idea for Redis/Valkey):

```bash
kubectl -n default exec deploy/wp-wordpress -c wordpress -- ls -l /var/www/html/wp-content/object-cache.php
kubectl -n default exec deploy/wp-wordpress -c wordpress -- redis-cli -h wp-redis INFO stats | grep -E 'keyspace_hits|keyspace_misses'
```

Short stats checks:

```bash
# Memcached
kubectl -n default exec deploy/wp-wordpress -c wordpress -- php -r '$s=fsockopen("wp-memcached",11211,$e,$es,2); fwrite($s,"stats\r\n"); echo stream_get_contents($s); fclose($s);' | grep -E 'STAT cmd_get|STAT cmd_set|STAT get_hits|STAT get_misses'

# Redis / Valkey
kubectl -n default exec deploy/wp-wordpress -c wordpress -- redis-cli -h wp-redis INFO stats | grep -E 'keyspace_hits|keyspace_misses'
```


## Installation samples

### Basic Installation
See in TL;DR

### With External Database
Find the externalDB.secrets.yaml and externalDB.values.yaml in the GitHub repo in the subfolder "samples".

```bash
kubectl apply -f ./samples/externalDB.secrets.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/externalDB.values.yaml
```

### Advanced installation
Find the advanced.secrets.yaml, advanced.configmap.yaml and advanced.values.yaml in the GitHub repo in the subfolder "samples".

This includes everything from basic installation plus:
* **Initial setup of WordPress**
* **Plugin Installation**
* **Theme Installation**
* **Additional WordPress user**
* **Additional configuration files**
  * .htaccess
  * wp-config.php settings
  * apache custom.ini
* **Permanent Nodeport**
* **Prometheus metrics**
  * For WordPress
  * For Apache
* **Memcached pod**

```bash
kubectl apply -f ./samples/advanced.secrets.yaml
kubectl apply -f ./samples/advanced.configmap.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/advanced.values.yaml
```

### Advanced installation with High Availability (2 Replicas)
Find the advanced2.values.yaml in the GitHub repo in the subfolder "samples".

This setup includes everything from the advanced installation plus:
* **2 WordPress pod replicas** for high availability and load balancing
* **ReadWriteMany (RWX) storage** to allow multiple pods to share the same WordPress files
* **Distributed locking** ensures only one pod runs init operations at a time (prevents race conditions)

**Requirements:**
* Your cluster must support ReadWriteMany (RWX) storage class (e.g., NFS, Ceph, cloud provider shared storage)
* LoadBalancer or Ingress for distributing traffic across replicas

> **Recommended for true HA: `controllerType: statefulset`.** Instead of one shared RWX volume (whose single share-manager/NFS server is a single point of failure for *all* replicas), set `controllerType: statefulset` so each replica gets its own **ReadWriteOnce** volume via `volumeClaimTemplates`. A storage outage then affects at most one replica, and you can use any RWO storage class (no RWX required). WordPress files (core/plugins/themes) are reproduced per volume on init; keep uploads on S3/object storage and the database external/shared. See the **High Availability / Workload Controller** feature above.

```bash
kubectl apply -f ./samples/advanced.secrets.yaml
kubectl apply -f ./samples/advanced.configmap.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/advanced2.values.yaml
```

### Memcached cache setup
Use WordPress with Memcached object cache. See `samples/memcached.values.yaml`.

```bash
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/memcached.values.yaml
```

### Redis cache setup
Use WordPress with Redis object cache. See `samples/redis.values.yaml`.

```bash
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/redis.values.yaml
```

### Valkey cache setup
Use WordPress with Valkey object cache. See `samples/valkey.values.yaml`.

```bash
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/valkey.values.yaml
```

### Custom Init Commands
Execute custom shell commands after WordPress installation. See `samples/customInit.configmap.yaml` and `samples/customInit.values.yaml`.

```bash
kubectl apply -f ./samples/customInit.configmap.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/customInit.values.yaml
```

### MU-Plugins via ConfigMaps
Deploy Must-Use Plugins that are automatically activated. See `samples/muPlugins.configmap.yaml` and `samples/muPlugins.values.yaml`.

```bash
kubectl apply -f ./samples/muPlugins.configmap.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/muPlugins.values.yaml
```

### Application Passwords + JWT (REST API / MCP access)
Configure per-user Application Passwords and JWT auth in one step. See `samples/token.values.yaml`.

```yaml
# samples/token.values.yaml (excerpt)
wordpress:
  init:
    existingSecret: "wordpress-secret"

    # JWT: auto-installs jwt-authentication-for-wp-rest-api, auto-generates signing secret
    jwt:
      enabled: true
      # secret: ""                        # inline signing secret — auto-generated if empty
      # existingSecret: ""                # alternative: name of an existing K8s Secret
      # secretKey: "JWT_AUTH_SECRET_KEY"  # key within existingSecret (default: JWT_AUTH_SECRET_KEY)

    # Application Password for the admin user
    applicationPassword:
      name: "API Access"
      outputSecret:
        name: "wordpress-token-admin"
        usernameKey: "WP_USERNAME"
        passwordKey: "WP_APP_PASSWORD"
        urlKey: "WP_SITE_URL"

  users:
    - username: "service-account"
      email: "svc@example.com"
      role: "editor"
      sendEmail: false
      applicationPassword:
        name: "API Access"
        outputSecret:
          name: "wordpress-token-svc"
          usernameKey: "WP_USERNAME"
          passwordKey: "WP_APP_PASSWORD"
          urlKey: "WP_SITE_URL"
```

```bash
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values samples/token.values.yaml
```

**Read credentials after install:**

```bash
# Application Password (admin)
kubectl get secret wordpress-token-admin \
  -o go-template='user={{ index .data "WP_USERNAME" | base64decode }}  pass={{ index .data "WP_APP_PASSWORD" | base64decode }}{{ "\n" }}'

# Application Password (service account)
kubectl get secret wordpress-token-svc \
  -o go-template='user={{ index .data "WP_USERNAME" | base64decode }}  pass={{ index .data "WP_APP_PASSWORD" | base64decode }}{{ "\n" }}'
```

**Test Application Password against the REST API:**

```bash
USER=$(kubectl get secret wordpress-token-admin -o jsonpath='{.data.WP_USERNAME}' | base64 -d)
PASS=$(kubectl get secret wordpress-token-admin -o jsonpath='{.data.WP_APP_PASSWORD}' | base64 -d)
URL=$(kubectl get secret wordpress-token-admin -o jsonpath='{.data.WP_SITE_URL}' | base64 -d)

curl -su "$USER:$PASS" "$URL/wp-json/wp/v2/users/me" | jq '{id,slug,roles}'
```

**Test JWT:**

```bash
WP_PASS=$(kubectl get secret wordpress-secret -o jsonpath='{.data.wordpress\.password}' | base64 -d)
JWT=$(curl -sf -X POST "$URL/wp-json/jwt-auth/v1/token" \
  -d "username=$USER&password=$WP_PASS" | jq -r '.token')

curl -sf -H "Authorization: Bearer $JWT" "$URL/wp-json/wp/v2/users/me" | jq '{id,slug}'
```

> **HTTP sites:** WordPress 5.6+ disables Application Passwords on non-HTTPS sites. Add this filter to an MU-Plugin to allow it on HTTP (e.g. cluster-internal or local):
> ```php
> add_filter('wp_is_application_passwords_available', '__return_true');
> ```
> In production behind TLS this filter is not needed.

---

### MCP (Model Context Protocol) via WordPress

The [`wordpress/mcp-adapter`](https://github.com/slybase/mcp-adapter) plugin exposes a **Streamable HTTP MCP server** at `/wp-json/mcp/mcp-adapter-default-server`.
Both Application Password and JWT auth work as `Authorization` headers.

Configure two named connections in your project's `.claude/settings.local.json`:

```json
{
  "mcpServers": {
    "wordpress-app-password": {
      "type": "http",
      "url": "https://example.com/wp-json/mcp/mcp-adapter-default-server",
      "headers": {
        "Authorization": "Basic <base64(username:app-password)>"
      }
    },
    "wordpress-jwt": {
      "type": "http",
      "url": "https://example.com/wp-json/mcp/mcp-adapter-default-server",
      "headers": {
        "Authorization": "Bearer <jwt-token>"
      }
    }
  }
}
```

Generate the credentials from Kubernetes Secrets:

```bash
WP_URL=$(kubectl get secret wordpress-token-admin -o jsonpath='{.data.WP_SITE_URL}' | base64 -d)
USER=$(kubectl get secret wordpress-token-admin -o jsonpath='{.data.WP_USERNAME}' | base64 -d)
PASS=$(kubectl get secret wordpress-token-admin -o jsonpath='{.data.WP_APP_PASSWORD}' | base64 -d)
WP_LOGIN_PASS=$(kubectl get secret wordpress-secret -o jsonpath='{.data.wordpress\.password}' | base64 -d)

# Application Password → Basic Auth header value
echo "Basic $(echo -n "$USER:$PASS" | base64)"

# JWT → Bearer token (expires in ~7 days)
curl -sf -X POST "$WP_URL/wp-json/jwt-auth/v1/token" \
  -d "username=$USER&password=$WP_LOGIN_PASS" | jq -r '"Bearer " + .token'
```

> **Tip:** Application Passwords don't expire — prefer them for long-running automations.
> JWT tokens expire after ~7 days; refresh by re-running the `jwt-auth/v1/token` request.

Required plugins (add to `wordpress.plugins`):
```yaml
wordpress:
  init:
    jwt:
      enabled: true        # auto-installs jwt-authentication-for-wp-rest-api
  plugins:
    - name: "wordpress/mcp-adapter"
      activate: true
    - name: "enable-abilities-for-mcp"
      activate: true
```

---

### SMTP
Configure outgoing mail via any SMTP server. See `samples/smtp.values.yaml` and `samples/smtp.secrets.yaml`.

```bash
kubectl apply -f ./samples/smtp.secrets.yaml
# then add the smtp snippet to your existing values file
```

```yaml
# smtp snippet to merge into your values
wordpress:
  smtp:
    enabled: true
    host: smtp.gmail.com
    port: 587
    encryption: tls
    fromName: "My WordPress Site"
    auth: true
    existingSecret: gmail-smtp-secret
    existingSecretPasswordKey: password
    existingSecretUsernameKey: username
    existingSecretFromEmailKey: fromEmail
```

### NetworkPolicy
Restrict pod traffic to only the required connections. See `samples/networkpolicy.values.yaml`.

```yaml
# snippet to merge into your values
networkPolicy:
  enabled: true
  allowExternalEgress: true   # needed for wp-cli downloads and SMTP
  ingress:
    from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx
```

### PrometheusRule
Deploy bundled alerting rules. Requires `metrics.apache.enabled` or `metrics.wordpress.enabled`. See `samples/prometheusrule.values.yaml`.

```yaml
# snippet to merge into your values
metrics:
  apache:
    enabled: true
  prometheusRule:
    enabled: true
    additionalLabels:
      release: kube-prometheus-stack
```

### Secondary Ingress
Separate Ingress for `wp-admin` with IP allowlist and its own TLS certificate. See `samples/secondary-ingress.values.yaml`.

```yaml
# snippet to merge into your values
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: blog.example.com
      paths:
        - path: /
          pathType: Prefix
  secondary:
    - name: admin
      enabled: true
      className: nginx
      annotations:
        nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8"
      hosts:
        - host: admin.example.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - secretName: wp-admin-tls
          hosts: [admin.example.com]
```

### Backup CronJob
Daily database backup to a PVC, with optional S3 sync via rclone. See `samples/backup.values.yaml` and `samples/backup-s3.secrets.yaml`.

```bash
# S3 backup: create the rclone config secret first
kubectl create secret generic my-rclone-config --from-file=rclone.conf=./rclone.conf
```

```yaml
# snippet to merge into your values
backup:
  enabled: true
  schedule: "0 2 * * *"
  retentionDays: 14
  persistence:
    size: 20Gi
  # Optional S3 sync after each run:
  s3:
    enabled: true
    existingSecret: my-rclone-config   # Secret with rclone.conf
    remote: s3
    bucket: my-wordpress-backups
    path: wordpress
```

**Trigger a manual backup run:**
```bash
kubectl create job --from=cronjob/<release>-backup manual-backup-1
kubectl logs -l job-name=manual-backup-1 -c backup -f
```

> **Note:** `backup.includeFiles: true` tars `wp-content` in addition to the database dump. Only enable this when the WordPress PVC supports concurrent readers (RWX storage or VolumeSnapshot). With standard RWO storage (OpenEBS ZFS, Longhorn RWO, etc.) leave it `false` (default) to avoid mount conflicts.

### Restore a backup
Replay a backup created by the CronJob. The restore runs as a Helm `pre-upgrade` hook Job against the running database, before the WordPress pods roll.

```yaml
# snippet to merge into your values
backup:
  enabled: true
  restore:
    enabled: true                 # set back to false after a successful restore
    timestamp: "20260625-084235"  # YYYYMMDD-HHMMSS folder; empty = newest available
    fromS3: false                 # true = pull the backup from S3 (rclone) first
```

```bash
helm upgrade <release> ./charts/wordpress -f values.yaml
kubectl logs job/<release>-wordpress-restore   # => "restore complete (<timestamp>)"
# then set backup.restore.enabled=false and upgrade once more so it does not re-run
```

### VolumeSnapshot
Create a CSI snapshot of the WordPress data PVC. Requires the external-snapshotter CRDs and a `VolumeSnapshotClass` on the cluster. A new timestamped snapshot is created on every `helm upgrade`.

```yaml
# snippet to merge into your values
backup:
  volumeSnapshot:
    enabled: true
    className: ""   # empty = cluster default VolumeSnapshotClass
```

> **Note:** for `controllerType: statefulset` the data PVC is per-replica (`<fullname>-<fullname>-0`); set `storage.existingClaim` to the PVC you want snapshotted.

### commonLabels and commonAnnotations
Apply uniform labels or annotations to every Kubernetes resource the chart creates. See `samples/commonLabels.values.yaml`.

```yaml
# snippet to merge into your values
commonLabels:
  team: platform
  environment: production

commonAnnotations:
  owner: platform-team
  contact: platform@example.com
```

### Composer Packages
Install plugins and themes via Composer that aren't available in WordPress.org. See `samples/composer.values.yaml`.

```bash
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/composer.values.yaml
```

**Examples:**
- **Plugins**: `humanmade/s3-uploads`, `wpackagist-plugin/wordpress-seo`
- **Themes**: `wpackagist-theme/astra`
- **Library Packages**: Composer packages listed under `wordpress.plugins` or `wordpress.themes` are explicitly mapped into `wp-content/plugins` or `wp-content/themes`, even when upstream declares them as `type: library`
- **Auto-Update**: Works for packages without fixed version (always installs latest)
- **Pruning**: Compatible with `pluginsPrune` and `themesPrune`

#### Custom Composer Repositories
By default, only **wpackagist.org** is configured, which mirrors all WordPress.org plugins and themes.

Add custom repositories for private/premium packages:

```yaml
wordpress:
  composer:
    repositories:
      - type: "vcs"
        url: "https://github.com/mycompany/private-plugin"
      - type: "composer"
        url: "https://my-satis-server.com"
      - type: "package"
        package:
          name: "vendor/premium-plugin"
          version: "1.0.0"
          dist:
            url: "https://example.com/premium-plugin.zip"
            type: "zip"
  plugins:
    - name: "mycompany/private-plugin"
      activate: true
```

### WordPress Multisite
Full multisite configuration with automatic site creation, network-wide plugin/theme management, and per-site user roles. See `samples/multisite.values.yaml` and `samples/multisite.secrets.yaml`.

```bash
kubectl apply -f ./samples/multisite.secrets.yaml
helm install wordpress oci://ghcr.io/slybase/charts/wordpress --values ./samples/multisite.values.yaml
```

> **Important:** Do **not** add multisite constants (`WP_ALLOW_MULTISITE`, `MULTISITE`, `SUBDOMAIN_INSTALL`, `DOMAIN_CURRENT_SITE`, `PATH_CURRENT_SITE`, `SITE_ID_CURRENT_SITE`, `BLOG_ID_CURRENT_SITE`) to `configExtra`, `configExtraConfigMap`, or `configExtraSecret`. These constants are automatically written to `wp-config.php` by the init container during multisite setup and persist on the PVC. Defining them again would cause PHP "Constant already defined" warnings.

#### Plugin/Theme Activation in Multisite

In multisite mode, `activate` and `sites` work **independently**:

| Property | Effect |
|---|---|
| `activate: true` | Activate on the **main site** |
| `sites: [blog, shop]` | Activate on specific **sub-sites** |
| `activate: true` + `sites: [blog]` | Activate on **main + blog** |
| `networkActivate: true` | Activate across **entire network** (overrides activate and sites) |

Example:
```yaml
wordpress:
  plugins:
    # Network-wide: available on ALL sites
    - name: "wordpress-seo"
      activate: true
      networkActivate: true

    # Sub-sites only: NOT on main site
    - name: "contact-form-7"
      activate: false
      sites:
        - blog
        - shop

    # Main site + specific sub-sites
    - name: "woocommerce"
      activate: true
      sites:
        - shop
```

The same pattern applies to themes with `networkEnable` (make theme available to all sites) and `activate`/`sites` (control which site uses it as active theme).

#### URL Plugins/Themes with `slug` Property

When installing plugins or themes from a URL, the slug (directory name after installation) cannot always be determined from the URL. Use the `slug` property to explicitly specify it:

```yaml
wordpress:
  plugins:
    - name: "https://example.com/downloads/my-premium-plugin-v2.3.zip"
      slug: "my-premium-plugin"   # Required: actual plugin directory name
      activate: true
      autoupdate: true
      sites:
        - blog
  themes:
    - name: "https://creativethemes.com/downloads/blocksy-child.zip"
      slug: "blocksy-child"       # Required: actual theme directory name
      activate: true
      autoupdate: true
```

Without `slug`, URL plugins/themes use `basename` of the URL as a best-effort guess, but this fails for URLs like `download?id=123` or versioned filenames like `plugin-v2.3.1.zip`. Setting `slug` explicitly enables:
- **Skip-if-installed** detection (no unnecessary reinstalls)
- **Auto-updates**
- **Site-specific activation** (`sites[]`)
- **Network activation** (`networkActivate` / `networkEnable`)

## Notable changes

### To 5.0.0
- ⚠️ **`serviceAccount.automount` now defaults to `false`** (was `true`). The WordPress pod no longer mounts a Kubernetes API token unless it is actually needed — the chart force-enables it automatically when the Application Password feature must write a Secret via the ServiceAccount. If external tooling relied on the mounted token, set `serviceAccount.automount: true` explicitly.
- ⚠️ **`podSecurityContext.runAsGroup: 33` is now set by default** (matching `runAsUser`/`fsGroup` = www-data). On pre-existing volumes whose files are owned by a different GID, adjust ownership or override `runAsGroup`.
- Added **Backup restore** (`backup.restore`): one-shot Job (Helm `pre-upgrade` hook) that restores a CronJob backup — database (and `wp-content` when included) — from the backup PVC or from S3 (`fromS3`). Select a backup with `restore.timestamp` or restore the newest.
- Added **VolumeSnapshot** (`backup.volumeSnapshot`): declarative CSI VolumeSnapshot of the WordPress data PVC, created per `helm upgrade`.

### To 4.6.0
- Added **StatefulSet controller** (`controllerType: statefulset`): each replica runs on its own **ReadWriteOnce** volume via `volumeClaimTemplates`, removing the Longhorn RWX share-manager single point of failure that could take down all replicas at once during a rebuild/share-manager recreation. Adds a headless Service and `statefulset.*` tunables (`podManagementPolicy`, `updateStrategy`, `persistentVolumeClaimRetentionPolicy`). Default remains `controllerType: deployment` (backwards-compatible).
- Pod spec extracted into a shared `wordpress.podTemplate` partial (`templates/_pod.tpl`) reused by both the Deployment and the new StatefulSet.

### To 4.2.0
- Added **SMTP** (`wordpress.smtp`): MU-plugin generated from chart values, mounted directly via subPath — no external plugin needed. Credentials (password, username, from-address) are read from a Kubernetes Secret.
- Added **NetworkPolicy** (`networkPolicy`): automatically wires DB/cache/DNS egress; optional internet egress via `allowExternalEgress`.
- Added **PrometheusRule** (`metrics.prometheusRule`): bundled alerts for pod-down, scrape-failing, and high busy-workers; extend via `extraRules`.
- Added **Secondary Ingress** (`ingress.secondary[]`): generates additional Ingress objects per release (e.g. separate `wp-admin` with IP allowlist).
- Added **Backup CronJob** (`backup`): daily `mariadb-dump` to PVC; optional rclone S3 sidecar (`backup.s3`). New `backup.includeFiles` flag (default `false`) controls whether `wp-content` is also archived.
- Added **commonLabels / commonAnnotations**: applied to all chart resources; resource-specific annotations take precedence.

### To 4.1.0
- Added **Application Passwords** (`wordpress.init.applicationPassword`, `wordpress.users[].applicationPassword`): WP-CLI in the init container creates Application Passwords per user and stores them in Kubernetes Secrets (persist after `helm uninstall`).
- Added **JWT Authentication** (`wordpress.init.jwt`): auto-installs `jwt-authentication-for-wp-rest-api` in the init container, signing secret is auto-generated and preserved across upgrades via `lookup`.
- New `wordpress.init.jwt.secret`: inline signing secret value (replaces the old `signingKey` field — it is the secret VALUE, not a key name).
- New `wordpress.init.jwt.secretKey`: key name within `wordpress.init.jwt.existingSecret` (default: `JWT_AUTH_SECRET_KEY`).
- New template `app-password-rbac.yaml`: Role + RoleBinding so the WordPress ServiceAccount can write Application Password output Secrets.

### To 4.0.0
- Update WordPress to 7.0.0 (PHP 8.3). WordPress 7.0 uses `$generic$` password hashing for Application Passwords (replaces phpass). Existing Application Passwords remain valid; new ones are created in the updated format automatically.

### To 3.4.0
- Complete Memcached object-cache support for WordPress, including runtime bootstrap of `memcache`/`memcached` PHP extensions (no custom image required).
- `WP_CACHE` is now injected automatically (guarded) when Memcached config is enabled.
- New `WP_CACHE_KEY_SALT` handling for stable cache isolation: explicit value, existing Secret reference, or auto-generated persisted value.
- New `memcached.serverGroups` allows cache-group-specific Memcached backends, with fallback to the embedded Memcached service.
- Improved init safety in drop-in mode (`object-cache.php`) to avoid plugin activation/redeclare conflicts and stale drop-in bootstrap failures.
- Fixed blog title update in init (`blogname`) so title changes are now applied reliably.
- Added Redis as alternative caching option using cloudpirates-redis chart and redis-cache plugin.
- Added Valkey (Redis fork) as alternative caching option using cloudpirates-valkey chart and redis-cache plugin.
- Automatically injects `WP_REDIS_HOST`, `WP_REDIS_PORT`, and optional `WP_REDIS_PASSWORD` into wp-config.php.
- Uses Predis library (pure PHP) - no PHP extensions or init containers required.
- Redis, Valkey, and Memcached can be used as mutually exclusive caching backends.

### To 3.2.0
- Introducing multisite for WordPress, including users, plugins, and themes

### To 3.0.0
- Split init pipeline into three containers: `fix-permissions` (runs as root), `base`, and `init` — enables correct ownership handling on RWX storage (e.g., Longhorn). ⚠️ **`fix-permissions` requires root permissions.**
- Moved the init script library into a separate ConfigMap and added ConfigMap checksum annotations to trigger automatic rollouts on script/config changes. **If the ConfigMap is managed outside the Helm release (e.g. applied via Kustomize), you may need to manually restart the deployment to run the init containers again:**
  `kubectl rollout restart deployment/wordpress-wordpress`
- Improved multi-pod init safety with heartbeat-based distributed locking, a bootstrap `helm_locks` table, and automatic stale-lock detection (60s without heartbeat).
- Replaced `wp-cli` with direct database queries for much faster initialization (up to ~200% speed improvement in many scenarios).

### To 2.0.0
- WordPress version from 6.8.3 to 6.9.0
- WordPress image tag from PHP version 8.1 to 8.3 (default)
- mariadb from 12.0.2 to 12.1.2

### To 1.0.0
This major release introduces new possibilities to use composer plugins and themes and muPlugins. Now it is possible to activate a prune mode for plugins and themes. This will uninstall all plugins/themes that are not listed in the values.

Also adds more flexible user customization with init scripts. The init script is now a huge set to pre-configure and set up WordPress.
For more, see the changelog.