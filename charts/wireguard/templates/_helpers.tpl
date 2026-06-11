{{/*
Expand the name of the chart.
*/}}
{{- define "wireguard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "wireguard.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "wireguard.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "wireguard.labels" -}}
helm.sh/chart: {{ include "wireguard.chart" . }}
{{ include "wireguard.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "wireguard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wireguard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "wireguard.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "wireguard.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
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
