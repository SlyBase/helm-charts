{{- define "wordpress.init-base" -}}
#!/bin/bash
set -e

# PVC ownership is handled by the fix-permissions init container (runs as root).
# This script runs as non-root uid 33 (www-data) - all created files are
# automatically owned by www-data, no chown needed.

# Helper function to extract WordPress version from version.php
get_wp_version() {
  local version_file="$1"
  if [ -f "$version_file" ]; then
    grep "^\$wp_version" "$version_file" | sed "s/.*'\([^']*\)'.*/\1/"
  else
    echo ""
  fi
}

# Helper function to copy WordPress core files (excludes wp-content)
# Uses a lock file to prevent concurrent copies when multiple replicas start simultaneously
copy_wp_core() {
  local LOCK_FILE="/tmp/wordpress/.wp-copy-lock"

  # Try to acquire lock (atomic: set -o noclobber makes > fail if file exists)
  if (set -o noclobber; echo "$$" > "$LOCK_FILE") 2>/dev/null; then
    # We got the lock - copy files
    trap 'rm -f "$LOCK_FILE"' EXIT
    echo "Copying WordPress core files..."
    cd /usr/src/wordpress || exit 1
    for item in *; do
      if [ "$item" != "wp-content" ]; then
        cp -rf "$item" /tmp/wordpress/ || exit 1
      fi
    done
    # No chown needed - running as uid 33, files are already owned correctly
    rm -f "$LOCK_FILE"
    trap - EXIT
    echo "WordPress core files copied successfully!"
  else
    # Another pod is copying - wait for it to finish
    echo "Another pod is copying WordPress files, waiting..."
    WAIT=0
    while [ -f "$LOCK_FILE" ] && [ $WAIT -lt 120 ]; do
      sleep 2
      WAIT=$((WAIT + 2))
    done
    if [ -f "$LOCK_FILE" ]; then
      echo "WARNING: Lock file still present after 120s, removing stale lock..."
      rm -f "$LOCK_FILE"
    fi
    echo "WordPress files ready (copied by another pod)."
  fi
}

# Get versions from image and PVC
IMAGE_VERSION=$(get_wp_version "/usr/src/wordpress/wp-includes/version.php")
PVC_VERSION=$(get_wp_version "/tmp/wordpress/wp-includes/version.php")

echo "========================================="
echo "WordPress Version Check"
echo "========================================="
echo "Image version: ${IMAGE_VERSION:-'not found'}"
echo "PVC version:   ${PVC_VERSION:-'not installed'}"
echo "========================================="

# Check if WordPress needs to be installed or updated
if [ -z "$PVC_VERSION" ]; then
    echo "WordPress not found in /tmp/wordpress - fresh installation..."
    mkdir -p /tmp/wordpress
    copy_wp_core

    # Handle wp-config-docker.php for fresh install
    if [ -f "/usr/src/wordpress/wp-config-docker.php" ] && [ ! -f /tmp/wordpress/wp-config.php ]; then
      awk '
        /put your unique phrase here/ {
          cmd = "head -c1m /dev/urandom | sha1sum | cut -d\\  -f1"
          cmd | getline str
          close(cmd)
          gsub("put your unique phrase here", str)
        }
        { print }
      ' /usr/src/wordpress/wp-config-docker.php > /tmp/wordpress/wp-config.php
    fi

    {{- if eq .Values.storage.mode "wp-content" }}
    # storage.mode=wp-content: wp-content is its own volume (always a mountpoint), so populate
    # the image skeleton only when the directory is empty — covers a fresh per-Pod RWO volume
    # or a fresh shared RWX volume. A lock file serializes the copy when replicas start together.
    if [ -z "$(ls -A /tmp/wordpress/wp-content 2>/dev/null)" ]; then
        SKEL_LOCK="/tmp/wordpress/wp-content/.wp-content-copy-lock"
        if (set -o noclobber; echo "$$" > "$SKEL_LOCK") 2>/dev/null; then
            trap 'rm -f "$SKEL_LOCK"' EXIT
            echo "Populating empty wp-content from image skeleton..."
            cp -r /usr/src/wordpress/wp-content/. /tmp/wordpress/wp-content/ 2>/dev/null || true
            rm -f "$SKEL_LOCK"
            trap - EXIT
        else
            echo "Another pod is populating wp-content, continuing..."
        fi
    fi
    {{- else }}
    # Copy wp-content skeleton if not present
    if [ ! -d /tmp/wordpress/wp-content ]; then
        cp -r /usr/src/wordpress/wp-content /tmp/wordpress/wp-content 2>/dev/null || true
    fi
    {{- end }}
    echo "Complete! WordPress has been successfully installed to /tmp/wordpress"

elif [ "$IMAGE_VERSION" != "$PVC_VERSION" ]; then
    echo "WordPress version mismatch detected!"
    echo "Updating core files from $PVC_VERSION to $IMAGE_VERSION..."
    echo "Note: wp-content directory will be preserved."
    copy_wp_core
    echo "Complete! WordPress core has been updated to $IMAGE_VERSION"

    # Mark that a core update happened (used by init.sh to disable auto-updates)
    touch /tmp/wordpress/.wp-core-updated

else
    echo "WordPress version matches - no update needed."
fi


# ============================================================================
# Setup MU-Plugins from ConfigMaps
# ============================================================================
{{- if .Values.wordpress.muPluginsConfigMaps }}
echo ""
echo "Setting up MU-Plugins from ConfigMaps..."
echo "========================================="


# Create mu-plugins directory if it doesn't exist
mkdir -p /tmp/wordpress/wp-content/mu-plugins
chmod 755 /tmp/wordpress/wp-content/mu-plugins


{{- range .Values.wordpress.muPluginsConfigMaps }}
# Copy files from ConfigMap: {{ .name }}
if [ -d "/tmp/mu-plugins-{{ .name }}" ]; then
  {{- if .key }}
  # Copy specific key only
  if [ -f "/tmp/mu-plugins-{{ .name }}/{{ .key }}" ]; then
    echo "Copying MU-Plugin file {{ .key }} from {{ .name }}..."
    cp /tmp/mu-plugins-{{ .name }}/{{ .key }} /tmp/wordpress/wp-content/mu-plugins/
    chmod 644 /tmp/wordpress/wp-content/mu-plugins/{{ .key }}
    echo "MU-Plugin file {{ .key }} from {{ .name }} copied successfully!"
  else
    echo "Warning: Key {{ .key }} not found in ConfigMap {{ .name }}"
  fi
  {{- else }}
  # Copy all files from ConfigMap
  echo "Copying all MU-Plugin files from {{ .name }}..."
  cp -r -L /tmp/mu-plugins-{{ .name }}/* /tmp/wordpress/wp-content/mu-plugins/ 2>/dev/null || true
  # Set correct ownership and permissions for all copied files
  find /tmp/wordpress/wp-content/mu-plugins -type f -exec chmod 644 {} \;
  echo "MU-Plugin files from {{ .name }} copied successfully!"
  {{- end }}
else
  echo "Warning: MU-Plugin ConfigMap mount {{ .name }} not found"
fi
{{- end }}


echo "MU-Plugins setup completed!"
{{- else }}
echo "No MU-Plugins ConfigMaps configured."
{{- end }}


# ============================================================================
# Custom Init Commands ConfigMap Info
# ============================================================================
{{- if .Values.wordpress.init.customInitConfigMap.name }}
echo ""
echo "Custom init commands ConfigMap detected: {{ .Values.wordpress.init.customInitConfigMap.name }}"
{{- end }}


echo "========================================="
echo "Base script completed!"
echo "========================================="
{{- end -}}
