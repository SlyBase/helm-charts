{{- define "wordpress.podTemplate" }}
    metadata:
      annotations:
        {{- if .Values.podAnnotations }}
{{- toYaml .Values.podAnnotations | nindent 6 }}
        {{- end }}
        {{- if .Values.extraEnvVarsCM }}
          {{- $name := .Values.extraEnvVarsCM }}
          {{- $cm := lookup "v1" "ConfigMap" .Release.Namespace $name }}
          {{- if $cm }}
        checksum/extraEnvVarsCM: {{ toJson $cm.data | sha256sum }}
          {{- else }}
        checksum/extraEnvVarsCM: {{ $name | sha256sum }}
          {{- end }}
        {{- end }}

        {{- if .Values.wordpress.configExtraConfigMap.name }}
          {{- $name := .Values.wordpress.configExtraConfigMap.name }}
          {{- $cm := lookup "v1" "ConfigMap" .Release.Namespace $name }}
          {{- if $cm }}
        checksum/wordpress-configExtraConfigMap: {{ toJson $cm.data | sha256sum }}
          {{- else }}
        checksum/wordpress-configExtraConfigMap: {{ $name | sha256sum }}
          {{- end }}
        {{- end }}

        {{- if .Values.wordpress.configExtraSecret.name }}
          {{- $name := .Values.wordpress.configExtraSecret.name }}
          {{- $secret := lookup "v1" "Secret" .Release.Namespace $name }}
          {{- if $secret }}
        checksum/wordpress-configExtraSecret: {{ toJson $secret.data | sha256sum }}
          {{- else }}
        checksum/wordpress-configExtraSecret: {{ $name | sha256sum }}
          {{- end }}
        {{- end }}

        {{- if .Values.wordpress.htaccessConfigMap }}
          {{- $name := .Values.wordpress.htaccessConfigMap }}
          {{- $cm := lookup "v1" "ConfigMap" .Release.Namespace $name }}
          {{- if $cm }}
        checksum/wordpress-htaccessConfigMap: {{ toJson $cm.data | sha256sum }}
          {{- else }}
        checksum/wordpress-htaccessConfigMap: {{ $name | sha256sum }}
          {{- end }}
        {{- end }}

        {{- if .Values.apache.customDefaultSiteConfigMap }}
          {{- $name := .Values.apache.customDefaultSiteConfigMap }}
          {{- $cm := lookup "v1" "ConfigMap" .Release.Namespace $name }}
          {{- if $cm }}
        checksum/apache-customDefaultSiteConfigMap: {{ toJson $cm.data | sha256sum }}
          {{- else }}
        checksum/apache-customDefaultSiteConfigMap: {{ $name | sha256sum }}
          {{- end }}
        {{- end }}

        {{- if .Values.apache.customPortsConfigMap }}
          {{- $name := .Values.apache.customPortsConfigMap }}
          {{- $cm := lookup "v1" "ConfigMap" .Release.Namespace $name }}
          {{- if $cm }}
        checksum/apache-customPortsConfigMap: {{ toJson $cm.data | sha256sum }}
          {{- else }}
        checksum/apache-customPortsConfigMap: {{ $name | sha256sum }}
          {{- end }}
        {{- end }}

        {{- if .Values.apache.customPhpConfigMap }}
          {{- $name := .Values.apache.customPhpConfigMap }}
          {{- $cm := lookup "v1" "ConfigMap" .Release.Namespace $name }}
          {{- if $cm }}
        checksum/apache-customPhpConfigMap: {{ toJson $cm.data | sha256sum }}
          {{- else }}
        checksum/apache-customPhpConfigMap: {{ $name | sha256sum }}
          {{- end }}
        {{- end }}

        {{- if .Values.wordpress.init.customInitConfigMap.name }}
          {{- $name := .Values.wordpress.init.customInitConfigMap.name }}
          {{- $cm := lookup "v1" "ConfigMap" .Release.Namespace $name }}
          {{- if $cm }}
        checksum/wordpress-init-customInitConfigMap: {{ toJson $cm.data | sha256sum }}
          {{- else }}
        checksum/wordpress-init-customInitConfigMap: {{ $name | sha256sum }}
          {{- end }}
        {{- end }}

        {{- range .Values.wordpress.muPluginsConfigMaps }}
          {{- $name := .name }}
          {{- $cm := lookup "v1" "ConfigMap" $.Release.Namespace $name }}
          {{- if $cm }}
        checksum/wordpress-muPlugins-{{ $name }}: {{ toJson $cm.data | sha256sum }}
          {{- else }}
        checksum/wordpress-muPlugins-{{ $name }}: {{ $name | sha256sum }}
          {{- end }}
        {{- end }}
        {{- /* combined muPlugins checksum */}}
        {{- $muChecks := list -}}
        {{- range .Values.wordpress.muPluginsConfigMaps }}
          {{- $muChecks = append $muChecks (include "wordpress.checksum.lookup" (list .name $.Release.Namespace)) }}
        {{- end }}
        {{- if gt (len $muChecks) 0 }}
        checksum/wordpress-muPlugins-combined: {{ include "wordpress.checksum.combine" (list $muChecks) }}
        {{- end }}
        {{- if .Values.wordpress.smtp.enabled }}
        checksum/smtp-config: {{ toJson .Values.wordpress.smtp | sha256sum }}
        {{- end }}

        {{- /* combined configmaps checksum */}}
        {{- $allChecks := list -}}
        {{- if .Values.extraEnvVarsCM }}
          {{- $allChecks = append $allChecks (include "wordpress.checksum.lookup" (list .Values.extraEnvVarsCM $.Release.Namespace)) }}
        {{- end }}
        {{- if .Values.wordpress.htaccessConfigMap }}
          {{- $allChecks = append $allChecks (include "wordpress.checksum.lookup" (list .Values.wordpress.htaccessConfigMap $.Release.Namespace)) }}
        {{- end }}
        {{- if .Values.wordpress.configExtraConfigMap.name }}
          {{- $allChecks = append $allChecks (include "wordpress.checksum.lookup" (list .Values.wordpress.configExtraConfigMap.name $.Release.Namespace)) }}
        {{- end }}
        {{- if .Values.apache.customDefaultSiteConfigMap }}
          {{- $allChecks = append $allChecks (include "wordpress.checksum.lookup" (list .Values.apache.customDefaultSiteConfigMap $.Release.Namespace)) }}
        {{- end }}
        {{- if .Values.apache.customPortsConfigMap }}
          {{- $allChecks = append $allChecks (include "wordpress.checksum.lookup" (list .Values.apache.customPortsConfigMap $.Release.Namespace)) }}
        {{- end }}
        {{- if .Values.apache.customPhpConfigMap }}
          {{- $allChecks = append $allChecks (include "wordpress.checksum.lookup" (list .Values.apache.customPhpConfigMap $.Release.Namespace)) }}
        {{- end }}
        {{- if gt (len $allChecks) 0 }}
        checksum/wordpress-configmaps-combined: {{ include "wordpress.checksum.combine" (list $allChecks) }}
        {{- end }}

        # Checksum of the chart-generated init-scripts ConfigMap to trigger rollout on script changes
        checksum/init-scripts: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "wordpress.labels" . | nindent 8 }}
        {{- with .Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "wordpress.serviceAccountName" . }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if .Values.dnsPolicy }}
      dnsPolicy: {{ .Values.dnsPolicy }}
      {{- end }}
      {{- with .Values.dnsConfig }}
      dnsConfig:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if .Values.hostNetwork }}
      hostNetwork: {{ .Values.hostNetwork }}
      {{- end }}
      initContainers:
        {{- if and (has "ReadWriteMany" .Values.storage.accessModes) (ne .Values.controllerType "statefulset") }}
        # Fixes PVC ownership for RWX shared storage (NFS, Longhorn, CephFS, etc.)
        # that doesn't respect Kubernetes fsGroup settings.
        # Requires root user because DAC_OVERRIDE cannot change ownership of root-owned
        # directories (e.g., lost+found) on network storage.
        # Only for Deployment + ReadWriteMany. StatefulSet provisions fresh per-Pod
        # RWO volumes where fsGroup is honoured by the CSI driver — no chown needed.
        - name: {{ .Chart.Name }}-rwx-permissions
          image: {{ include "slycharts.image" (dict "image" .Values.image "defaultTag" .Chart.AppVersion) }}
          securityContext:
            runAsUser: 0
            runAsNonRoot: false
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            privileged: false
            capabilities:
              drop: ["ALL"]
              add: ["CHOWN", "DAC_OVERRIDE"]
            seccompProfile:
              type: RuntimeDefault
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command: ["sh", "-c", "chown -R {{ .Values.podSecurityContext.runAsUser | default 33 }}:{{ .Values.podSecurityContext.fsGroup | default 33 }} /tmp/wordpress && echo 'PVC ownership fixed!'"]
          volumeMounts:
            {{- include "wordpress.dataVolumeMounts" (dict "ctx" . "path" "/tmp/wordpress") | nindent 12 }}
        {{- end }}
        - name: {{ .Chart.Name }}-base
          image: {{ include "slycharts.image" (dict "image" .Values.image "defaultTag" .Chart.AppVersion) }}
          {{- with .Values.containerSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            - name: WORDPRESS_DEBUG
              value: "false"
          command:
          - sh
          - -c
          - |
            # copy your base.sh and run it
            cp /scripts/base.sh /tmp/base.sh
            chmod +x /tmp/base.sh
            /tmp/base.sh

            # copy and run htaccess-setup.sh
            cp /scripts/htaccess-setup.sh /tmp/htaccess-setup.sh
            chmod +x /tmp/htaccess-setup.sh
            /tmp/htaccess-setup.sh

            # Prepare library scripts for init container
            mkdir -p /tmp/lib
            cp /scripts/lib-core.sh /tmp/lib/lib-core.sh
            cp /scripts/lib-composer.sh /tmp/lib/lib-composer.sh
            cp /scripts/lib-lock.sh /tmp/lib/lib-lock.sh
            chmod +x /tmp/lib/*.sh
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            {{- include "wordpress.dataVolumeMounts" (dict "ctx" . "path" "/tmp/wordpress") | nindent 12 }}
            # Mount ConfigMap outside of /tmp to avoid being hidden by emptyDir
            - name: {{ include "wordpress.fullname" . }}-init
              mountPath: /scripts
              readOnly: true
            - name: {{ include "wordpress.fullname" . }}-configfiles
              mountPath: /configfiles
            {{- range .Values.wordpress.muPluginsConfigMaps }}
            - name: mu-plugins-{{ .name }}
              mountPath: /tmp/mu-plugins-{{ .name }}
            {{- end }}
        - name: {{ .Chart.Name }}-init
          image: {{ include "slycharts.image" (dict "image" .Values.wordpress.init.image) }}
          {{- with .Values.containerSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          imagePullPolicy: {{ .Values.wordpress.init.image.pullPolicy | default .Values.wordpress.init.pullPolicy | default "IfNotPresent" }}
          command:
            - sh
            - -c
            - |
              # Libraries are prepared by base container in /tmp/lib/
              # Copy and run init.sh from ConfigMap
              cp /scripts/init.sh /tmp/init.sh
              chmod +x /tmp/init.sh
              /tmp/init.sh
          envFrom:
          {{- if or .Values.extraEnvVarsCM .Values.extraEnvVarsSecret }}
            {{- if .Values.extraEnvVarsCM }}
            - configMapRef:
                name: {{ .Values.extraEnvVarsCM }}
            {{- end }}
            {{- if .Values.extraEnvVarsSecret }}
            - secretRef:
                name: {{ .Values.extraEnvVarsSecret }}
            {{- end }}
          {{- end }}
          {{- $cacheBackends := (include "wordpress.cache.backends" . | fromYaml) }}
          {{- $cacheMeta := dict "createConfig" false "authEnabled" false "authPassword" "" "authExistingSecret" "" "authExistingSecretPasswordKey" "" }}
          {{- if or (eq $cacheBackends.selected "redis") (eq $cacheBackends.selected "valkey") }}
          {{- $cacheMeta = (include "wordpress.cache.kvMeta" (dict "ctx" . "backend" $cacheBackends.selected) | fromYaml) }}
          {{- end }}
          env:
            - name: WORDPRESS_PATH
              value: /var/www/html
            - name: WP_CLI_CACHE_DIR
              value: /tmp/wp-cli-cache
            {{- if and (or (eq $cacheBackends.selected "redis") (eq $cacheBackends.selected "valkey")) $cacheMeta.createConfig $cacheMeta.authEnabled }}
            {{- if $cacheMeta.authPassword }}
            - name: WP_REDIS_PASSWORD
              value: {{ $cacheMeta.authPassword | quote }}
            {{- else if $cacheMeta.authExistingSecret }}
            - name: WP_REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ $cacheMeta.authExistingSecret }}
                  key: {{ $cacheMeta.authExistingSecretPasswordKey }}
            {{- end }}
            {{- end }}
            - name: DEBUG
              value: {{ .Values.wordpress.init.debug | default "false" | quote }}
            - name: WORDPRESS_TABLE_PREFIX
              value: {{ .Values.wordpress.tablePrefix| default "wp_" | quote }}
            - name: WP_URL
              value: {{ include "wordpress.normalizedUrl" . | quote }}
            - name: WORDPRESS_METRICS
              value: {{ include "metrics.wordpress.pluginname" . }}
            - name: WP_LOCALE
              value: {{ .Values.wordpress.language | quote }}
            - name: WP_INIT
              value: {{ .Values.wordpress.init.enabled | quote }}
            {{- $permalinkStructures := dict "plain" "" "dayAndName" "/%year%/%monthnum%/%day%/%postname%/" "monthAndName" "/%year%/%monthnum%/%postname%/" "numeric" "/archives/%post_id%/" "postName" "/%postname%/" -}}
            {{- if .Values.wordpress.permalinks.customStructure }}
            - name: WP_PERMALINK_STRUCTURE
              value: {{ .Values.wordpress.permalinks.customStructure | quote }}
            {{- else if .Values.wordpress.permalinks.structure }}
            - name: WP_PERMALINK_STRUCTURE
              value: {{ index $permalinkStructures .Values.wordpress.permalinks.structure | quote }}
            {{- end }}
            {{- if .Values.mariadb.enabled }}
            - name: WORDPRESS_DB_HOST
              value: {{ include "wordpress.mariadb.fullname" . | default "mariadb" }}
            - name: WORDPRESS_DB_NAME
              value: {{ .Values.mariadb.auth.database | quote }}
            - name: WORDPRESS_DB_USER
              value: {{ .Values.mariadb.auth.username | quote }}
            - name: WORDPRESS_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ if .Values.mariadb.auth.existingSecret }}{{ .Values.mariadb.auth.existingSecret }}{{ else }}{{ include "wordpress.mariadb.fullname" . }}{{ end }}
                  key: {{ .Values.mariadb.auth.secretKeys.userPasswordKey | default "mariadb-password" }}
            {{- else if (not .Values.mariadb.enabled ) }}
            - name: WORDPRESS_DB_HOST
              value: {{ .Values.externalDatabase.host | quote }}
            - name: WORDPRESS_DB_NAME
              value: {{ .Values.externalDatabase.database | quote }}
            {{- if .Values.externalDatabase.existingSecret }}
            - name: WORDPRESS_DB_USER
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.externalDatabase.existingSecret }}
                  key: {{ .Values.externalDatabase.secretKeys.userUsernameKey | default "db.username" }}
            - name: WORDPRESS_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.externalDatabase.existingSecret }}
                  key: {{ .Values.externalDatabase.secretKeys.userPasswordKey | default "db.password" }}
            {{- else }}
            - name: WORDPRESS_DB_USER
              value: {{ .Values.externalDatabase.username | quote }}
            - name: WORDPRESS_DB_PASSWORD
              value: {{ .Values.externalDatabase.password | quote }}
            {{- end }}
            {{- end }}
            {{- if .Values.wordpress.init.enabled }}
            - name: WP_TITLE
              value: {{ .Values.wordpress.init.title | default "New Blog" | quote }}
            - name: WP_ADMIN_USER
              valueFrom:
                secretKeyRef:
                  name: {{ if .Values.wordpress.init.existingSecret }}{{ .Values.wordpress.init.existingSecret }}{{ else }}{{ include "wordpress.fullname" . }}-init{{ end }}
                  key: {{ .Values.wordpress.init.secretKeys.userUsernameKey | default "wordpress.username" }}
            - name: WP_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ if .Values.wordpress.init.existingSecret }}{{ .Values.wordpress.init.existingSecret }}{{ else }}{{ include "wordpress.fullname" . }}-init{{ end }}
                  key: {{ .Values.wordpress.init.secretKeys.userPasswordKey | default "wordpress.password" }}
            - name: WP_ADMIN_EMAIL
              valueFrom:
                secretKeyRef:
                  name: {{ if .Values.wordpress.init.existingSecret }}{{ .Values.wordpress.init.existingSecret }}{{ else }}{{ include "wordpress.fullname" . }}-init{{ end }}
                  key: {{ .Values.wordpress.init.secretKeys.userEmailKey | default "wordpress.email" }}
            {{- if .Values.wordpress.init.firstname }}
            - name: WP_ADMIN_FIRSTNAME
              value: {{ .Values.wordpress.init.firstname | quote }}
            {{- end }}
            {{- if .Values.wordpress.init.lastname }}
            - name: WP_ADMIN_LASTNAME
              value: {{ .Values.wordpress.init.lastname | quote }}
            {{- end }}
            {{- if .Values.wordpress.init.title }}
            - name: WP_INIT_TITLE
              value: {{ .Values.wordpress.init.title | quote }}
            {{- end }}
            {{- if .Values.wordpress.init.multiSites.enabled }}
            - name: WP_MULTISITE_ENABLED
              value: "true"
            - name: WP_MULTISITE_TITLE
              value: {{ .Values.wordpress.init.multiSites.title | default .Values.wordpress.init.title | quote }}
            - name: WP_MULTISITE_SUBDOMAIN
              value: {{ .Values.wordpress.init.multiSites.subdomain | quote }}
            - name: WP_MULTISITE_PRUNE
              value: {{ .Values.wordpress.init.multiSites.prune | quote }}
            {{- if .Values.wordpress.init.multiSites.sites }}
            - name: WP_MULTISITE_SITES
              value: {{ .Values.wordpress.init.multiSites.sites | toJson | quote }}
            {{- end }}
            {{- end }}
            {{- end }}
            {{- if .Values.wordpress.init.jwt.enabled }}
            - name: JWT_AUTH_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  {{- if .Values.wordpress.init.jwt.existingSecret }}
                  name: {{ .Values.wordpress.init.jwt.existingSecret }}
                  key: {{ .Values.wordpress.init.jwt.secretKey | default "JWT_AUTH_SECRET_KEY" }}
                  {{- else }}
                  name: {{ include "wordpress.fullname" . }}-jwt
                  key: JWT_AUTH_SECRET_KEY
                  {{- end }}
            {{- end }}
          {{- if and .Values.wordpress.configExtraConfigMap.name (not .Values.wordpress.configExtraSecret.name) }}
          {{- if .Values.wordpress.configExtraInject }}
          {{/* Combine external ConfigMap + chart-managed inject via K8s env var interpolation */}}
            - name: _WP_CONFIG_INJECT
              valueFrom:
                secretKeyRef:
                  name: {{ include "wordpress.fullname" . }}
                  key: _WP_CONFIG_INJECT
            - name: _WP_CONFIG_USER
              valueFrom:
                configMapKeyRef:
                  name: {{ .Values.wordpress.configExtraConfigMap.name }}
                  key: {{ .Values.wordpress.configExtraConfigMap.key | default "wordpress.configExtra" }}
            - name: WORDPRESS_CONFIG_EXTRA
              value: "$(_WP_CONFIG_USER)$(_WP_CONFIG_INJECT)"
          {{- else }}
            - name: WORDPRESS_CONFIG_EXTRA
              valueFrom:
                configMapKeyRef:
                  name: {{ .Values.wordpress.configExtraConfigMap.name }}
                  key: {{ .Values.wordpress.configExtraConfigMap.key | default "wordpress.configExtra" }}
          {{- end }}
          {{- end }}
          {{- if .Values.wordpress.configExtraSecret.name }}
          {{- if .Values.wordpress.configExtraInject }}
          {{/* Combine external Secret + chart-managed inject via K8s env var interpolation */}}
            - name: _WP_CONFIG_INJECT
              valueFrom:
                secretKeyRef:
                  name: {{ include "wordpress.fullname" . }}
                  key: _WP_CONFIG_INJECT
            - name: _WP_CONFIG_USER
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.wordpress.configExtraSecret.name }}
                  key: {{ .Values.wordpress.configExtraSecret.key | default "wordpress.configExtra" }}
            - name: WORDPRESS_CONFIG_EXTRA
              value: "$(_WP_CONFIG_USER)$(_WP_CONFIG_INJECT)"
          {{- else }}
            - name: WORDPRESS_CONFIG_EXTRA
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.wordpress.configExtraSecret.name }}
                  key: {{ .Values.wordpress.configExtraSecret.key | default "wordpress.configExtra" }}
          {{- end }}
          {{- end }}
          volumeMounts:
            {{- include "wordpress.dataVolumeMounts" (dict "ctx" . "path" "/var/www/html") | nindent 12 }}
            - name: tmp
              mountPath: /tmp
            # Mount ConfigMap outside of /tmp
            - name: {{ include "wordpress.fullname" . }}-init
              mountPath: /scripts
              readOnly: true
            {{- if .Values.wordpress.init.customInitConfigMap.name }}
            - name: custom-init-commands
              mountPath: /tmp/custom-init-commands
            {{- end }}
        {{- if .Values.memcached.enabled }}
        - name: {{ .Chart.Name }}-memcached-bootstrap
          image: {{ include "slycharts.image" (dict "image" .Values.image "defaultTag" .Chart.AppVersion) }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          securityContext:
            runAsUser: 0
            runAsNonRoot: false
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
              add:
                - CHOWN
                - DAC_OVERRIDE
                - FOWNER
                - SETGID
                - SETUID
            seccompProfile:
              type: RuntimeDefault
          env:
            - name: DEBUG
              value: {{ .Values.wordpress.init.debug | default "false" | quote }}
          command:
            - sh
            - -ec
            - |
              echo "Memcached bootstrap: installation startet..."
              export DEBIAN_FRONTEND=noninteractive
              cat >/etc/apt/apt.conf.d/99sandboxroot <<'EOF'
              APT::Sandbox::User "root";
              EOF
              if [ "${DEBUG:-false}" = "true" ]; then
                apt-get update
                apt-get install -y --no-install-recommends libmemcached-dev zlib1g-dev libsasl2-dev libzstd-dev
                pecl install memcached
                pecl install memcache
              else
                apt-get update >/dev/null
                apt-get install -y --no-install-recommends libmemcached-dev zlib1g-dev libsasl2-dev libzstd-dev >/dev/null
                pecl install memcached >/dev/null
                pecl install memcache >/dev/null
              fi
              mkdir -p /opt/php-ext/conf.d /opt/php-ext/lib
              EXT_DIR="$(php-config --extension-dir)"
              cp "${EXT_DIR}/memcache.so" /opt/php-ext/memcache.so
              cp "${EXT_DIR}/memcached.so" /opt/php-ext/memcached.so
              ldd "${EXT_DIR}/memcached.so" | awk '/=> \/.*/ {print $3} /^\/.*/ {print $1}' | sed 's/[[:space:]]*$//' | sort -u | while read -r lib; do
                [ -f "$lib" ] && cp -L "$lib" /opt/php-ext/lib/
              done
              echo "extension=/opt/php-ext/memcache.so" > /opt/php-ext/conf.d/zz-memcache.ini
              echo "extension=/opt/php-ext/memcached.so" > /opt/php-ext/conf.d/zz-memcached.ini
              PHP_INI_SCAN_DIR="/usr/local/etc/php/conf.d:/opt/php-ext/conf.d" LD_LIBRARY_PATH="/opt/php-ext/lib" php -m | grep -qi '^memcache$' || { echo "ERROR: memcache extension failed to load"; exit 1; }
              PHP_INI_SCAN_DIR="/usr/local/etc/php/conf.d:/opt/php-ext/conf.d" LD_LIBRARY_PATH="/opt/php-ext/lib" php -m | grep -qi '^memcached$' || { echo "ERROR: memcached extension failed to load"; exit 1; }
              if [ -f /var/www/html/wp-content/plugins/memcached/object-cache.php ]; then
                cp /var/www/html/wp-content/plugins/memcached/object-cache.php /var/www/html/wp-content/object-cache.php
              fi
              echo "Memcached bootstrap: installation beendet."
              rm -f /etc/apt/apt.conf.d/99sandboxroot
              rm -rf /var/lib/apt/lists/*
          volumeMounts:
            - name: wordpress-memcached-ext
              mountPath: /opt/php-ext
            {{- include "wordpress.dataVolumeMounts" (dict "ctx" . "path" "/var/www/html") | nindent 12 }}
        {{- end }}
      {{- if .Values.initContainers }}
        {{- toYaml .Values.initContainers | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          {{- with .Values.containerSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          image: {{ include "slycharts.image" (dict "image" .Values.image "defaultTag" .Chart.AppVersion) }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          {{- if .Values.command }}
          command:
            {{- toYaml .Values.command | nindent 12 }}
          {{- end }}
          {{- if .Values.args }}
          args:
            {{- toYaml .Values.args | nindent 12 }}
          {{- end }}
          env:
          {{- if .Values.extraEnvVars }}
          {{- toYaml .Values.extraEnvVars | nindent 12 }}
          {{- end }}
          {{- $cacheBackends := (include "wordpress.cache.backends" . | fromYaml) }}
          {{- $cacheMeta := dict "createConfig" false "authEnabled" false "authPassword" "" "authExistingSecret" "" "authExistingSecretPasswordKey" "" }}
          {{- if or (eq $cacheBackends.selected "redis") (eq $cacheBackends.selected "valkey") }}
          {{- $cacheMeta = (include "wordpress.cache.kvMeta" (dict "ctx" . "backend" $cacheBackends.selected) | fromYaml) }}
          {{- end }}
          {{- if .Values.memcached.enabled }}
            - name: PHP_INI_SCAN_DIR
              value: "/usr/local/etc/php/conf.d:/opt/php-ext/conf.d"
            - name: LD_LIBRARY_PATH
              value: "/opt/php-ext/lib"
          {{- end }}
            - name: WP_HOME
              value: {{ include "wordpress.normalizedUrl" . | quote }}
            - name: WP_SITEURL
              value: {{ include "wordpress.normalizedUrl" . | quote }}
          {{- if and (or (eq $cacheBackends.selected "redis") (eq $cacheBackends.selected "valkey")) $cacheMeta.createConfig $cacheMeta.authEnabled }}
          {{- if $cacheMeta.authPassword }}
            - name: WP_REDIS_PASSWORD
              value: {{ $cacheMeta.authPassword | quote }}
          {{- else if $cacheMeta.authExistingSecret }}
            - name: WP_REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ $cacheMeta.authExistingSecret }}
                  key: {{ $cacheMeta.authExistingSecretPasswordKey }}
          {{- end }}
          {{- end }}
          {{ if .Values.wordpress.debug }}
            - name: WORDPRESS_DEBUG
              value: "true"
          {{- end }}
          {{ if .Values.mariadb.enabled }}
            - name: WORDPRESS_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{if .Values.mariadb.auth.existingSecret}} {{ .Values.mariadb.auth.existingSecret }} {{ else }} {{ include "wordpress.mariadb.fullname" . }} {{ end }}
                  key: {{ .Values.mariadb.auth.secretKeys.userPasswordKey }}
          {{- else if (not .Values.mariadb.enabled ) }}
            - name: WORDPRESS_DB_HOST
              value: {{ .Values.externalDatabase.host | quote }}
            - name: WORDPRESS_DB_NAME
              value: {{ .Values.externalDatabase.database | quote }}
          {{- if .Values.externalDatabase.existingSecret }}
            - name: WORDPRESS_DB_USER
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.externalDatabase.existingSecret }}
                  key: {{ .Values.externalDatabase.secretKeys.userUsernameKey | default "db.username" }}
            - name: WORDPRESS_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.externalDatabase.existingSecret }}
                  key: {{ .Values.externalDatabase.secretKeys.userPasswordKey | default "db.password" }}
          {{- else }}
            - name: WORDPRESS_DB_USER
              value: {{ .Values.externalDatabase.username | quote }}
            - name: WORDPRESS_DB_PASSWORD
              value: {{ .Values.externalDatabase.password | quote }}
          {{- end }}
          {{- end }}
          {{ if .Values.metrics.wordpress.enabled }}
            - name: SLYMETRICS_BEARER_TOKEN
              valueFrom:
                secretKeyRef:
                  name: {{ if .Values.metrics.wordpress.serviceMonitor.existingSecret }}{{ .Values.metrics.wordpress.serviceMonitor.existingSecret }}{{ else }}{{ include "metrics.wordpress.fullname" . }}{{ end }}
                  key: wordpress.metrics.token
            - name: SLYMETRICS_ENCRYPTION_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ include "metrics.wordpress.fullname" . }}
                  key: wordpress.metrics.encryptionKey
          {{- end }}
          {{- if .Values.wordpress.init.jwt.enabled }}
            - name: JWT_AUTH_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  {{- if .Values.wordpress.init.jwt.existingSecret }}
                  name: {{ .Values.wordpress.init.jwt.existingSecret }}
                  key: {{ .Values.wordpress.init.jwt.secretKey | default "JWT_AUTH_SECRET_KEY" }}
                  {{- else }}
                  name: {{ include "wordpress.fullname" . }}-jwt
                  key: JWT_AUTH_SECRET_KEY
                  {{- end }}
          {{- end }}
          {{- if and .Values.wordpress.configExtraConfigMap.name (not .Values.wordpress.configExtraSecret.name) }}
          {{- if .Values.wordpress.configExtraInject }}
          {{/* Combine external ConfigMap + chart-managed inject via K8s env var interpolation */}}
            - name: _WP_CONFIG_INJECT
              valueFrom:
                secretKeyRef:
                  name: {{ include "wordpress.fullname" . }}
                  key: _WP_CONFIG_INJECT
            - name: _WP_CONFIG_USER
              valueFrom:
                configMapKeyRef:
                  name: {{ .Values.wordpress.configExtraConfigMap.name }}
                  key: {{ .Values.wordpress.configExtraConfigMap.key | default "wordpress.configExtra" }}
            - name: WORDPRESS_CONFIG_EXTRA
              value: "$(_WP_CONFIG_USER)$(_WP_CONFIG_INJECT)"
          {{- else }}
            - name: WORDPRESS_CONFIG_EXTRA
              valueFrom:
                configMapKeyRef:
                  name: {{ .Values.wordpress.configExtraConfigMap.name }}
                  key: {{ .Values.wordpress.configExtraConfigMap.key | default "wordpress.configExtra" }}
          {{- end }}
          {{- end }}
          {{- if .Values.wordpress.configExtraSecret.name }}
          {{- if .Values.wordpress.configExtraInject }}
          {{/* Combine external Secret + chart-managed inject via K8s env var interpolation */}}
            - name: _WP_CONFIG_INJECT
              valueFrom:
                secretKeyRef:
                  name: {{ include "wordpress.fullname" . }}
                  key: _WP_CONFIG_INJECT
            - name: _WP_CONFIG_USER
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.wordpress.configExtraSecret.name }}
                  key: {{ .Values.wordpress.configExtraSecret.key | default "wordpress.configExtra" }}
            - name: WORDPRESS_CONFIG_EXTRA
              value: "$(_WP_CONFIG_USER)$(_WP_CONFIG_INJECT)"
          {{- else }}
            - name: WORDPRESS_CONFIG_EXTRA
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.wordpress.configExtraSecret.name }}
                  key: {{ .Values.wordpress.configExtraSecret.key | default "wordpress.configExtra" }}
          {{- end }}
          {{- end }}
          {{- if .Values.wordpress.smtp.enabled }}
            - name: WP_SMTP_HOST
              value: {{ .Values.wordpress.smtp.host | quote }}
            - name: WP_SMTP_PORT
              value: {{ .Values.wordpress.smtp.port | quote }}
            - name: WP_SMTP_ENCRYPTION
              value: {{ .Values.wordpress.smtp.encryption | quote }}
            - name: WP_SMTP_AUTH
              value: {{ .Values.wordpress.smtp.auth | quote }}
            - name: WP_SMTP_USERNAME
              {{- if and .Values.wordpress.smtp.existingSecret .Values.wordpress.smtp.existingSecretUsernameKey }}
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.wordpress.smtp.existingSecret }}
                  key: {{ .Values.wordpress.smtp.existingSecretUsernameKey }}
              {{- else }}
              value: {{ .Values.wordpress.smtp.username | quote }}
              {{- end }}
            - name: WP_SMTP_FROM_EMAIL
              {{- if and .Values.wordpress.smtp.existingSecret .Values.wordpress.smtp.existingSecretFromEmailKey }}
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.wordpress.smtp.existingSecret }}
                  key: {{ .Values.wordpress.smtp.existingSecretFromEmailKey }}
              {{- else }}
              value: {{ .Values.wordpress.smtp.fromEmail | quote }}
              {{- end }}
            - name: WP_SMTP_FROM_NAME
              value: {{ .Values.wordpress.smtp.fromName | quote }}
            - name: WP_SMTP_PASSWORD
              {{- if .Values.wordpress.smtp.existingSecret }}
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.wordpress.smtp.existingSecret }}
                  key: {{ .Values.wordpress.smtp.existingSecretPasswordKey }}
              {{- else if .Values.wordpress.smtp.password }}
              valueFrom:
                secretKeyRef:
                  name: {{ include "wordpress.fullname" . }}
                  key: WP_SMTP_PASSWORD
              {{- else }}
              value: ""
              {{- end }}
          {{- end }}
          envFrom:
            - secretRef:
                name: {{ include "wordpress.fullname" . }}
          {{- if or .Values.extraEnvVarsCM .Values.extraEnvVarsSecret }}
            {{- if .Values.extraEnvVarsCM }}
            - configMapRef:
                name: {{ .Values.extraEnvVarsCM }}
            {{- end }}
            {{- if .Values.extraEnvVarsSecret }}
            - secretRef:
                name: {{ .Values.extraEnvVarsSecret }}
            {{- end }}
          {{- end }}
          ports:
            - name: http
              containerPort: {{ .Values.containerPorts.http }}
              protocol: TCP
            - name: https
              containerPort: {{ .Values.containerPorts.https }}
              protocol: TCP
          {{- if .Values.customLivenessProbe }}
          livenessProbe:
            {{- toYaml .Values.customLivenessProbe | nindent 12 }}
          {{- else if .Values.livenessProbe.enabled }}
          livenessProbe:
            {{- toYaml (omit .Values.livenessProbe "enabled") | nindent 12 }}
            httpGet:
              path: /wp-login.php
              port: http
              {{- if .Values.wordpress.init.multiSites.enabled }}
              httpHeaders:
                - name: Host
                  value: {{ include "wordpress.urlHost" . | quote }}
              {{- end }}
          {{- end }}
          {{- if .Values.customReadinessProbe }}
          readinessProbe:
            {{- toYaml .Values.customReadinessProbe | nindent 12 }}
          {{- else if .Values.readinessProbe.enabled }}
          readinessProbe:
            {{- toYaml (omit .Values.readinessProbe "enabled") | nindent 12 }}
            httpGet:
              path: /wp-login.php
              port: http
              {{- if .Values.wordpress.init.multiSites.enabled }}
              httpHeaders:
                - name: Host
                  value: {{ include "wordpress.urlHost" . | quote }}
              {{- end }}
          {{- end }}
          {{- if .Values.customStartupProbe }}
          startupProbe:
            {{- toYaml .Values.customStartupProbe | nindent 12 }}
          {{- else if .Values.startupProbe.enabled }}
          startupProbe:
            {{- toYaml (omit .Values.startupProbe "enabled") | nindent 12 }}
            httpGet:
              path: /wp-login.php
              port: http
              {{- if .Values.wordpress.init.multiSites.enabled }}
              httpHeaders:
                - name: Host
                  value: {{ include "wordpress.urlHost" . | quote }}
              {{- end }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          volumeMounts:
            {{- include "wordpress.dataVolumeMounts" (dict "ctx" . "path" "/var/www/html") | nindent 12 }}
            - name: tmp
              mountPath: /tmp
            - name: run
              mountPath: /var/run
            {{- if .Values.memcached.enabled }}
            - name: wordpress-memcached-ext
              mountPath: /opt/php-ext
            {{- end }}
            {{- if .Values.extraVolumeMounts }}
            {{- toYaml .Values.extraVolumeMounts | nindent 12 }}
            {{- end }}
            {{- if .Values.wordpress.smtp.enabled }}
            - name: smtp-mu-plugin
              mountPath: /var/www/html/wp-content/mu-plugins/smtp-override.php
              subPath: smtp-override.php
              readOnly: true
            {{- end }}
            - name: {{ include "wordpress.fullname" . }}-configfiles
              mountPath: /etc/apache2/sites-enabled/000-default.conf
              subPath: 000-default.conf
            - name: {{ include "wordpress.fullname" . }}-configfiles
              mountPath: /etc/apache2/conf-enabled/00-servername-global.conf
              subPath: 00-servername-global.conf
            - name: {{ include "wordpress.fullname" . }}-configfiles
              mountPath: /etc/apache2/ports.conf
              subPath: ports.conf
            - name: {{ include "wordpress.fullname" . }}-configfiles
              mountPath: /usr/local/etc/php/conf.d/custom.ini
              subPath: custom.ini
            {{- if .Values.apache.opcache.enabled }}
            - name: {{ include "wordpress.fullname" . }}-configfiles
              mountPath: /usr/local/etc/php/conf.d/zz-opcache.ini
              subPath: zz-opcache.ini
            {{- end }}
        {{- if .Values.metrics.apache.enabled}}
        - name: metrics-apache
          image: {{ include "slycharts.image" (dict "image" .Values.metrics.apache.image) }}
          imagePullPolicy: {{ .Values.metrics.apache.image.pullPolicy | quote }}
          command:
            - sh
            - -c
            - |
              echo "Waiting for WordPress to be ready..."
              until wget -q -O /dev/null http://localhost:{{ .Values.containerPorts.http }}/server-status/?auto; do
                echo "WordPress not ready yet, waiting..."
                sleep 10
              done
              echo "WordPress is ready, starting exporter..."
              exec /bin/apache_exporter --scrape_uri http://localhost:{{ .Values.containerPorts.http }}/server-status/?auto
          ports:
          - name: metrics
            containerPort: {{ .Values.metrics.apache.service.ports.metrics }}
          {{ if .Values.metrics.apache.customLivenessProbe }}
          livenessProbe:
            {{- toYaml .Values.metrics.apache.customLivenessProbe | nindent 12 }}
          {{- else if .Values.metrics.apache.livenessProbe.enabled }}
          livenessProbe:
            tcpSocket:
              port: metrics
            initialDelaySeconds: {{ .Values.metrics.apache.livenessProbe.initialDelaySeconds | default 5 }}
            periodSeconds: {{ .Values.metrics.apache.livenessProbe.periodSeconds | default 10 }}
            timeoutSeconds: {{ .Values.metrics.apache.livenessProbe.timeoutSeconds | default 5 }}
            failureThreshold: {{ .Values.metrics.apache.livenessProbe.failureThreshold | default 3 }}
            successThreshold: {{ .Values.metrics.apache.livenessProbe.successThreshold | default 1 }}
          {{ end }}
          {{ if .Values.metrics.apache.customReadinessProbe }}
          readinessProbe:
            {{- toYaml .Values.metrics.apache.customReadinessProbe | nindent 12 }}
          {{- else if .Values.metrics.apache.readinessProbe.enabled }}
          readinessProbe:
            tcpSocket:
              port: metrics
            initialDelaySeconds: {{ .Values.metrics.apache.readinessProbe.initialDelaySeconds | default 5 }}
            periodSeconds: {{ .Values.metrics.apache.readinessProbe.periodSeconds | default 10 }}
            timeoutSeconds: {{ .Values.metrics.apache.readinessProbe.timeoutSeconds | default 5 }}
            failureThreshold: {{ .Values.metrics.apache.readinessProbe.failureThreshold | default 3 }}
            successThreshold: {{ .Values.metrics.apache.readinessProbe.successThreshold | default 1 }}
          {{ end }}
          {{ if .Values.metrics.apache.customStartupProbe }}
          startupProbe:
            {{- toYaml .Values.metrics.apache.customStartupProbe | nindent 12 }}
          {{- else if .Values.metrics.apache.startupProbe.enabled }}
          startupProbe:
            tcpSocket:
              port: metrics
            initialDelaySeconds: {{ .Values.metrics.apache.startupProbe.initialDelaySeconds | default 10 }}
            periodSeconds: {{ .Values.metrics.apache.startupProbe.periodSeconds | default 10 }}
            timeoutSeconds: {{ .Values.metrics.apache.startupProbe.timeoutSeconds | default 1 }}
            failureThreshold: {{ .Values.metrics.apache.startupProbe.failureThreshold | default 15 }}
            successThreshold: {{ .Values.metrics.apache.startupProbe.successThreshold | default 1 }}
          {{ end }}
          resources:
            {{ toYaml .Values.metrics.resources | indent 10 }}
          securityContext:
            {{- toYaml .Values.metrics.apache.containerSecurityContext | nindent 12 }}
        {{- end }}
      {{- with .Values.sidecars }}
        {{- toYaml . | nindent 8 }}
      {{- end }}
      volumes:
      - name: tmp
        emptyDir: {}
      - name: run
        emptyDir: {}
      {{- if .Values.memcached.enabled }}
      - name: wordpress-memcached-ext
        emptyDir: {}
      {{- end }}
      - name: {{ include "wordpress.fullname" . }}-configfiles
        projected:
          defaultMode: 0664
          sources:
          - configMap:
              name: {{ include "wordpress.fullname" . }}-configfiles
              items:
                - key: 00-servername-global.conf
                  path: 00-servername-global.conf
                {{- if (not .Values.apache.customDefaultSiteConfigMap) }}
                - key: 000-default.conf
                  path: 000-default.conf
                {{- end }}
                {{- if (not .Values.apache.customPortsConfigMap) }}
                - key: ports.conf
                  path: ports.conf
                {{- end }}
                {{- if (not .Values.apache.customPhpConfigMap) }}
                - key: custom.ini
                  path: custom.ini
                {{- end }}
                {{- if .Values.apache.opcache.enabled }}
                - key: zz-opcache.ini
                  path: zz-opcache.ini
                {{- end }}
                {{- if (not .Values.wordpress.htaccessConfigMap) }}
                - key: htaccess
                  path: .htaccess
                {{- end }}
          {{- if .Values.apache.customDefaultSiteConfigMap }}
          - configMap:
              name: {{ .Values.apache.customDefaultSiteConfigMap }}
              items:
                - key: 000-default.conf
                  path: 000-default.conf
          {{- end }}
          {{- if .Values.apache.customPortsConfigMap }}
          - configMap:
              name: {{ .Values.apache.customPortsConfigMap }}
              items:
                - key: ports.conf
                  path: ports.conf
          {{- end }}
          {{- if .Values.apache.customPhpConfigMap }}
          - configMap:
              name: {{ .Values.apache.customPhpConfigMap }}
              items:
                - key: custom.ini
                  path: custom.ini
          {{- end }}
          {{- if .Values.wordpress.htaccessConfigMap }}
          - configMap:
              name: {{ .Values.wordpress.htaccessConfigMap }}
              items:
                - key: htaccess
                  path: .htaccess
          {{- end }}
      - name: {{ include "wordpress.fullname" . }}-init
        configMap:
          name: {{ include "wordpress.fullname" . }}-init
          items:
            - key: base.sh
              path: base.sh
            - key: init.sh
              path: init.sh
            - key: htaccess-setup.sh
              path: htaccess-setup.sh
            - key: htaccess-inject.sh
              path: htaccess-inject.sh
            - key: wordpress-rewrite-rules.txt
              path: wordpress-rewrite-rules.txt
            - key: lib-core.sh
              path: lib-core.sh
            - key: lib-composer.sh
              path: lib-composer.sh
            - key: lib-lock.sh
              path: lib-lock.sh
      {{- if .Values.externalDatabase.existingSecret }}
      - name: {{ .Values.externalDatabase.existingSecret }}
        secret:
          secretName: {{ .Values.externalDatabase.existingSecret }}
      {{- end }}
      {{- if eq .Values.storage.mode "wp-content" }}
      # storage.mode=wp-content: the WordPress core lives on this ephemeral emptyDir
      # (re-copied from the image each start); only wp-content is persisted on the volume below.
      - name: wordpress-html
        emptyDir: {}
      {{- end }}
      {{- if ne .Values.controllerType "statefulset" }}
      - name: {{ include "wordpress.fullname" . }}
        persistentVolumeClaim:
          claimName: {{ if .Values.storage.existingClaim }}{{ .Values.storage.existingClaim }}{{ else }}{{ include "wordpress.fullname" . }}{{ end }}
      {{- else }}
      # StatefulSet: the "{{ include "wordpress.fullname" . }}" volume is provided per-Pod
      # by spec.volumeClaimTemplates (same name → volumeMounts stay unchanged).
      {{- end }}
      {{- if .Values.wordpress.init.customInitConfigMap.name }}
      - name: custom-init-commands
        configMap:
          name: {{ .Values.wordpress.init.customInitConfigMap.name }}
          defaultMode: 0755
      {{- end }}
      {{- range .Values.wordpress.muPluginsConfigMaps }}
      - name: mu-plugins-{{ .name }}
        configMap:
          name: {{ .name }}
          defaultMode: 0644
      {{- end }}
      {{- if .Values.wordpress.smtp.enabled }}
      - name: smtp-mu-plugin
        configMap:
          name: {{ include "wordpress.fullname" . }}-smtp-mu-plugin
          defaultMode: 0644
      {{- end }}
      {{- if .Values.extraVolumes }}
      {{- toYaml .Values.extraVolumes | nindent 6 }}
      {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if .Values.priorityClassName }}
      priorityClassName: {{ .Values.priorityClassName }}
      {{- end }}
{{- end -}}
