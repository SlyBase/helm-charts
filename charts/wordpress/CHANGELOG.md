# Changelog

All notable changes to this chart are documented here.

## 3.6.40 - 2026-05-14

- Update redis to 0.27.9

## 3.6.39 - 2026-05-07

- Update redis to 0.27.6

## 3.6.38 - 2026-05-06

- Update docker.io/valkey/valkey to 9.0.4

## 3.6.37 - 2026-05-06

- Update docker.io/valkey/valkey to 9.0.4

## 3.6.36 - 2026-05-05

- Update docker.io/redis to 8.6.3

## 3.6.35 - 2026-05-05

- Update docker.io/redis to 8.6.3

## 3.6.33 - 2026-05-04

- Update valkey to 0.20.1

## 3.6.32 - 2026-04-29

- Update redis to 0.27.4

## 3.6.31 - 2026-04-27

- Update memcached to 0.13.1

## 3.6.30 - 2026-04-27

- Update redis to 0.27.2

## 3.6.29 - 2026-04-24

- Update docker.io/memcached digest to 277e0c4

## 3.6.28 - 2026-04-22

- Update redis to 0.27.1

## 3.6.27 - 2026-04-21

- Update redis to 0.27.0

## 3.6.26 - 2026-04-20

- Update valkey to 0.20.0

## 3.6.25 - 2026-04-20

- Update memcached to 0.13.0

## 3.6.24 - 2026-04-17

- Update redis to 0.26.11

## 3.6.23 - 2026-04-16

- Update memcached to 0.12.1

## 3.6.22 - 2026-04-16

- Update docker.io/mariadb digest to e0236fc

## 3.6.21 - 2026-04-16

- Update redis to 0.26.9

## 3.6.20 - 2026-04-16

- Update mariadb to 0.16.1

## 3.6.19 - 2026-04-13

- Fix Composer-managed plugin and theme installation for packages published as type: library by synchronizing installer paths and linking vendor packages into wp-content when needed.
- Preserve Composer command exit codes in the init workflow so failed installs are no longer reported as successful.
- Retry Composer theme activation and multisite network-enable after dependency installation to avoid init-container startup failures.

## 3.6.18 - 2026-04-12

- Fix duplicate WORDPRESS_DEBUG env rendering in the WordPress Deployment to prevent failed Helm upgrades and rollback remediation.

## 3.6.17 - 2026-04-10

- Update mariadb to 0.16.0

## 3.6.16 - 2026-04-10

- Update valkey to 0.19.0

## 3.6.15 - 2026-04-10

- Update memcached to 0.12.0

## 3.6.14 - 2026-04-08

- Update docker.io/memcached to

## 3.6.13 - 2026-04-08

- Update docker.io/mariadb to

## 3.6.12 - 2026-03-29

- Update redis to 0.26.8

## 3.6.11 - 2026-03-27

- Update docker.io/redis docker.io/redis to 8.6.2

## 3.6.10 - 2026-03-18

- Update mariadb to 0.15.3

## 3.6.8 - 2026-03-17

- Update docker.io/mariadb to e16f61b
- Pull Request: https://github.com/slydlake/helm-charts/pull/239

## 3.6.7 - 2026-03-17

- Update [mariadb](https://mariadb.org) ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/mariadb)) to 0.15.2
- Pull Request: https://github.com/slydlake/helm-charts/pull/236

## 3.6.6 - 2026-03-17

- Update [redis](https://www.redis.io) ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/redis)) to 0.26.5
- Pull Request: https://github.com/slydlake/helm-charts/pull/238

## 3.6.5 - 2026-03-17

- Update docker.io/mariadb to 310a2b5
- Pull Request: https://github.com/slydlake/helm-charts/pull/235

## 3.6.4 - 2026-03-17

- Update docker.io/mariadb to ddb976b
- Update docker.io/memcached to 27db90c
- Pull Request: https://github.com/slydlake/helm-charts/pull/234

## 3.6.3 - 2026-03-17

- Update docker.io/memcached to 29eba63
- Pull Request: https://github.com/slydlake/helm-charts/pull/233

> Note: Releases 3.5.2, 3.5.3, 3.5.4, 3.5.5, 3.5.6, 3.5.7, 3.5.13, and 3.5.14 were accidentally published under 3.5.x although they belonged to the 3.6.x line. Those OCI artifacts remain published for immutability. Unpublished incorrect entries 3.5.8 through 3.5.12 were removed. Stable releases continue from 3.6.2.

## 3.6.2 - 2026-03-15

- Correct WordPress chart version line after accidental 3.5.x releases.
- No functional chart changes compared to 3.5.14; this release restores the intended 3.6.x numbering.

## 3.5.14 - 2026-03-14

- Update [memcached](https://memcached.org) ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/memcached)) to 0.11.0
- Pull Request: https://github.com/slydlake/helm-charts/pull/229

## 3.5.13 - 2026-03-12

- Update docker.io/wordpress to 6.9.4-php8.3-apache
- Update docker.io/wordpress to 6.9.4
- Pull Request: https://github.com/slydlake/helm-charts/pull/210

## 3.5.7 - 2026-03-06

- Update redis to 0.25.8
- Pull Request: https://github.com/slydlake/helm-charts/pull/159

## 3.5.6 - 2026-03-05

- Update redis to 0.25.7
- Pull Request: https://github.com/slydlake/helm-charts/pull/157

## 3.5.5 - 2026-03-05

- Update redis to 0.25.6
- Pull Request: https://github.com/slydlake/helm-charts/pull/156

## 3.5.4 - 2026-03-03

- Update redis to 0.25.5
- Pull Request: https://github.com/slydlake/helm-charts/pull/154

## 3.5.3 - 2026-03-02

- Apache ServerName directive added to fix ServerName warnings in Apache logs
- Added apache.serverName value to set ServerName directive in Apache config, defaulting to the host of the WordPress URL host if not set

## 3.5.2 - 2026-02-27

- Update memcached to 0.10.1
- Update redis to 0.25.2
- Pull Request: https://github.com/slydlake/helm-charts/pull/153

## 3.6.1 - 2026-02-27

- Update Update to dependencies
- Pull Request: https://github.com/slydlake/helm-charts/pull/153

## 3.6.0 - 2026-02-26

- Update docker.io/memcached to 572b011
- Update docker.io/redis to 8.6.1-trixie
- Update docker.io/valkey/valkey to 9.0.3-trixie
- Update mariadb to 0.14.3
- Update redis to 0.25.1
- Pull Request: https://github.com/slydlake/helm-charts/pull/146

## 3.5.1 - 2026-02-26

- Init container: Added inline custom script property. Thanks to Minding000

## 3.5.0 - 2026-02-26

- Pod scheduling: Add optional priorityClassName support. Thanks to oden3000
- HTTPRoute as the new Ingress alternative (GatewayAPI). Thanks to Minding000
- container ports (8080, 8443) - this has no effect on the service ports, but doesn't violate the security context. Thanks to Minding000
- Added ServerName directive 000-default.conf. Thanks to Minding000
- Added minimum length validation to wordpress.url to ensure chart users do not miss it. Thanks to Minding000

## 3.4.0 - 2026-02-23

- Init container: Fixed permissions only apply when using rwx storage. No root access required for init script when using rwo storage.
- Init script: Blog title (blogname) update is fixed and now reliably applied via wp option update.
- Memcached: Providing now full memcached functionality.
- Memcached: Automatically inject guarded WP_CACHE define when memcached config is enabled.
- Memcached: Add WP_CACHE_KEY_SALT support with precedence: explicit value, existing Secret reference, persisted generated value.
- Memcached: Add memcached.serverGroups for cache-group-specific backend mapping; fallback remains embedded memcached service.
- Memcached: Harden memcached runtime setup via extension bootstrap init container (memcache + memcached) and staged shared libraries.
- Memcached: Enforce memcached plugin drop-in mode (object-cache.php) and avoid normal activation conflicts in init workflow.
- Redis: Added Redis as alternative caching option using cloudpirates-redis chart and redis-cache plugin.
- Valkey: Added Valkey (Redis fork) as alternative caching option using cloudpirates-valkey chart and redis-cache plugin.
- Redis/Valkey: Automatically inject WP_REDIS_HOST, WP_REDIS_PORT, and optional WP_REDIS_PASSWORD into wp-config.php.
- Redis/Valkey: Add WP_CACHE_KEY_SALT support with precedence: explicit value, existing Secret reference, persisted generated value.

## 3.4.0-beta3 - 2026-02-21

- Init container: Fixed permissions only apply when using rwx storage. No root access required for init script when using rwo storage.
- Init script: Blog title (blogname) update is fixed and now reliably applied via wp option update.
- Memcached: Providing now full memcached functionality.
- Memcached: Automatically inject guarded WP_CACHE define when memcached config is enabled.
- Memcached: Add WP_CACHE_KEY_SALT support with precedence: explicit value, existing Secret reference, persisted generated value.
- Memcached: Add memcached.serverGroups for cache-group-specific backend mapping; fallback remains embedded memcached service.
- Memcached: Harden memcached runtime setup via extension bootstrap init container (memcache + memcached) and staged shared libraries.
- Memcached: Enforce memcached plugin drop-in mode (object-cache.php) and avoid normal activation conflicts in init workflow.
- Redis: Added Redis as alternative caching option using cloudpirates-redis chart and redis-cache plugin.
- Valkey: Added Valkey (Redis fork) as alternative caching option using cloudpirates-valkey chart and redis-cache plugin.
- Redis/Valkey: Automatically inject WP_REDIS_HOST, WP_REDIS_PORT, and optional WP_REDIS_PASSWORD into wp-config.php.
- Redis/Valkey: Add WP_CACHE_KEY_SALT support with precedence: explicit value, existing Secret reference, persisted generated value.
- Release channel: beta

## 3.4.0-beta2 - 2026-02-19

- Providing now full memcached functionality.
- Init script: Blog title (blogname) update is fixed and now reliably applied via wp option update.
- Memcached: Automatically inject guarded WP_CACHE define when memcached config is enabled.
- Memcached: Add WP_CACHE_KEY_SALT support with precedence: explicit value, existing Secret reference, persisted generated value.
- Memcached: Add memcached.serverGroups for cache-group-specific backend mapping; fallback remains embedded memcached service.
- Memcached: Harden memcached runtime setup via extension bootstrap init container (memcache + memcached) and staged shared libraries.
- Memcached: Enforce memcached plugin drop-in mode (object-cache.php) and avoid normal activation conflicts in init workflow.
- Release channel: beta

## 3.4.0-beta1 - 2026-02-19

- Providing now full memcached functionality.
- Init script: Blog title (blogname) update is fixed and now reliably applied via wp option update.
- Memcached: Automatically inject guarded WP_CACHE define when memcached config is enabled.
- Memcached: Add WP_CACHE_KEY_SALT support with precedence: explicit value, existing Secret reference, persisted generated value.
- Memcached: Add memcached.serverGroups for cache-group-specific backend mapping; fallback remains embedded memcached service.
- Memcached: Harden memcached runtime setup via extension bootstrap init container (memcache + memcached) and staged shared libraries.
- Memcached: Enforce memcached plugin drop-in mode (object-cache.php) and avoid normal activation conflicts in init workflow.
- Release channel: beta

## 3.3.1 - 2026-02-18

- Update docker.io/mariadb to b1cb255
- Update mariadb to 0.14.1
- Pull Request: https://github.com/slydlake/helm-charts/pull/137

## 3.3.0 - 2026-02-18

- Update docker.io/mariadb to b1cb255
- Update mariadb to 0.14.1
- Update memcached to 0.10.0
- Pull Request: https://github.com/slydlake/helm-charts/pull/136

## 3.2.0-beta1 - 2026-02-16

- Add support for WordPress Multisite configuration with both subdirectory and subdomain modes, including pruning and renaming of sites in the network
- Multisite: Persistent site tracking via blog_id mapping in wp_sitemeta — enables site slug renames without data loss
- Multisite: Support previousName field for explicit site slug renames with automatic mapping migration
- Multisite: User assignment to specific sites in multisite mode
- Multisite: Plugins network-wide activation, with optional site-specific overrides
- Multisite: Metrics plugin (SlyMetrics) — network-activate in multisite and enable autoupdates by default
- Multisite: Themes network-wide activation, with optional site-specific overrides
- Add support for injecting custom configuration into wp-config.php (e.g. WP_DEBUG, multisite constants, memcached config)
- WordPress debug mode via the Helm values (WORDPRESS_DEBUG constant in wp-config.php) to facilitate troubleshooting and development
- WordPress site URL via the Helm values to ensure correct URL configuration in multisite setups and simplify configuration management
- Remove --force flag from wp plugin/theme install commands - prevents incorrect file ownership (www-data:root) causing unnecessary reinstallations on pod restarts
- Fix stale autoupdate DB entries by replacing old incorrect plugin file paths (full-replace instead of merge)
- Add slug property for URL plugins/themes to enable sites, autoupdate and network activation support
- Auto-prefix http:// or https:// to URL when no protocol is specified (derived from Ingress TLS config) to prevent redirect loops
- Release channel: beta

## 3.2.0 - 2026-02-16

- Add support for WordPress Multisite configuration with both subdirectory and subdomain modes, including pruning and renaming of sites in the network
- Multisite: Persistent site tracking via blog_id mapping in wp_sitemeta — enables site slug renames without data loss
- Multisite: Support previousName field for explicit site slug renames with automatic mapping migration
- Multisite: User assignment to specific sites in multisite mode
- Multisite: Plugins network-wide activation, with optional site-specific overrides
- Multisite: Metrics plugin (SlyMetrics) — network-activate in multisite and enable autoupdates by default
- Multisite: Themes network-wide activation, with optional site-specific overrides
- Add support for injecting custom configuration into wp-config.php (e.g. WP_DEBUG, multisite constants, memcached config)
- WordPress debug mode via the Helm values (WORDPRESS_DEBUG constant in wp-config.php) to facilitate troubleshooting and development
- WordPress site URL via the Helm values to ensure correct URL configuration in multisite setups and simplify configuration management
- Remove --force flag from wp plugin/theme install commands - prevents incorrect file ownership (www-data:root) causing unnecessary reinstallations on pod restarts
- Fix stale autoupdate DB entries by replacing old incorrect plugin file paths (full-replace instead of merge)
- Add slug property for URL plugins/themes to enable sites, autoupdate and network activation support
- Auto-prefix http:// or https:// to URL when no protocol is specified (derived from Ingress TLS config) to prevent redirect loops

## 3.1.2 - 2026-02-16

- Update mariadb to 0.13.6
- Pull Request: https://github.com/slydlake/helm-charts/pull/132

## 3.1.1 - 2026-02-16

- Update mariadb to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/mariadb))
- Pull Request: https://github.com/slydlake/helm-charts/pull/128

## 3.1.0 - 2026-02-13

- Update docker.io/mariadb
- Pull Request: https://github.com/slydlake/helm-charts/pull/121

## 3.0.6 - 2026-02-11

- Update docker.io/mariadb
- Update docker.io/wordpress
- Update docker.io/wordpress
- Update mariadb to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/mariadb))
- Update memcached to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/memcached))
- Pull Request: https://github.com/slydlake/helm-charts/pull/115

## 3.0.5 - 2026-02-11

- Update docker.io/mariadb
- Update docker.io/wordpress
- Update docker.io/wordpress
- Update mariadb to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/mariadb))
- Update memcached to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/memcached))
- Pull Request: https://github.com/slydlake/helm-charts/pull/113

## 3.0.4 - 2026-02-11

- Update docker.io/mariadb
- Update docker.io/wordpress
- Update docker.io/wordpress
- Update mariadb to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/mariadb))
- Update memcached to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/memcached))
- Pull Request: https://github.com/slydlake/helm-charts/pull/113

## 3.0.3 - 2026-02-11

- Update docker.io/mariadb
- Update docker.io/wordpress
- Update docker.io/wordpress
- Update mariadb to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/mariadb))
- Update memcached to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/memcached))
- Pull Request: https://github.com/slydlake/helm-charts/pull/108

## 3.0.2 - 2026-02-12

- Update docker.io/mariadb
- Update docker.io/wordpress
- Update docker.io/wordpress
- Update mariadb to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/mariadb))
- Update memcached to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/memcached))
- Pull Request: https://github.com/slydlake/helm-charts/pull/115

## 3.0.1 - 2026-02-12

- Update docker.io/mariadb
- Update docker.io/wordpress
- Update docker.io/wordpress
- Update mariadb to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/mariadb))
- Update memcached to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/memcached))
- Pull Request: https://github.com/slydlake/helm-charts/pull/115

## 3.0.0 - 2026-02-11

- Split init pipeline into 3 containers: fix-permissions (root), base (non-root), init (non-root)
- Split script library into separate ConfigMap for better modularity and maintainability
- Add dedicated fix-permissions init container for NFS-based PVC ownership (Longhorn RWX)
- Add SIGTERM/SIGINT trap for graceful lock release on container termination
- Add ConfigMap checksum annotation for automatic rollout on init script changes
- Add combined mu-plugins and configmaps checksum annotations
- Add heartbeat-based distributed locking for multi-pod init containers
- Add bootstrap lock using dedicated helm_locks table (before WordPress installation)
- Add automatic stale lock detection (60s without heartbeat) for crash recovery
- sample file composer2.values.yaml for using Composer packages and two replicas with shared storage
- sample file advanced2.values.yaml now uses fixed storageClass longhorn
- Replace wp-cli with direct database queries for much faster initialization. Up to 200% reduction in init time, especially with many plugins.

## 2.1.0 - 2026-02-04

- Update docker.io/lusotycoon/apache-exporter
- Update docker.io/mariadb
- Update docker.io/memcached
- Update mariadb to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/mariadb))
- Update memcached to ([source](https://redirect.github.com/CloudPirates-io/helm-charts/tree/HEAD/charts/memcached))
- Pull Request: https://github.com/slydlake/helm-charts/pull/95

## 2.0.0 - 2025-12-07

- Update docker.io/mariadb to 12.1.2-noble
- Update docker.io/wordpress to 6.9.0-php8.3-apache
- Update docker.io/wordpress to 6.9.0
- Update mariadb to 0.9.0
- Update memcached to 0.7.1
- Pull Request: https://github.com/slydlake/helm-charts/pull/93

## 1.0.2 - 2025-12-07

- fixed base script problem

## 1.0.1 - 2025-12-04

- fixed base script problem

## 1.0.0 - 2025-12-04

- Added Grafana Dashboard auto-deployment feature for WordPress metrics (metrics.wordpress.grafanaDashboard) with automatic discovery via grafana_dashboard label and optional folder organization
- Added WORDPRESS_CONFIG_EXTRA environment variable support to init container for consistent configuration across all containers
- Added wordpress.plugins option to define plugins to be installed via Composer during init.
- Added wordpress.themes option to define themes to be installed via Composer during init.
- Added wordpress.composer.repositories option to configure custom Composer repositories (e.g., private GitHub, Satis, premium plugins). Default repositories (wpackagist.org) are documented in values.yaml
- Added init container support for installing Composer plugins and themes during initialization
- Added wordpress.pluginsPrune option to automatically remove all plugins not defined in wordpress.plugins list during init
- Added wordpress.themesPrune option to automatically remove all themes not defined in wordpress.themes list during init (protects active theme with automatic fallback activation)
- Added samples/composer.values.yaml sample file demonstrating usage of Composer plugins, themes, and custom repositories
- Changed samples/customInit.values.yaml and muPlugins.values.yaml with fixed nodePort for easier testing
- Better startupProbe and livenessProbe initial delays and periods for more reliable container health checking
- Refactored init scripts into modular libraries (lib-core.sh, lib-lock.sh, lib-composer.sh) for better maintainability and testability
- Added DRY_RUN and TEST_MODE support with assert() function for testing init scripts without making changes
- Traditional Helm Repository is deprecated, only OCI-based Helm charts are supported.
- Registry value added. Added functionality to _helpers.tpl to support it.
- Better comments for documentation in values.yaml.

## 0.7.6 - 2025-12-03

- Fixed updating process for wordpress iamge and language installation and updating
- Disabled wordpress auto updates by default in database

## 0.7.5 - 2025-11-29

- cleared image registry names in value.yaml to allow better update handling by Renovate

## 0.7.4 - 2025-11-28

- Release 0.7.4

## 0.7.3 - 2025-11-19

- Release 0.7.3

## 0.7.2 - 2025-11-19

- Release 0.7.2

## 0.7.1 - 2025-11-19

- Update docker.io/wordpress to ed5d7a7
- Pull Request: https://github.com/slydlake/helm-charts/pull/77

## 0.7.0 - 2025-11-19

- Improved base and init container.
- Added support for MU-Plugins via ConfigMaps. See samples/muPlugins.* for example.
- Added support for custom commands in Init container via ConfigMap. See samples/customInit.* for example.
- Improved handling of table prefix during initialization locking.
- Checks if database is initialized, without Init Mode.
- Removing the metrics plugin support.
- More debug logging for init container.

## 0.6.13 - 2025-11-18

- Race condition during WordPress init fixed.

## 0.6.12 - 2025-11-18

- Race condition during WordPress init fixed.

## 0.6.11 - 2025-11-18

- Race condition during WordPress init fixed.

## 0.6.10 - 2025-11-18

- Race condition during WordPress init fixed.

## 0.6.9 - 2025-11-18

- Update docker.io/memcached to 4737e17
- Update docker.io/wordpress to 7703e57
- Update mariadb to 0.7.0
- Pull Request: https://github.com/slydlake/helm-charts/pull/69

## 0.6.8 - 2025-11-17

- Update memcached to v0.7.0
- Pull Request: https://github.com/slydlake/helm-charts/pull/68

## 0.6.7 - 2025-11-17

- Fixed race condition in multi-replica deployments causing plugin installation failures. Implemented database table-based distributed locking mechanism to ensure only one pod runs init operations at a time.
- Added a new sample values file: samples/advanced2.values.yaml with multiple replicas.

## 0.6.6 - 2025-11-14

- Update docker.io/mariadb:12.0.2-noble to 607835c
- Pull Request: https://github.com/slydlake/helm-charts/pull/67

## 0.6.5 - 2025-11-13

- Update mariadb to 0.6.1
- Update memcached to 0.6.0
- Pull Request: https://github.com/slydlake/helm-charts/pull/66

## 0.6.4 - 2025-11-10

- Update docker.io/mariadb:12.0.2-noble to 439d77b
- Pull Request: https://github.com/slydlake/helm-charts/pull/65

## 0.6.3 - 2025-11-09

- Fixed .htaccess updates with ConfigMap if already exists in PV.

## 0.6.2 - 2025-11-09

- Fixed .htaccess WordPress rewrite rules injection by implementing persistent volume storage and intelligent init container logic

## 0.6.1 - 2025-11-08

- Removed maintenance mode from init script to enable zero downtime deployments with multiple replicas

## 0.6.0 - 2025-11-08

- Add configurable ports and secretKey to WordPress ServiceMonitor for flexible metrics scraping on HTTP/HTTPS endpoints. By default only HTTP port is scraped.
- When using WordPress metrics plugin, in init container always rewrite flush

## 0.5.6 - 2025-11-08

- Fixed 'imagePullSecrets' schema to expect array of objects instead of strings (thanks @ScionOfDesign)
- Update docker.io/wordpress to 67ec86e
- Update memcached to 0.5.3
- Pull Request: https://github.com/slydlake/helm-charts/pull/64

## 0.5.4 - 2025-11-06

- Update docker.io/wordpress to 67ec86e
- Update memcached to 0.5.3
- Pull Request: https://github.com/slydlake/helm-charts/pull/63

## 0.5.3 - 2025-11-06

- Add HTTPS endpoint to WordPress ServiceMonitor for metrics collection on both HTTP and HTTPS ports.

## 0.5.2 - 2025-11-04

- Optimize init script performance: batch plugin/theme checks and installations for many plugins/themes.

## 0.5.1 - 2025-11-04

- Update docker.io/memcached to 050de63
- Update docker.io/wordpress to 23efd69
- Update memcached to 0.5.2
- Pull Request: https://github.com/slydlake/helm-charts/pull/61

## 0.5.0 - 2025-11-03

- Add theme installation support with batch operations and ZIP URL support
- Optimize plugin/theme installation performance with batch operations

## 0.4.7 - 2025-11-01

- Update memcached to v0.5.0
- Pull Request: https://github.com/slydlake/helm-charts/pull/60

## 0.4.6 - 2025-10-31

- Update mariadb to 0.6.0
- Update memcached to 0.4.0
- Pull Request: https://github.com/slydlake/helm-charts/pull/59

## 0.4.5 - 2025-10-30

- Provided better samples for the first start. Readme help a lot more for first installation.

## 0.4.4 - 2025-10-27

- removed the digest from deployment manifests to use it directly from the tag

## 0.4.3 - 2025-10-27

- Update docker.io/mariadb to 5b6a1ea
- Update docker.io/memcached to edbe8e8
- Update lusotycoon/apache-exporter to v1.0.11
- Pull Request: https://github.com/slydlake/helm-charts/pull/53

## 0.4.2 - 2025-10-26

- [docker.io/wordpress] chore(deps): update docker.io/wordpress:6.8.3-php8.1-apache Docker digest to 75f79f9
- Pull Request: https://github.com/slydlake/helm-charts/pull/43

## 0.4.1 - 2025-10-26

- [docker.io/lusotycoon/apache-exporter] chore(deps): update docker.io/lusotycoon/apache-exporter Docker tag to v1.0.11
- Pull Request: https://github.com/slydlake/helm-charts/pull/45

## 0.4.0 - 2025-10-26

- refactor: updated liveness, readiness, and startup probe timings for better stability
- fix: pod restart when updating configmaps via checksums
- refactor: removed .digest values from image definitions for CI pipeline compatibility. Use image tags with digests instead.

## 0.3.2 - 2025-10-25

- [helm] chore(deps): update chart dependencies mariadb Docker tag to v0.5.2
- Pull Request: https://github.com/slydlake/helm-charts/pull/35

## 0.3.1 - 2025-10-24

- [helm] chore(deps): update chart dependencies memcached Docker tag to v0.3.2
- Pull Request: https://github.com/slydlake/helm-charts/pull/36

## 0.3.0 - 2025-10-21

- chore(feat): added configExtraConfigMap and configExtraSecret support for wp-config.php customization

## 0.2.22 - 2025-10-20

- chore(fix): values.schema.json - simpler externalDatabase validation

## 0.2.21 - 2025-10-20

- chore(fix): values.schema.json - allow for some values integer or null

## 0.2.20 - 2025-10-20

- chore(fix): values.yaml - empty strings instead of null

## 0.2.19 - 2025-10-15

- [helm] chore(deps): update chart dependencies mariadb Docker tag to v0.5.1
- Pull Request: https://github.com/slydlake/helm-charts/pull/31

## 0.2.18 - 2025-10-15

- [helm] chore(deps): update chart dependencies memcached Docker tag to v0.3.1
- Pull Request: https://github.com/slydlake/helm-charts/pull/30

## 0.2.17 - 2025-10-15

- [helm] chore(deps): update chart dependencies mariadb Docker tag to v0.5.0
- Pull Request: https://github.com/slydlake/helm-charts/pull/29

## 0.2.16 - 2025-10-13

- [helm] chore(deps): update chart dependencies mariadb Docker tag to v0.3.5
- Pull Request: https://github.com/slydlake/helm-charts/pull/27

## 0.2.15 - 2025-10-13

- [helm] chore(deps): update chart dependencies memcached Docker tag to v0.2.3
- Pull Request: https://github.com/slydlake/helm-charts/pull/28

## 0.2.14 - 2025-10-12

- readme info about decrepation of helm chart releases, use OCI registry instead.

## 0.2.13 - 2025-10-11

- [helm] chore(deps): update chart dependencies memcached Docker tag to v0.2.2
- Pull Request: https://github.com/slydlake/helm-charts/pull/26

## 0.2.12 - 2025-10-11

- [helm] chore(deps): update chart dependencies mariadb Docker tag to v0.3.4
- Pull Request: https://github.com/slydlake/helm-charts/pull/25

## 0.2.11 - 2025-10-09

- Updates 'externalDatabase.existingSecret' and 'wordpress.init' to be able to use customizable keys (thanks to ScionOfDesign)
- No longer requires that externalDatabase.username be defined if an external secret is specified (thanks to ScionOfDesign)
- Ensures that the host and database user are passed into the Wordpress container as environment variables when an external secret is used (thanks to ScionOfDesign)

## 0.2.10 - 2025-10-08

- extraEnvVars are now working in wodpress deployment (thanks to ScionOfDesign)
- secret value database name (thanks to ScionOfDesign)
- uses WORDPRESS_ env variables if defined in values.yaml (thanks to ScionOfDesign)

## 0.2.9 - 2025-10-07

- wordpress bumped to 6.8.3-php8.1-apache
- memcached chart update
- mariadb chart update

## 0.2.8 - 2025-10-06

- memcached chart update
- mariadb chart update

## 0.2.7 - 2025-09-29

- Added Ingress and extraRules support
- Readme: Added note about default WordPress installation
- If WordPress is already installed, the log will show this

## 0.2.6 - 2025-09-27

- Wordpress CLI image version can now be set
- Detailed comments for all values
- Pinned all images to specific tags and digests to improve security
- Pinned chart dependencies to specific versions
- ImagePullPolicy for all images set to IfNotPresent

## 0.2.5 - 2025-09-21

- Improved ServiceMonitor namespace isolation for WordPress metrics

## 0.2.4 - 2025-09-21

- Added namespaceSelector to ServiceMonitors to prevent cross-namespace scraping conflicts and Target Down alerts

## 0.2.3 - 2025-09-18

- artifacthub verification metadata

## 0.2.2 - 2025-09-18

- sample values, secrets and configmaps moved to separate folder

## 0.2.1 - 2025-09-18

- signed the chart with cosign

## 0.2.0 - 2025-09-17

- added support for custom configmaps for apache and php configurations as well as .htaccess file
- signed the chart with cosign

## 0.1.3 - 2025-09-16

- fixed chart links for artifacthub

## 0.1.2 - 2025-09-16

- fixed chart links for artifacthub

## 0.1.1 - 2025-09-16

- fixed chart links

## 0.1.0 - 2025-09-16

- fixed chart links
