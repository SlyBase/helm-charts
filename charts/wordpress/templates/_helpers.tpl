{{/*
Expand the name of the chart.
*/}}
{{- define "wordpress.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "wordpress.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Headless service name used by the StatefulSet for stable Pod DNS.
*/}}
{{- define "wordpress.headlessServiceName" -}}
{{- printf "%s-headless" (include "wordpress.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "wordpress.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "wordpress.labels" -}}
helm.sh/chart: "{{ include "wordpress.chart" . }}"
{{ include "wordpress.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: "{{ .Chart.AppVersion }}"
{{- end }}
app.kubernetes.io/managed-by: "{{ .Release.Service }}"
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "wordpress.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wordpress.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "wordpress.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "wordpress.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
MariaDB fullname
*/}}
{{- define "wordpress.mariadb.fullname" -}}
{{- if .Values.mariadb.fullnameOverride }}
{{- .Values.mariadb.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "mariadb" .Values.mariadb.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
memcached fullname
*/}}
{{- define "wordpress.memcached.fullname" -}}
{{- if .Values.memcached.fullnameOverride }}
{{- .Values.memcached.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "memcached" .Values.memcached.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
redis fullname
*/}}
{{- define "wordpress.redis.fullname" -}}
{{- if .Values.redis.fullnameOverride }}
{{- .Values.redis.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "redis" .Values.redis.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
valkey fullname
*/}}
{{- define "wordpress.valkey.fullname" -}}
{{- if .Values.valkey.fullnameOverride }}
{{- .Values.valkey.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "valkey" .Values.valkey.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Wordpress metrics plugin
*/}}
{{- define "metrics.wordpress.pluginname" -}}
{{- if and (default false .Values.metrics.wordpress.enabled) (default false .Values.metrics.wordpress.installPlugin) }}
{{- default "slymetrics" .Values.metrics.wordpress.pluginNameOverride | quote }}
{{- else }}
{{- "" | quote }}
{{- end }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "metrics.wordpress.fullname" -}}
{{- if .Values.metrics.wordpress.fullnameOverride }}
{{- .Values.metrics.wordpress.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "metrics-wordpress" .Values.metrics.wordpress.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "metrics.apache.fullname" -}}
{{- if .Values.metrics.apache.fullnameOverride }}
{{- .Values.metrics.apache.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "metrics-apache" .Values.metrics.apache.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Build a full image reference from registry, repository and tag.
Usage: {{ include "slycharts.image" (dict "image" .Values.image "defaultTag" .Chart.AppVersion) }}
or:    {{ include "slycharts.image" (dict "image" .Values.wordpress.init.image) }}

The image dict should contain:
  - registry: (optional) e.g. "docker.io", "ghcr.io"
  - repository: (required) e.g. "wordpress", "mariadb"
  - tag: (required) e.g. "6.8.3-php8.1-apache" or with digest "6.8.3@sha256:abc123"

Returns: registry/repository:tag (e.g. "docker.io/wordpress:6.8.3-php8.1-apache")
*/}}
{{- define "slycharts.image" -}}
{{- $registry := .image.registry | default "" -}}
{{- $repository := .image.repository -}}
{{- $tag := .image.tag | default .defaultTag | default "latest" -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}
{{/* Checksum helpers */}}
{{/*
Normalize WordPress URL: ensure it has a protocol prefix.
If no protocol is provided, derive from Ingress TLS config (https:// if TLS configured, http:// otherwise).
Usage: {{ include "wordpress.normalizedUrl" . }}
*/}}
{{- define "wordpress.normalizedUrl" -}}
{{- $url := .Values.wordpress.url -}}
{{- if and (not (hasPrefix "http://" $url)) (not (hasPrefix "https://" $url)) -}}
  {{- if and .Values.ingress.enabled .Values.ingress.tls -}}
    {{- printf "https://%s" $url -}}
  {{- else -}}
    {{- printf "http://%s" $url -}}
  {{- end -}}
{{- else -}}
  {{- $url -}}
{{- end -}}
{{- end -}}

{{/*
Extract host (without protocol) from WordPress URL for HTTP Host headers.
Usage: {{ include "wordpress.urlHost" . }}
*/}}
{{- define "wordpress.urlHost" -}}
{{- $url := include "wordpress.normalizedUrl" . -}}
{{- $url = trimPrefix "https://" $url -}}
{{- $url = trimPrefix "http://" $url -}}
{{- trimSuffix "/" $url -}}
{{- end -}}

{{- define "wordpress.checksum.lookup" -}}
{{- $name := index . 0 -}}
{{- $ns := index . 1 -}}
{{- if $ns }}
  {{- $cm := lookup "v1" "ConfigMap" $ns $name -}}
  {{- if $cm }}
{{- toJson $cm.data | sha256sum }}
  {{- else }}
{{- $name | sha256sum }}
  {{- end }}
{{- else }}
{{- $name | sha256sum }}
{{- end -}}
{{- end -}}

{{- define "wordpress.checksum.rendered" -}}
{{- $path := index . 0 -}}
{{- $ctx := index . 1 -}}
{{- include $path $ctx | sha256sum -}}
{{- end -}}

{{- define "wordpress.checksum.combine" -}}
{{- $list := index . 0 -}}
{{- $joined := $list | join "" -}}
{{- $joined | sha256sum -}}
{{- end -}}

{{/* Cache helper: resolve createConfig with legacy createconfig support */}}
{{- define "wordpress.cache.createConfig" -}}
{{- $obj := .obj -}}
{{- $value := ($obj.createConfig | default false) -}}
{{- if hasKey $obj "createconfig" -}}
{{- $value = $obj.createconfig -}}
{{- end -}}
{{- toYaml (dict "value" $value) -}}
{{- end -}}

{{/* Cache helper: collect enabled backends and createConfig flags */}}
{{- define "wordpress.cache.backends" -}}
{{- $memcachedCreate := (include "wordpress.cache.createConfig" (dict "obj" .Values.memcached) | fromYaml).value -}}
{{- $redisCreate := (include "wordpress.cache.createConfig" (dict "obj" .Values.redis) | fromYaml).value -}}
{{- $valkeyCreate := (include "wordpress.cache.createConfig" (dict "obj" .Values.valkey) | fromYaml).value -}}

{{- $enabled := list -}}
{{- if .Values.memcached.enabled }}{{- $enabled = append $enabled "memcached" }}{{- end -}}
{{- if .Values.redis.enabled }}{{- $enabled = append $enabled "redis" }}{{- end -}}
{{- if .Values.valkey.enabled }}{{- $enabled = append $enabled "valkey" }}{{- end -}}

{{- $selected := "" -}}
{{- if eq (len $enabled) 1 }}{{- $selected = index $enabled 0 -}}{{- end -}}

{{- toYaml (dict
    "enabled" $enabled
    "enabledCount" (len $enabled)
    "selected" $selected
    "memcachedCreateConfig" $memcachedCreate
    "redisCreateConfig" $redisCreate
    "valkeyCreateConfig" $valkeyCreate
  ) -}}
{{- end -}}

{{/* Cache helper: fail-fast if more than one backend is enabled */}}
{{- define "wordpress.cache.validateSelection" -}}
{{- $b := (include "wordpress.cache.backends" . | fromYaml) -}}
{{- if gt ($b.enabledCount | int) 1 -}}
{{- fail (printf "invalid cache backend configuration: exactly one of memcached.enabled, redis.enabled, valkey.enabled can be true (got %d: %v)" ($b.enabledCount | int) $b.enabled) -}}
{{- end -}}
{{- end -}}

{{/* Cache helper: shared metadata for redis/valkey */}}
{{- define "wordpress.cache.kvMeta" -}}
{{- $ctx := .ctx -}}
{{- $backend := .backend -}}
{{- $meta := dict
    "backend" $backend
    "createConfig" false
    "host" ""
    "port" 0
    "cacheKeySalt" ""
    "cacheKeySaltSecretName" ""
    "cacheKeySaltSecretKey" "WP_CACHE_KEY_SALT"
  "authEnabled" false
    "authExistingSecret" ""
    "authExistingSecretPasswordKey" ""
    "authPassword" ""
    "scaling" (dict
      "type" "none"
      "servers" (list)
      "sentinel" ""
      "shards" (list)
      "cluster" (list)
    )
  -}}

{{- if eq $backend "redis" -}}
{{- $_ := set $meta "createConfig" ((include "wordpress.cache.createConfig" (dict "obj" $ctx.Values.redis) | fromYaml).value) -}}
{{- $_ := set $meta "host" (include "wordpress.redis.fullname" $ctx) -}}
{{- $_ := set $meta "port" $ctx.Values.redis.service.port -}}
{{- $_ := set $meta "cacheKeySalt" ($ctx.Values.redis.cacheKeySalt | default "") -}}
{{- $_ := set $meta "cacheKeySaltSecretName" $ctx.Values.redis.cacheKeySaltSecret.name -}}
{{- $_ := set $meta "cacheKeySaltSecretKey" ($ctx.Values.redis.cacheKeySaltSecret.key | default "WP_CACHE_KEY_SALT") -}}
{{- $redisAuthEnabled := (default true $ctx.Values.redis.auth.enabled) -}}
{{- $redisAuthExistingSecret := ($ctx.Values.redis.auth.existingSecret | default "") -}}
{{- if and $redisAuthEnabled (eq $redisAuthExistingSecret "") -}}
{{- $redisAuthExistingSecret = include "wordpress.redis.fullname" $ctx -}}
{{- end -}}
{{- $_ := set $meta "authEnabled" $redisAuthEnabled -}}
{{- $_ := set $meta "authExistingSecret" $redisAuthExistingSecret -}}
{{- $_ := set $meta "authExistingSecretPasswordKey" ($ctx.Values.redis.auth.existingSecretPasswordKey | default "redis-password") -}}
{{- if $ctx.Values.redis.auth.password }}{{- $_ := set $meta "authPassword" $ctx.Values.redis.auth.password -}}{{- end -}}
{{- $_ := set $meta "scaling" ($ctx.Values.redis.scaling | default (dict "type" "none" "servers" (list) "sentinel" "" "shards" (list) "cluster" (list))) -}}
{{- else if eq $backend "valkey" -}}
{{- $_ := set $meta "createConfig" ((include "wordpress.cache.createConfig" (dict "obj" $ctx.Values.valkey) | fromYaml).value) -}}
{{- $_ := set $meta "host" (include "wordpress.valkey.fullname" $ctx) -}}
{{- $_ := set $meta "port" $ctx.Values.valkey.service.port -}}
{{- $_ := set $meta "cacheKeySalt" ($ctx.Values.valkey.cacheKeySalt | default "") -}}
{{- $_ := set $meta "cacheKeySaltSecretName" $ctx.Values.valkey.cacheKeySaltSecret.name -}}
{{- $_ := set $meta "cacheKeySaltSecretKey" ($ctx.Values.valkey.cacheKeySaltSecret.key | default "WP_CACHE_KEY_SALT") -}}
{{- $valkeyAuthEnabled := (default true $ctx.Values.valkey.auth.enabled) -}}
{{- $valkeyAuthExistingSecret := ($ctx.Values.valkey.auth.existingSecret | default "") -}}
{{- if and $valkeyAuthEnabled (eq $valkeyAuthExistingSecret "") -}}
{{- $valkeyAuthExistingSecret = include "wordpress.valkey.fullname" $ctx -}}
{{- end -}}
{{- $_ := set $meta "authEnabled" $valkeyAuthEnabled -}}
{{- $_ := set $meta "authExistingSecret" $valkeyAuthExistingSecret -}}
{{- $_ := set $meta "authExistingSecretPasswordKey" ($ctx.Values.valkey.auth.existingSecretPasswordKey | default "password") -}}
{{- if $ctx.Values.valkey.auth.password }}{{- $_ := set $meta "authPassword" $ctx.Values.valkey.auth.password -}}{{- end -}}
{{- $_ := set $meta "scaling" ($ctx.Values.valkey.scaling | default (dict "type" "none" "servers" (list) "sentinel" "" "shards" (list) "cluster" (list))) -}}
{{- end -}}

{{- toYaml $meta -}}
{{- end -}}

{{/* Cache helper: resolve cache key salt */}}
{{- define "wordpress.cache.resolveSalt" -}}
{{- $ctx := .ctx -}}
{{- $backend := .backend -}}
{{- $valueSalt := (.valueSalt | default "") -}}
{{- $secretName := (.secretName | default "") -}}
{{- $secretKey := (.secretKey | default "WP_CACHE_KEY_SALT") -}}

{{- $salt := $valueSalt -}}
{{- if and (eq $salt "") (ne $secretName "") -}}
{{- $cacheKeySaltSecret := lookup "v1" "Secret" $ctx.Release.Namespace $secretName -}}
{{- if not $cacheKeySaltSecret -}}
{{- fail (printf "%s.cacheKeySaltSecret.name '%s' not found in namespace '%s'" $backend $secretName $ctx.Release.Namespace) -}}
{{- end -}}
{{- if not (hasKey $cacheKeySaltSecret.data $secretKey) -}}
{{- fail (printf "%s.cacheKeySaltSecret.key '%s' not found in secret '%s'" $backend $secretKey $secretName) -}}
{{- end -}}
{{- $salt = (index $cacheKeySaltSecret.data $secretKey | b64dec) -}}
{{- end -}}

{{- if eq $salt "" -}}
{{- $existingSecret := lookup "v1" "Secret" $ctx.Release.Namespace (include "wordpress.fullname" $ctx) -}}
{{- if and $existingSecret (hasKey $existingSecret.data "WORDPRESS_CACHE_KEY_SALT") -}}
{{- $salt = (index $existingSecret.data "WORDPRESS_CACHE_KEY_SALT" | b64dec) -}}
{{- else -}}
{{- $salt = randAlphaNum 48 -}}
{{- end -}}
{{- end -}}

{{- toYaml (dict "salt" $salt) -}}
{{- end -}}

{{/* Cache helper: resolve auth password from existing secret or explicit value */}}
{{- define "wordpress.cache.resolveAuthPassword" -}}
{{- $ctx := .ctx -}}
{{- $secretName := (.secretName | default "") -}}
{{- $secretKey := (.secretKey | default "") -}}
{{- $explicitPassword := (.explicitPassword | default "") -}}

{{- $password := "" -}}
{{- if $secretName -}}
{{- $authSecret := lookup "v1" "Secret" $ctx.Release.Namespace $secretName -}}
{{- if and $authSecret (hasKey $authSecret.data $secretKey) -}}
{{- $password = (index $authSecret.data $secretKey | b64dec) -}}
{{- end -}}
{{- else if $explicitPassword -}}
{{- $password = $explicitPassword -}}
{{- end -}}

{{- toYaml (dict "password" $password) -}}
{{- end -}}
