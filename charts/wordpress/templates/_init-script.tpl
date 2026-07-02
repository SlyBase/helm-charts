{{- define "wordpress.init-script" -}}
#!/bin/bash
set -e

# ============================================================================
# WordPress Helm Chart Init Script
# ============================================================================
#
# Purpose:
#   Initializes WordPress installation with plugins, themes, and configuration.
#   Ensures safe multi-pod deployment using distributed database locking.
#
# Features:
#   - Modular library architecture for maintainability
#   - Atomic database lock prevents concurrent initialization
#   - Composer package management for plugins/themes
#   - Automatic dependency installation and autoloading
#   - Network retry logic with exponential backoff
#   - Input validation and injection protection
#   - Performance optimizations (caching, batch operations)
#   - DRY_RUN mode for testing without changes
#   - TEST_MODE with assertions for validation
#
# Libraries:
#   - lib-core.sh: Core utilities (wp, run, handle_error, retry_command, assert)
#   - lib-lock.sh: Database locking with heartbeat (claim/release bootstrap + config locks)
#   - lib-composer.sh: Composer management (ensure_composer, composer_exec)
#
# Environment Variables:
#   WP_INIT - Enable/disable WordPress core installation
#   WP_URL - WordPress site URL
#   WP_TITLE - Site title
#   WP_ADMIN_USER - Admin username
#   WP_ADMIN_PASSWORD - Admin password
#   WP_ADMIN_EMAIL - Admin email
#   WP_LOCALE - WordPress language locale
#   DEBUG - Enable verbose debug output (true/false)
#   DRY_RUN - Print commands without executing (true/false)
#   TEST_MODE - Enable assertions for testing (true/false)
#   MAX_RETRIES - Network operation retry count (default: 3)
#   RETRY_DELAY - Base retry delay in seconds (default: 2)
#
# Exit Codes:
#   0 - Successful initialization
#   1 - Fatal error (database, lock timeout, invalid input, network failure)
#
# ============================================================================

echo "Starting init script..."

# ============================================================================
# Load Libraries
# ============================================================================
# Libraries are copied to /tmp/lib by the base init container

LIB_DIR="/tmp/lib"

# Source libraries with error handling
for lib in lib-core.sh lib-lock.sh lib-composer.sh; do
  if [ -f "$LIB_DIR/$lib" ]; then
    # shellcheck source=/dev/null
    source "$LIB_DIR/$lib"
    [ "${DEBUG}" = "true" ] && echo "DEBUG: Loaded library: $lib" >&2
  else
    echo "ERROR: Required library not found: $LIB_DIR/$lib" >&2
    echo "Make sure the base init container has prepared the libraries." >&2
    exit 1
  fi
done

# ============================================================================
# Configuration Constants
# ============================================================================

# Database lock configuration
readonly DB_CHECK_RETRY_INTERVAL=15  # Seconds between database connection checks

# WordPress paths
readonly WORDPRESS_PATH="/var/www/html"
readonly WP_PLUGINS_DIR="wp-content/plugins"
readonly WP_THEMES_DIR="wp-content/themes"
readonly WP_MU_PLUGINS_DIR="wp-content/mu-plugins"

# Composer configuration
readonly COMPOSER_HOME_DIR="/tmp/.composer"
readonly COMPOSER_INSTALL_DIR="/tmp"

# Runtime variables
COMPOSER_PACKAGES_MODIFIED=false
PLUGINS_MODIFIED=false
COMPOSER_PLUGINS_PENDING_ACTIVATION=()
ASSERT_FAILURES=0

# Ensure locks are released even when the container is killed (SIGTERM from kubelet)
# SIGTERM → exit 1 → triggers EXIT trap → releases locks + stops heartbeat
# Note: SIGKILL (after terminationGracePeriodSeconds) cannot be caught,
# but the heartbeat-based stale detection handles that case (60s timeout)
trap 'echo "Received termination signal, cleaning up..."; exit 1' TERM INT
trap '_stop_heartbeat; release_bootstrap_lock; release_config_lock' EXIT

# ============================================================================
# Validate Required Environment Variables
# ============================================================================

for required_var in WORDPRESS_DB_HOST WORDPRESS_DB_USER WORDPRESS_DB_PASSWORD WORDPRESS_DB_NAME; do
  eval "val=\$$required_var"
  if [ -z "$val" ]; then
    handle_error "Required environment variable $required_var is not set"
  fi
done

if [ "${WP_INIT}" = "true" ]; then
  for required_var in WP_URL WP_ADMIN_USER WP_ADMIN_PASSWORD WP_ADMIN_EMAIL; do
    eval "val=\$$required_var"
    if [ -z "$val" ]; then
      handle_error "Required environment variable $required_var is not set (needed for WP_INIT=true)"
    fi
  done
fi

# ============================================================================
# Wait for Database
# ============================================================================


echo "Waiting for database..."
# Direct database connection check (faster than wp db check - no WordPress bootstrap)
# Uses getenv() instead of inline credentials to avoid leaking them in process list
until php -r 'exit(@(new mysqli(getenv("WORDPRESS_DB_HOST"), getenv("WORDPRESS_DB_USER"), getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME")))->connect_error ? 1 : 0);' 2>/dev/null; do
  echo "Database not ready yet, waiting ${DB_CHECK_RETRY_INTERVAL} seconds..."
  sleep "${DB_CHECK_RETRY_INTERVAL}"
done
echo "Database connection established!"

# Cache table prefix once (performance optimization)
# Priority: 1. Environment variable (from values.yaml), 2. wp-config.php, 3. default "wp_"
if [ -n "${WORDPRESS_TABLE_PREFIX}" ]; then
  TABLE_PREFIX="${WORDPRESS_TABLE_PREFIX}"
elif [ -f /var/www/html/wp-config.php ]; then
  TABLE_PREFIX=$(grep "^\$table_prefix" /var/www/html/wp-config.php 2>/dev/null | sed "s/.*'\([^']*\)'.*/\1/" || echo "wp_")
else
  TABLE_PREFIX="wp_"
fi
export TABLE_PREFIX
echo "Using WordPress table prefix: ${TABLE_PREFIX}"

{{- if .Values.memcached.enabled }}
# wp-cli in wordpress-init container runs without memcached extension.
# If a stale object-cache.php exists on PVC, wp bootstrap can fatally fail.
MEMCACHED_DROPIN="/var/www/html/wp-content/object-cache.php"
MEMCACHED_DROPIN_DISABLED="/var/www/html/wp-content/object-cache.php.helm-disabled"
if [ -f "$MEMCACHED_DROPIN" ] && ! php -m | grep -qi '^memcached$'; then
  echo "Temporarily disabling existing object-cache.php for wp-cli init..."
  mv "$MEMCACHED_DROPIN" "$MEMCACHED_DROPIN_DISABLED" || true
fi
{{- end }}

# ============================================================================
# Bootstrap Lock Acquisition (Before WordPress Installation)
# ============================================================================
# This lock prevents race conditions when multiple pods start simultaneously
# and try to install WordPress at the same time.
#
# Uses dedicated helm_locks table with heartbeat-based stale detection.

# Check if WordPress is already installed (quick check before claiming lock)
WP_ALREADY_INSTALLED=false
if wp_table_exists "options"; then
  if run wp core is-installed --url="${WP_URL}" 2>/dev/null; then
    WP_ALREADY_INSTALLED=true
    echo "WordPress is already installed, skipping bootstrap lock."
  fi
fi

# Only claim bootstrap lock if WordPress needs installation
if [ "$WP_ALREADY_INSTALLED" = "false" ] && [ "${WP_INIT}" = "true" ]; then
  echo "WordPress not installed yet, claiming bootstrap lock..."
  if ! claim_bootstrap_lock; then
    echo "ERROR: Failed to claim bootstrap lock - another pod may have installation issues"
    exit 1
  fi
  # Trap already set up above with _stop_heartbeat + release functions
fi

# ============================================================================
# WordPress Installation (First-Time Only)
# ============================================================================

echo "========================================="
echo "Setting up WordPress..."
echo "========================================="

if [ "${WP_INIT}" = "true" ]; then
  echo "WP_INIT=true: WordPress core installation enabled (skipped if already installed)."
else
  echo "WP_INIT=false: skipping WordPress core installation (wordpress.init.enabled=false)."
  echo "The init container still manages plugins, themes and configuration."
fi

if [ "${WP_INIT}" = "true" ]; then
  # Check both: wp-cli installation status AND database tables existence
  WP_INSTALLED=false
  if run wp core is-installed --url="${WP_URL}" 2>/dev/null; then
    # wp-cli says installed, but verify tables actually exist
    if wp_table_exists "options"; then
      WP_INSTALLED=true
      echo "WordPress is already installed, skipping installation."
    else
      echo "WordPress files exist but database tables are missing - reinstalling..."
      WP_INSTALLED=false
    fi
  fi

  if [ "$WP_INSTALLED" = "false" ]; then
    echo "Installing WordPress core..."
    run wp core install \
      --url="${WP_URL}" \
      --title="${WP_TITLE}" \
      --admin_user="${WP_ADMIN_USER}" \
      --admin_password="${WP_ADMIN_PASSWORD}" \
      --admin_email="${WP_ADMIN_EMAIL}" \
      --skip-email \
      --locale="${WP_LOCALE}"

    # Verify installation succeeded
    if ! wp_table_exists "options"; then
      echo "ERROR: WordPress installation failed - wp_options table not created!"
      exit 1
    fi
    echo "WordPress core installed successfully!"

    # ============================================================================
    # Multisite Configuration
    # ============================================================================

    if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
      echo "========================================="
      echo "Configuring WordPress Multisite..."
      echo "========================================="

      # Extract domain from WP_URL (remove protocol)
      DOMAIN_CURRENT_SITE=$(echo "${WP_URL}" | sed -E 's|^https?://||' | sed -E 's|/.*||')
      echo "Network domain: ${DOMAIN_CURRENT_SITE}"

      # Check if already converted to multisite (check for wp_sitemeta table)
      if ! wp_table_exists "sitemeta"; then
        echo "Converting WordPress to multisite..."

        # Determine subdomain/subdirectory mode
        if [ "${WP_MULTISITE_SUBDOMAIN:-false}" = "true" ]; then
          echo "Using SUBDOMAIN multisite configuration"
          run wp core multisite-convert --subdomains
        else
          echo "Using SUBDIRECTORY multisite configuration"
          run wp core multisite-convert
        fi

        # Verify conversion succeeded
        if ! wp_table_exists "sitemeta"; then
          echo "ERROR: Multisite conversion failed - sitemeta table not created!"
          exit 1
        fi
        echo "Multisite conversion completed successfully!"
      else
        echo "WordPress is already configured as multisite, skipping conversion."
      fi

      # Set network title (if provided)
      if [ -n "${WP_MULTISITE_TITLE:-}" ]; then
        echo "Setting network title: ${WP_MULTISITE_TITLE}"
        wp db query "UPDATE ${TABLE_PREFIX}sitemeta SET meta_value='${WP_MULTISITE_TITLE}' WHERE meta_key='site_name' AND site_id=1;" 2>&1 | grep -v -e "^$" -e "^Success:" || true
      fi

      echo "========================================="
      echo "Multisite conversion completed!"
      echo "========================================="
    fi

    # Release bootstrap lock after successful installation
    release_bootstrap_lock
  else
    # Installation was skipped, release bootstrap lock if acquired
    release_bootstrap_lock
  fi
else
  # WP_INIT is false - check if WordPress is already installed
  # Use cached TABLE_PREFIX (set at script start)

  # Check if wp_options table exists
  if ! wp_table_exists "options"; then
    echo "========================================="
    echo "ERROR: WordPress database tables not found!"
    echo "========================================="
    echo ""
    echo "The database exists but WordPress tables are missing."
    echo "This indicates one of the following issues:"
    echo ""
    echo "1. WordPress initialization has not been performed yet"
    echo "   -> Set wordpress.init.enabled=true in your values.yaml"
    echo ""
    echo "2. Wrong table prefix configured"
    echo "   -> Current prefix: ${TABLE_PREFIX}"
    echo "   -> Check wordpress.tablePrefix in your values.yaml"
    echo ""
    echo "3. Database was reset but persistent volume still exists"
    echo "   -> Delete the PVC and reinstall"
    echo ""
    echo "========================================="
    exit 1
  fi


  echo "WordPress tables found, continuing with configuration..."
fi

# Update main site title if changed (works in both single-site and multisite mode)
if [ -n "${WP_INIT_TITLE:-}" ]; then
  CURRENT_MAIN_TITLE=$(wp db query "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='blogname';" --skip-column-names 2>/dev/null | tr -d '[:space:]' || echo "")
  EXPECTED_MAIN_TITLE=$(echo "${WP_INIT_TITLE}" | tr -d '[:space:]')
  if [ "$CURRENT_MAIN_TITLE" != "$EXPECTED_MAIN_TITLE" ]; then
    echo "Updating site title to: ${WP_INIT_TITLE}"
    wp option update blogname "${WP_INIT_TITLE}" 2>&1 | grep -v -e "^$" -e "^Success:" || true
  fi
fi


# ============================================================================
# Multisite Site Management (runs on every init if multisite enabled)
# ============================================================================

if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
  # Only proceed if wp_sitemeta table exists (multisite is actually set up)
  if wp_table_exists "sitemeta"; then
    # Extract domain from WP_URL for site checks
    DOMAIN_CURRENT_SITE=$(echo "${WP_URL}" | sed -E 's|^https?://||' | sed -E 's|/.*||')

    # Update network title (if provided) - can be changed without reinstall
    if [ -n "${WP_MULTISITE_TITLE:-}" ]; then
      CURRENT_TITLE=$(wp db query "SELECT meta_value FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='site_name' AND site_id=1;" --skip-column-names 2>/dev/null || echo "")
      if [ "$CURRENT_TITLE" != "${WP_MULTISITE_TITLE}" ]; then
        echo "Updating network title to: ${WP_MULTISITE_TITLE}"
        wp db query "UPDATE ${TABLE_PREFIX}sitemeta SET meta_value='${WP_MULTISITE_TITLE}' WHERE meta_key='site_name' AND site_id=1;" 2>&1 | grep -v -e "^$" -e "^Success:" || true
      fi
    fi

    # Load persistent site name → blog_id mapping
    load_site_mapping

    # Create/update sites from WP_MULTISITE_SITES JSON array
    if [ -n "${WP_MULTISITE_SITES:-}" ]; then
      echo "========================================="
      echo "Managing multisite network sites..."
      echo "========================================="

      # Parse JSON array using PHP (already available in WordPress container)
      # Export each site as "name|title|private|active|archived" format for processing
      SITES_DATA=$(php -r '
        $sites = json_decode(getenv("WP_MULTISITE_SITES"), true);
        if (!is_array($sites)) { exit(1); }
        foreach ($sites as $site) {
          if (empty($site["name"])) continue;
          $name = $site["name"];
          $title = $site["title"] ?? $name;
          $private = isset($site["private"]) && $site["private"] ? "true" : "false";
          $active = isset($site["active"]) && !$site["active"] ? "false" : "true";
          $archived = isset($site["archived"]) && $site["archived"] ? "true" : "false";
          $previousName = $site["previousName"] ?? "";
          echo "$name|$title|$private|$active|$archived|$previousName\n";
        }
      ' 2>/dev/null) || true

      if [ -z "$SITES_DATA" ]; then
        echo "WARNING: Failed to parse WP_MULTISITE_SITES JSON or no valid sites found"
      else
        MAPPING_CHANGED=false

        # Process each site (using heredoc to avoid subshell variable loss)
        while IFS='|' read -r SITE_SLUG SITE_TITLE SITE_PRIVATE SITE_ACTIVE SITE_ARCHIVED SITE_PREVIOUS_NAME; do
          if [ -z "$SITE_SLUG" ]; then
            continue
          fi

          echo "Processing site: ${SITE_SLUG}"

          # === Rename migration: previousName → name ===
          if [ -n "${SITE_PREVIOUS_NAME:-}" ]; then
            OLD_BLOG_ID=$(get_blog_id_by_name "$SITE_PREVIOUS_NAME")
            if [ -n "$OLD_BLOG_ID" ]; then
              echo "Migrating site mapping: '${SITE_PREVIOUS_NAME}' → '${SITE_SLUG}' (blog_id: ${OLD_BLOG_ID})"
              remove_name_from_mapping "$SITE_PREVIOUS_NAME"
              set_blog_id_for_name "$SITE_SLUG" "$OLD_BLOG_ID"
              MAPPING_CHANGED=true

              # Update slug/URL in database to match new name
              echo "Updating site URL slug from '${SITE_PREVIOUS_NAME}' to '${SITE_SLUG}' (blog_id: ${OLD_BLOG_ID})"
              if [ "${WP_MULTISITE_SUBDOMAIN:-false}" = "true" ]; then
                wp db query "UPDATE ${TABLE_PREFIX}blogs SET domain='${SITE_SLUG}.${DOMAIN_CURRENT_SITE}' WHERE blog_id=${OLD_BLOG_ID};" 2>&1 | grep -v -e "^$" || true
                RENAME_NEW_URL="http://${SITE_SLUG}.${DOMAIN_CURRENT_SITE}"
              else
                wp db query "UPDATE ${TABLE_PREFIX}blogs SET path='/${SITE_SLUG}/' WHERE blog_id=${OLD_BLOG_ID};" 2>&1 | grep -v -e "^$" || true
                RENAME_NEW_URL="${WP_URL%/}/${SITE_SLUG}"
              fi
              RENAME_PREFIX="${TABLE_PREFIX}"
              if [ "$OLD_BLOG_ID" != "1" ]; then
                RENAME_PREFIX="${TABLE_PREFIX}${OLD_BLOG_ID}_"
              fi
              wp db query "UPDATE ${RENAME_PREFIX}options SET option_value='${RENAME_NEW_URL}' WHERE option_name='siteurl';" 2>&1 | grep -v -e "^$" || true
              wp db query "UPDATE ${RENAME_PREFIX}options SET option_value='${RENAME_NEW_URL}' WHERE option_name='home';" 2>&1 | grep -v -e "^$" || true
              echo "Site URL updated to: ${RENAME_NEW_URL}"
            else
              echo "INFO: previousName '${SITE_PREVIOUS_NAME}' not found in mapping — ignoring"
            fi
          fi

          # === 3-stage site lookup: mapping → slug fallback → create ===
          SITE_ID=""

          # Stage 1: Lookup by stored mapping (name → blog_id)
          MAPPED_BLOG_ID=$(get_blog_id_by_name "$SITE_SLUG")
          if [ -n "$MAPPED_BLOG_ID" ]; then
            # Verify blog_id still exists in DB
            BLOG_EXISTS=$(wp db query "SELECT blog_id FROM ${TABLE_PREFIX}blogs WHERE blog_id=${MAPPED_BLOG_ID};" --skip-column-names 2>/dev/null | tr -d '[:space:]' || echo "")
            if [ -n "$BLOG_EXISTS" ]; then
              SITE_ID="$MAPPED_BLOG_ID"
              echo "Site ${SITE_SLUG} found by mapping (blog_id: ${SITE_ID})"

              # Check if slug needs updating (site was renamed in values)
              CURRENT_SLUG=$(get_site_slug_by_blog_id "$SITE_ID")
              if [ -n "$CURRENT_SLUG" ] && [ "$CURRENT_SLUG" != "$SITE_SLUG" ]; then
                echo "WARNING: Updating site URL slug from '${CURRENT_SLUG}' to '${SITE_SLUG}' — external links to the old URL will break!"
                if [ "${WP_MULTISITE_SUBDOMAIN:-false}" = "true" ]; then
                  wp db query "UPDATE ${TABLE_PREFIX}blogs SET domain='${SITE_SLUG}.${DOMAIN_CURRENT_SITE}' WHERE blog_id=${SITE_ID};" 2>&1 | grep -v -e "^$" || true
                else
                  wp db query "UPDATE ${TABLE_PREFIX}blogs SET path='/${SITE_SLUG}/' WHERE blog_id=${SITE_ID};" 2>&1 | grep -v -e "^$" || true
                fi
                # Update siteurl and home options for the renamed site
                local site_prefix="${TABLE_PREFIX}"
                if [ "$SITE_ID" != "1" ]; then
                  site_prefix="${TABLE_PREFIX}${SITE_ID}_"
                fi
                if [ "${WP_MULTISITE_SUBDOMAIN:-false}" = "true" ]; then
                  local new_site_url="http://${SITE_SLUG}.${DOMAIN_CURRENT_SITE}"
                else
                  local new_site_url="${WP_URL%/}/${SITE_SLUG}"
                fi
                wp db query "UPDATE ${site_prefix}options SET option_value='${new_site_url}' WHERE option_name='siteurl';" 2>&1 | grep -v -e "^$" || true
                wp db query "UPDATE ${site_prefix}options SET option_value='${new_site_url}' WHERE option_name='home';" 2>&1 | grep -v -e "^$" || true
              fi
            else
              echo "WARNING: Mapped blog_id ${MAPPED_BLOG_ID} for '${SITE_SLUG}' no longer exists in DB"
              remove_name_from_mapping "$SITE_SLUG"
              MAPPING_CHANGED=true
            fi
          fi

          # Stage 2: Fallback — lookup by slug in wp_blogs (backward compatibility)
          if [ -z "$SITE_ID" ]; then
            if [ "${WP_MULTISITE_SUBDOMAIN:-false}" = "true" ]; then
              SITE_ID=$(wp db query "SELECT blog_id FROM ${TABLE_PREFIX}blogs WHERE domain='${SITE_SLUG}.${DOMAIN_CURRENT_SITE}' AND path='/';" --skip-column-names 2>/dev/null | tr -d '[:space:]' || echo "")
            else
              SITE_ID=$(wp db query "SELECT blog_id FROM ${TABLE_PREFIX}blogs WHERE path='/${SITE_SLUG}/';" --skip-column-names 2>/dev/null | tr -d '[:space:]' || echo "")
            fi
            if [ -n "$SITE_ID" ]; then
              echo "Site ${SITE_SLUG} found by slug (blog_id: ${SITE_ID}) — storing mapping"
              set_blog_id_for_name "$SITE_SLUG" "$SITE_ID"
              MAPPING_CHANGED=true
            fi
          fi

          # Stage 3: Not found — create new site
          if [ -z "$SITE_ID" ]; then
            echo "Creating new site: ${SITE_SLUG}"
            SITE_ID=$(wp site create --slug="${SITE_SLUG}" --title="${SITE_TITLE}" --email="${WP_ADMIN_EMAIL}" --porcelain 2>&1) || {
              echo "ERROR: Failed to create site ${SITE_SLUG}: $SITE_ID"
              continue
            }
            if [ -z "$SITE_ID" ] || [ "$SITE_ID" = "0" ]; then
              echo "ERROR: Failed to create site ${SITE_SLUG} — invalid site ID"
              continue
            fi
            echo "Site created with ID: ${SITE_ID}"
            set_blog_id_for_name "$SITE_SLUG" "$SITE_ID"
            MAPPING_CHANGED=true
          fi

          # Always update site title (ensures title changes in values are applied)
          run wp_site "${SITE_SLUG}" option update blogname "${SITE_TITLE}" 2>/dev/null || true

          # Update site status (public/private, active/archived)
          SITE_PUBLIC=$([ "$SITE_PRIVATE" = "true" ] && echo "0" || echo "1")
          SITE_ARCHIVED_FLAG=$([ "$SITE_ARCHIVED" = "true" ] && echo "1" || echo "0")

          wp db query "UPDATE ${TABLE_PREFIX}blogs SET public='${SITE_PUBLIC}', archived='${SITE_ARCHIVED_FLAG}', deleted='0' WHERE blog_id=${SITE_ID};" 2>&1 | grep -v -e "^$" -e "^Success:" || true

          if [ "$SITE_ACTIVE" = "false" ]; then
            echo "Deactivating site ${SITE_SLUG}"
            run wp site deactivate ${SITE_ID} 2>/dev/null || true
          elif [ "$SITE_ARCHIVED" = "false" ]; then
            echo "Activating site ${SITE_SLUG}"
            run wp site activate ${SITE_ID} 2>/dev/null || true
          fi

          echo "Site ${SITE_SLUG} configured successfully!"
        done <<< "$SITES_DATA"

        # Persist site mapping if changed
        if [ "$MAPPING_CHANGED" = true ]; then
          save_site_mapping
          echo "Site mapping saved: ${SITE_MAPPING}"
        fi
      fi

      # Prune sites not in configuration (if WP_MULTISITE_PRUNE=true)
      if [ "${WP_MULTISITE_PRUNE:-false}" = "true" ]; then
        echo "Pruning sites not defined in configuration..."

        # Get all configured site slugs using PHP
        CONFIGURED_SITES=$(php -r '
          $sites = json_decode(getenv("WP_MULTISITE_SITES"), true);
          if (!is_array($sites)) { exit(1); }
          $slugs = array_filter(array_map(function($s) { return $s["name"] ?? ""; }, $sites));
          echo implode("|", $slugs);
        ' 2>/dev/null) || true

        if [ -n "$CONFIGURED_SITES" ]; then
          # Find sites in DB that are not in configuration (exclude main site ID 1)
          if [ "${WP_MULTISITE_SUBDOMAIN:-false}" = "true" ]; then
            SITES_TO_ARCHIVE=$(wp db query "SELECT blog_id, SUBSTRING_INDEX(domain, '.', 1) as slug FROM ${TABLE_PREFIX}blogs WHERE blog_id != 1 AND SUBSTRING_INDEX(domain, '.', 1) NOT REGEXP '${CONFIGURED_SITES}';" --skip-column-names 2>/dev/null || echo "")
          else
            SITES_TO_ARCHIVE=$(wp db query "SELECT blog_id, TRIM(BOTH '/' FROM path) as slug FROM ${TABLE_PREFIX}blogs WHERE blog_id != 1 AND TRIM(BOTH '/' FROM path) != '' AND TRIM(BOTH '/' FROM path) NOT REGEXP '${CONFIGURED_SITES}';" --skip-column-names 2>/dev/null || echo "")
          fi

          PRUNE_MAPPING_CHANGED=false
          if [ -n "$SITES_TO_ARCHIVE" ]; then
            while IFS=$'\t' read -r site_id site_slug; do
              [ -z "$site_id" ] && continue
              echo "Archiving unconfigured site: ${site_slug} (ID: ${site_id})"
              wp db query "UPDATE ${TABLE_PREFIX}blogs SET archived='1', deleted='0' WHERE blog_id=${site_id};" 2>&1 | grep -v -e "^$" -e "^Success:" || true
              # Remove archived site from mapping
              remove_name_from_mapping "$site_slug"
              PRUNE_MAPPING_CHANGED=true
            done <<< "$SITES_TO_ARCHIVE"
            if [ "$PRUNE_MAPPING_CHANGED" = true ]; then
              save_site_mapping
            fi
            echo "Site pruning completed!"
          else
            echo "No sites to prune."
          fi
        fi
      fi

      echo "========================================="
      echo "Multisite site management completed!"
      echo "========================================="
    fi
  fi
fi

# ============================================================================
# Acquire Configuration Lock
# Ensures only one pod performs plugin/theme/config initialization at a time
# ============================================================================

echo "Acquiring configuration lock for initialization..."
if ! claim_config_lock; then
  echo "ERROR: Timeout waiting for configuration lock after ${MAX_LOCK_WAIT}s"
  echo "Another pod may be stuck. Check its logs for errors."
  exit 1
fi

echo "Configuration lock acquired, proceeding with initialization..."

# ============================================================================
# Disable WordPress Core Auto-Updates (managed by Helm chart via image updates)
# ============================================================================

# Only run if wp_options table exists (skip for fresh installs without WP_INIT=true)
if wp_table_exists "options"; then
  echo "Disabling WordPress core auto-updates..."
  # Update all 3 settings in one multi-row query (faster than 3 separate queries)
  wp db query "
    INSERT INTO ${TABLE_PREFIX}options (option_name, option_value, autoload) VALUES
      ('auto_update_core_dev', 'disabled', 'yes'),
      ('auto_update_core_minor', 'disabled', 'yes'),          ('auto_update_core_major', 'disabled', 'yes')
    ON DUPLICATE KEY UPDATE option_value='disabled';
  " 2>&1 | grep -v -e "^$" -e "^Success:" || true
  echo "Core auto-updates disabled!"
else
  echo "Skipping WordPress configuration (database tables not ready yet)"
  # Skip all DB-dependent configuration if tables don't exist
  {{- if .Values.wordpress.users }}
  echo "Skipping custom user creation (database not ready)"
  {{- end }}
  echo "Continuing to plugin/theme management..."
  exit 0  # Exit early, WordPress needs to be set up first
fi

# ============================================================================
# WordPress Configuration (Localization, Permalinks, User Metadata)
# ============================================================================


if [ "${WP_INIT}" = "true" ]; then
  # Set language (with single check)
  if [ -n "${WP_LOCALE}" ]; then
    echo "Checking language pack status for ${WP_LOCALE}..."
    LANG_STATUS=$(wp language core list --language=${WP_LOCALE} --field=status 2>/dev/null || echo "uninstalled")
    case $LANG_STATUS in
      "uninstalled")
        echo "Installing language pack: ${WP_LOCALE}..."
        wp language core install ${WP_LOCALE} --activate
        ;;
      "installed")
        wp site switch-language ${WP_LOCALE}
        ;;
    esac

    # Check if language pack update is available (single check)
    LANG_UPDATE=$(wp language core list --language=${WP_LOCALE} --field=update 2>/dev/null || echo "none")
    if [ "$LANG_UPDATE" = "available" ]; then
      echo "Updating language pack for ${WP_LOCALE}..."
      wp language core update || true
    fi
  fi

  # Set permalinks (using wp-cli for proper escaping)
  if [ -n "${WP_PERMALINK_STRUCTURE}" ]; then
    echo "Checking permalink structure..."
    CURRENT_PERMALINK=$(wp option get permalink_structure 2>/dev/null || echo "")
    if [ "$CURRENT_PERMALINK" != "$WP_PERMALINK_STRUCTURE" ]; then
      echo "Setting WordPress permalinks to: ${WP_PERMALINK_STRUCTURE}"
      wp option update permalink_structure "${WP_PERMALINK_STRUCTURE}" >/dev/null 2>&1
      # Delete rewrite_rules to force WordPress to regenerate them on next page load
      wp db query "DELETE FROM ${TABLE_PREFIX}options WHERE option_name='rewrite_rules';" >/dev/null 2>&1 || true
      echo "Permalink structure updated (rewrite rules will be regenerated automatically)"
    fi
  fi

  # Set admin user metadata
  if [ -n "${WP_ADMIN_FIRSTNAME}" ] || [ -n "${WP_ADMIN_LASTNAME}" ]; then
    echo "Checking admin user metadata..."
  fi
  if [ -n "${WP_ADMIN_FIRSTNAME}" ]; then
    CURRENT_FIRSTNAME=$(wp user meta get "$WP_ADMIN_USER" first_name 2>/dev/null || echo "")
    if [ "$CURRENT_FIRSTNAME" != "$WP_ADMIN_FIRSTNAME" ]; then
      echo "Setting admin first name..."
      wp user meta update "$WP_ADMIN_USER" first_name "$WP_ADMIN_FIRSTNAME"
    fi
  fi
  if [ -n "${WP_ADMIN_LASTNAME}" ]; then
    CURRENT_LASTNAME=$(wp user meta get "$WP_ADMIN_USER" last_name 2>/dev/null || echo "")
    if [ "$CURRENT_LASTNAME" != "$WP_ADMIN_LASTNAME" ]; then
      echo "Setting admin last name..."
      wp user meta update "$WP_ADMIN_USER" last_name "$WP_ADMIN_LASTNAME"
    fi
  fi
fi


# ============================================================================
# Create Custom Users
# ============================================================================


{{- if .Values.wordpress.users }}
echo "Creating custom users..."
EXISTING_USERS=$(wp user list --field=user_login 2>/dev/null || echo "")


{{- range .Values.wordpress.users }}
if ! echo "$EXISTING_USERS" | grep -q "^{{ .username }}$"; then
  echo "Creating user {{ .username }}..."
  run wp user create {{ .username | quote }} {{ .email | quote }} \
    --role={{ .role | quote }} \
    --display_name={{ .displayname | quote }} \
    --first_name={{ .firstname | quote }} \
    --last_name={{ .lastname | quote }} \
    --send-email={{ .sendEmail | quote }}
else
  echo "User {{ .username }} already exists, skipping."
fi
{{- if and .superAdmin ($.Values.wordpress.init.multiSites.enabled) }}
# Grant super-admin privileges
if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
  CURRENT_SUPERS=$(wp super-admin list 2>/dev/null || echo "")
  if ! echo "$CURRENT_SUPERS" | grep -q "^{{ .username }}$"; then
    echo "Granting super-admin to {{ .username }}..."
    run wp super-admin add {{ .username | quote }} || echo "Warning: Could not grant super-admin to {{ .username }}"
  else
    echo "User {{ .username }} is already a super-admin."
  fi
fi
{{- end }}
{{- if and .sites ($.Values.wordpress.init.multiSites.enabled) }}
{{- $username := .username }}
# Assign user to specific sites with roles
if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
  {{- range .sites }}
  echo "Assigning user {{ $username }} to site {{ .name }} with role {{ .role }}..."
  run wp_site "{{ .name }}" user set-role {{ $username | quote }} {{ .role | quote }} 2>/dev/null || \
    echo "Warning: Could not assign {{ $username }} to site {{ .name }}"
  {{- end }}
fi
{{- end }}
{{- end }}
{{- else }}
echo "No custom users specified."
{{- end }}

# ============================================================================
# Composer Configuration
# ============================================================================

# Only initialize Composer if we have Composer packages to install
{{- if or .Values.wordpress.plugins .Values.wordpress.themes }}
{{- $composerPluginPackages := list }}
{{- range .Values.wordpress.plugins }}
{{- $name := .name | lower }}
{{- if and (contains "/" $name) (not (hasPrefix "http://" $name)) (not (hasPrefix "https://" $name)) }}
{{- $composerPluginPackages = append $composerPluginPackages $name }}
{{- end }}
{{- end }}
{{- $composerThemePackages := list }}
{{- range .Values.wordpress.themes }}
{{- $name := .name | lower }}
{{- if and (contains "/" $name) (not (hasPrefix "http://" $name)) (not (hasPrefix "https://" $name)) }}
{{- $composerThemePackages = append $composerThemePackages $name }}
{{- end }}
{{- end }}
HAS_COMPOSER_PACKAGES=false
{{- if .Values.wordpress.plugins }}
{{- range .Values.wordpress.plugins }}
{{- $name := .name }}
{{- if and (contains "/" $name) (not (hasPrefix "http://" $name)) (not (hasPrefix "https://" $name)) }}
HAS_COMPOSER_PACKAGES=true
{{- end }}
{{- end }}
{{- end }}
{{- if .Values.wordpress.themes }}
{{- range .Values.wordpress.themes }}
{{- $name := .name }}
{{- if and (contains "/" $name) (not (hasPrefix "http://" $name)) (not (hasPrefix "https://" $name)) }}
HAS_COMPOSER_PACKAGES=true
{{- end }}
{{- end }}
{{- end }}

if [ "$HAS_COMPOSER_PACKAGES" = "true" ]; then
  echo "========================================="
  echo "Setting up Composer configuration..."
  echo "========================================="
  ensure_composer
  cd /var/www/html || handle_error "Failed to change to /var/www/html directory"

  # Track if any Composer packages were installed/updated (to run composer install later)
  COMPOSER_PACKAGES_MODIFIED=false

  # Initialize composer.json if it doesn't exist
  if [ ! -f composer.json ]; then
    echo "Creating composer.json..."
    cat > composer.json << 'COMPOSERJSON'
{
  "name": "wordpress/site",
  "description": "WordPress site managed by Helm",
  "type": "project",
  "require": {},
  "repositories": [
    {
      "type": "composer",
      "url": "https://wpackagist.org"
    }{{- if .Values.wordpress.composer.repositories }}{{- range .Values.wordpress.composer.repositories }},
    {
      "type": "{{ .type }}",
      "url": "{{ .url }}"{{- if .options }},
      "options": {{ .options | toJson }}{{- end }}
    }{{- end }}{{- end }}
  ],
  "extra": {
    "installer-paths": {
      "wp-content/plugins/{$name}/": ["type:wordpress-plugin"],
      "wp-content/themes/{$name}/": ["type:wordpress-theme"]
    }
  },
  "config": {
    "allow-plugins": {
      "composer/installers": true
    }
  }
}
COMPOSERJSON
    echo "composer.json created!"
  else
    [ "${DEBUG}" = "true" ] && echo "DEBUG: composer.json already exists"
  fi

  CUSTOM_REPOS='{{ default (list) .Values.wordpress.composer.repositories | toJson }}'
  COMPOSER_PLUGIN_PACKAGES='{{ $composerPluginPackages | toJson }}'
  COMPOSER_THEME_PACKAGES='{{ $composerThemePackages | toJson }}'

  TEMP_JSON=$(sync_composer_json "$CUSTOM_REPOS" "$COMPOSER_PLUGIN_PACKAGES" "$COMPOSER_THEME_PACKAGES") || handle_error "Failed to synchronize composer.json"
  echo "$TEMP_JSON" > composer.json
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Composer repositories and installer paths synchronized"

  # Set allow-plugins config before requiring composer/installers
  composer config --no-plugins allow-plugins.composer/installers true

  # Ensure composer/installers is available for installer-paths
  if ! composer show composer/installers &>/dev/null; then
    echo "Installing composer/installers..."
    if ! COMPOSER_OUTPUT=$(retry_command composer_run_filtered require composer/installers --no-interaction --quiet); then
      echo "$COMPOSER_OUTPUT"
      handle_error "Error installing composer/installers (failed after retries)"
    fi
  fi
fi
{{- end }}

# ============================================================================
# Plugin Management
# ============================================================================
#
# Process Overview:
#   1. Cache plugin lists upfront (avoid repeated wp-cli calls)
#   2. Detect package type (Composer vs WP repository vs URL)
#   3. Validate package names for security
#   4. Batch operations for performance
#   5. Install with retry logic for network resilience
#   6. Activate and configure auto-updates
#
# Performance Optimizations:
#   - Batch installation (wp plugin install plugin1 plugin2 plugin3)
#   - Cached plugin lists (single wp-cli call)
#   - Skip already installed packages
#
# Error Handling:
#   - Validation errors: Skip package with warning
#   - Network errors: Retry with exponential backoff
#   - Composer errors: Exit with detailed message

# Cache all plugin data upfront for performance (using fast DB queries)
# Single query with all fields, then derive individual lists (3x fewer DB queries + filesystem scans)
echo "Caching plugin data..."
ALL_PLUGIN_DATA=$(wp_plugin_list --fields=name,status,auto_update --format=csv 2>/dev/null || echo "")
INSTALLED_PLUGINS=$(echo "$ALL_PLUGIN_DATA" | tail -n +2 | cut -d',' -f1 || echo "")
ACTIVE_PLUGINS=$(echo "$ALL_PLUGIN_DATA" | grep ",active," | cut -d',' -f1 || echo "")
AUTOUPDATE_ENABLED=$(echo "$ALL_PLUGIN_DATA" | grep ",on$" | cut -d',' -f1 || echo "")

# Detect if a name is a Composer package (vendor/package format)
#
# Args:
#   $1 - Package name to check
#
# Returns:
#   0 - Is a Composer package (contains / but not URL)
#   1 - Not a Composer package
#
# Performance:
#   String pattern matching (fast, no subprocess)
#
# Examples:
#   is_composer_package "wpackagist-plugin/akismet" -> 0 (true)
#   is_composer_package "akismet" -> 1 (false)
#   is_composer_package "https://example.com/plugin.zip" -> 1 (false)
is_composer_package() {
  local name="$1"
  # Check if it contains / and doesn't start with http:// or https://
  if [[ "$name" == */* ]] && [[ "$name" != http://* ]] && [[ "$name" != https://* ]]; then
    return 0
  fi
  return 1
}

# Extract WordPress slug from Composer package name
# Example: wpackagist-plugin/akismet -> akismet
#
# Args:
#   $1 - Composer package name (vendor/package)
#
# Returns:
#   Package portion after the slash
get_composer_slug() {
  local package="$1"
  # Extract part after the /
  echo "${package##*/}"
}

# Handle metrics plugin
if [ -n "${WORDPRESS_METRICS}" ]; then
  if ! echo "$INSTALLED_PLUGINS" | grep -q "^${WORDPRESS_METRICS}$"; then
    echo "Installing WordPress metrics plugin..."
    wp plugin install ${WORDPRESS_METRICS}
    PLUGINS_MODIFIED=true
  fi
{{- if and .Values.wordpress.init.multiSites.enabled (default true .Values.metrics.wordpress.networkActivate) }}
  # Multisite: network-activate metrics plugin
  NETWORK_ACTIVE_CHECK=$(wp db query "SELECT meta_value FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='active_sitewide_plugins' AND site_id=1;" --skip-column-names 2>/dev/null || echo "")
  if ! echo "$NETWORK_ACTIVE_CHECK" | grep -qF "${WORDPRESS_METRICS}"; then
    echo "Network-activating metrics plugin: ${WORDPRESS_METRICS}"
    run wp_network plugin activate ${WORDPRESS_METRICS} || echo "Warning: Could not network-activate metrics plugin"
    PLUGINS_MODIFIED=true
  fi
{{- else }}
  # Single-site: activate on main site only
  if ! echo "$ACTIVE_PLUGINS" | grep -q "^${WORDPRESS_METRICS}$"; then
    wp plugin activate ${WORDPRESS_METRICS} 2>/dev/null || true
    PLUGINS_MODIFIED=true
  fi
{{- end }}
fi

{{- if .Values.wordpress.init.jwt.enabled }}
# JWT Authentication plugin (jwt-authentication-for-wp-rest-api)
JWT_PLUGIN="jwt-authentication-for-wp-rest-api"
echo "Checking JWT Authentication plugin..."
if ! echo "$INSTALLED_PLUGINS" | grep -q "^${JWT_PLUGIN}$"; then
  echo "Installing ${JWT_PLUGIN}..."
  run wp plugin install "${JWT_PLUGIN}" --activate
  PLUGINS_MODIFIED=true
elif ! echo "$ACTIVE_PLUGINS" | grep -q "^${JWT_PLUGIN}$"; then
  echo "Activating ${JWT_PLUGIN}..."
  run wp plugin activate "${JWT_PLUGIN}"
else
  echo "${JWT_PLUGIN} already installed and active."
fi
{{- end }}

# Handle custom plugins
{{- if .Values.wordpress.plugins }}
echo "========================================="
echo "Processing plugins..."
echo "========================================="

PLUGINS_TO_INSTALL=()
PLUGINS_TO_ACTIVATE=()
PLUGINS_TO_DEACTIVATE=()    # Plugins with explicit activate: false (deactivate on main site)
PLUGINS_TO_AUTOUPDATE=()
PLUGINS_TO_NETWORK_ACTIVATE=()     # Multisite: networkActivate plugins

COMPOSER_PLUGINS_TO_INSTALL=()
COMPOSER_PLUGINS_TO_ACTIVATE=()
COMPOSER_PLUGINS_TO_UPDATE=()
COMPOSER_PLUGIN_PACKAGE_TARGETS=()
COMPOSER_PLUGINS_TO_NETWORK_ACTIVATE=()  # Multisite: networkActivate Composer plugins
COMPOSER_PLUGINS_PENDING_NETWORK_ACTIVATION=()  # Retry after composer install

{{- if and .Values.wordpress.init.enabled .Values.wordpress.init.multiSites.enabled }}
{{- $allSites := list }}
{{- range .Values.wordpress.init.multiSites.sites }}
{{- $allSites = append $allSites .name }}
{{- end }}
# Initialize site-specific plugin activation arrays
{{- range $allSites }}
{{- $siteVar := . | upper | replace "-" "_" }}
PLUGINS_SITE_ACTIVATE_{{ $siteVar }}=()
{{- end }}
{{- end }}

{{- range .Values.wordpress.plugins }}
# Plugin: {{ .name | lower }}
PLUGIN_NAME="{{ .name | lower }}"

# Validate package name before processing
if ! validate_package_name "$PLUGIN_NAME"; then
  echo "Skipping invalid plugin name: $PLUGIN_NAME"
  continue
fi

# Check if it's a Composer package
if is_composer_package "$PLUGIN_NAME"; then
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Detected Composer package: $PLUGIN_NAME"
  COMPOSER_SLUG=$(get_composer_slug "$PLUGIN_NAME")
  COMPOSER_PLUGIN_PACKAGE_TARGETS+=("$PLUGIN_NAME:$COMPOSER_SLUG")

  # Check if already installed via composer.json AND plugin directory exists
  # Plugin might be in composer.json but files deleted (e.g., after pruning)
  if composer_package_is_required "$PLUGIN_NAME" /var/www/html/composer.json; then
    if [ -d "/var/www/html/${WP_PLUGINS_DIR}/${COMPOSER_SLUG}" ]; then
      [ "${DEBUG}" = "true" ] && echo "DEBUG: Composer package $PLUGIN_NAME already installed"

      {{- if .autoupdate }}
      {{- if not .version }}
      # Auto-update only works for packages without fixed version AND already installed
      COMPOSER_PLUGINS_TO_UPDATE+=("$PLUGIN_NAME")
      {{- else }}
      echo "Note: Auto-update skipped for $PLUGIN_NAME (fixed version specified)"
      {{- end }}
      {{- end }}
    else
      # Package in composer.json but files missing - need to run composer install
      echo "Composer package $PLUGIN_NAME in composer.json but plugin directory missing - will reinstall"
      COMPOSER_PACKAGES_MODIFIED=true
    fi
  else
    {{- if .version }}
    COMPOSER_PLUGINS_TO_INSTALL+=("{{ .name | lower }}:{{ .version }}")
    {{- else }}
    COMPOSER_PLUGINS_TO_INSTALL+=("$PLUGIN_NAME")
    {{- end }}
  fi

  {{- if and .networkActivate ($.Values.wordpress.init.multiSites.enabled) }}
  COMPOSER_PLUGINS_TO_NETWORK_ACTIVATE+=("$COMPOSER_SLUG")
  {{- else }}
  {{- if .activate }}
  COMPOSER_PLUGINS_TO_ACTIVATE+=("$COMPOSER_SLUG")
  {{- end }}
  {{- if .sites }}
  # Build site-specific activation arrays for Composer plugin
  {{- range .sites }}
  {{- $siteVar := . | upper | replace "-" "_" }}
  PLUGINS_SITE_ACTIVATE_{{ $siteVar }}+=("$COMPOSER_SLUG")
  {{- end }}
  {{- end }}
  {{- end }}
# Check if it's a URL (at runtime, not template time)
elif [[ "$PLUGIN_NAME" == http://* ]] || [[ "$PLUGIN_NAME" == https://* ]]; then
  echo "Installing URL plugin: $PLUGIN_NAME"
  {{- if .slug }}
  URL_SLUG="{{ .slug | lower }}"
  {{- else }}
  URL_SLUG=$(basename "$PLUGIN_NAME" .zip 2>/dev/null || echo "")
  {{- end }}

  # Install the plugin
  {{- if .slug }}
  if ! echo "$INSTALLED_PLUGINS" | grep -q "^{{ .slug | lower }}$"; then
    INSTALL_OUTPUT=$(wp plugin install "$PLUGIN_NAME" 2>&1) || echo "Warning: Failed to install URL plugin"
    echo "$INSTALL_OUTPUT" | grep -v "already installed" || true
  else
    [ "${DEBUG}" = "true" ] && echo "DEBUG: URL plugin {{ .slug | lower }} already installed, skipping"
  fi
  {{- else }}
  INSTALL_OUTPUT=$(wp plugin install "$PLUGIN_NAME" 2>&1) || echo "Warning: Failed to install URL plugin"
  echo "$INSTALL_OUTPUT" | grep -v "already installed" || true
  {{- end }}

  {{- if and .networkActivate ($.Values.wordpress.init.multiSites.enabled) }}
  # Network-activate URL plugin
  if [ -n "$URL_SLUG" ]; then
    PLUGINS_TO_NETWORK_ACTIVATE+=("$URL_SLUG")
  fi
  {{- else }}
  {{- if .activate }}
  # Activate on main site
  if [ -n "$URL_SLUG" ]; then
    PLUGINS_TO_ACTIVATE+=("$URL_SLUG")
  fi
  {{- end }}
  {{- if .sites }}
  # Activate on specific sites
  if [ -n "$URL_SLUG" ]; then
    {{- range .sites }}
    {{- $siteVar := . | upper | replace "-" "_" }}
    PLUGINS_SITE_ACTIVATE_{{ $siteVar }}+=("$URL_SLUG")
    {{- end }}
  fi
  {{- end }}
  {{- end }}

  {{- if .autoupdate }}
  # Enable auto-updates (requires known slug)
  if [ -n "$URL_SLUG" ]; then
    PLUGINS_TO_AUTOUPDATE+=("$URL_SLUG")
  fi
  {{- end }}
else
  # Named plugin - add to batch processing
  if ! echo "$INSTALLED_PLUGINS" | grep -q "^${PLUGIN_NAME}$"; then
    {{- if .version }}
    PLUGINS_TO_INSTALL+=("{{ .name | lower }}:{{ .version }}")
    {{- else }}
    PLUGINS_TO_INSTALL+=("{{ .name | lower }}")
    {{- end }}
  fi
  {{- if and .networkActivate ($.Values.wordpress.init.multiSites.enabled) }}
  PLUGINS_TO_NETWORK_ACTIVATE+=("{{ .name | lower }}")
  {{- else }}
  {{- if .activate }}
  {{- if eq (.name | lower) "memcached" }}
  echo "Info: memcached plugin is a drop-in provider; skipping normal plugin activation to avoid wp_cache_* redeclare errors."
  {{- else }}
  PLUGINS_TO_ACTIVATE+=("{{ .name | lower }}")
  {{- end }}
  {{- end }}
  {{- if and (hasKey . "activate") (not .activate) }}
  # Explicit activate: false — deactivate on main site if currently active
  PLUGINS_TO_DEACTIVATE+=("{{ .name | lower }}")
  {{- end }}
  {{- if .sites }}
  {{- $pluginName := .name | lower }}
  # Build site-specific activation arrays for {{ $pluginName }}
  {{- range .sites }}
  {{- $siteVar := . | upper | replace "-" "_" }}
  PLUGINS_SITE_ACTIVATE_{{ $siteVar }}+=("{{ $pluginName }}")
  {{- end }}
  {{- end }}
  {{- end }}
  {{- if .autoupdate }}
  PLUGINS_TO_AUTOUPDATE+=("{{ .name | lower }}")
  {{- end }}
fi
{{- end }}

# Batch install plugins
if [ ${#PLUGINS_TO_INSTALL[@]} -gt 0 ]; then
  echo "Installing ${#PLUGINS_TO_INSTALL[@]} plugin(s)..."


  PLUGINS_NO_VERSION=()
  PLUGINS_WITH_VERSION=()


  for plugin_spec in "${PLUGINS_TO_INSTALL[@]}"; do
    if [[ "$plugin_spec" == *":"* ]]; then
      PLUGINS_WITH_VERSION+=("$plugin_spec")
    else
      PLUGINS_NO_VERSION+=("$plugin_spec")
    fi
  done


  if [ ${#PLUGINS_NO_VERSION[@]} -gt 0 ]; then
    if ! OUTPUT=$(retry_command wp plugin install "${PLUGINS_NO_VERSION[@]}" 2>&1); then
      echo "$OUTPUT" | grep -v "already installed"
      echo "Warning: Some plugins failed to install"
    elif [ "${DEBUG}" = "true" ]; then
      echo "$OUTPUT"
    fi
  fi


  for plugin_spec in "${PLUGINS_WITH_VERSION[@]}"; do
    PLUGIN_NAME="${plugin_spec%%:*}"
    PLUGIN_VERSION="${plugin_spec##*:}"
    if ! OUTPUT=$(retry_command wp plugin install "${PLUGIN_NAME}" --version="${PLUGIN_VERSION}" 2>&1); then
      echo "$OUTPUT" | grep -v "already installed"
      echo "Warning: Failed to install plugin: ${PLUGIN_NAME}"
    elif [ "${DEBUG}" = "true" ]; then
      echo "$OUTPUT"
    fi
  done


  INSTALLED_PLUGINS=$(wp_plugin_list --field=name 2>/dev/null || echo "")
  ACTIVE_PLUGINS=$(wp_plugin_list --status=active --field=name 2>/dev/null || echo "")
fi

# Install Composer plugins (batch operation for performance)
if [ ${#COMPOSER_PLUGINS_TO_INSTALL[@]} -gt 0 ]; then
  echo "Installing ${#COMPOSER_PLUGINS_TO_INSTALL[@]} Composer plugin(s)..."

  # Try batch install first (faster: single dependency resolution)
  all_packages="${COMPOSER_PLUGINS_TO_INSTALL[@]}"
  echo "Attempting batch install: $all_packages"

  if COMPOSER_OUTPUT=$(retry_command composer require $all_packages --no-interaction 2>&1); then
    echo "Batch install successful!"
  else
    echo "Batch install failed, falling back to individual installs..."
    echo "$COMPOSER_OUTPUT"

    # Fallback: Install individually
    for package_spec in "${COMPOSER_PLUGINS_TO_INSTALL[@]}"; do
      echo "Installing Composer package: $package_spec"
      if ! COMPOSER_OUTPUT=$(retry_command composer require "$package_spec" --no-interaction 2>&1); then
        echo "$COMPOSER_OUTPUT"
        handle_error "Error installing Composer package: $package_spec (failed after retries)"
      fi
    done
  fi

  echo "Composer plugins installed!"
  COMPOSER_PACKAGES_MODIFIED=true
  # Don't refresh plugin lists here - will do single refresh later
fi

# Update Composer plugins (auto-update for packages without fixed version)
if [ ${#COMPOSER_PLUGINS_TO_UPDATE[@]} -gt 0 ]; then
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Checking for Composer plugin updates..."

  # Get list of outdated packages once (performance optimization)
  OUTDATED_PACKAGES=$(composer outdated --direct --format=json 2>/dev/null | php -r '
    $json = json_decode(file_get_contents("php://stdin"), true);
    if (isset($json["installed"])) {
      foreach ($json["installed"] as $pkg) {
        echo $pkg["name"] . "\n";
      }
    }
  ' 2>/dev/null || echo "")

  PLUGINS_UPDATED=0
  for package in "${COMPOSER_PLUGINS_TO_UPDATE[@]}"; do
    # Check if package has an available update
    if echo "$OUTDATED_PACKAGES" | grep -q "^${package}$"; then
      echo "Updating Composer package: $package"
      # Capture output and only show on error, with retry logic
      if ! COMPOSER_OUTPUT=$(retry_command composer update "$package" --no-interaction 2>&1); then
        echo "$COMPOSER_OUTPUT"
        handle_error "Error updating Composer package: $package (failed after retries)"
      fi
      PLUGINS_UPDATED=$((PLUGINS_UPDATED + 1))
    else
      [ "${DEBUG}" = "true" ] && echo "DEBUG: Package $package is already up to date" >&2
    fi
  done

  if [ $PLUGINS_UPDATED -gt 0 ]; then
    echo "$PLUGINS_UPDATED Composer plugin(s) updated!"
    COMPOSER_PACKAGES_MODIFIED=true
  fi
fi

# Install Composer dependencies for plugins NOW (before theme installation)
# This ensures plugins like s3-uploads have their dependencies (e.g., AWS SDK)
# available before WordPress loads them during theme installation
# Always run this section to ensure plugin dependencies are installed, even if
# packages were not modified in this run (e.g., for existing installations)
echo ""
echo "========================================="
echo "Checking plugin Composer dependencies..."
echo "========================================="

# Run composer install for main project first (only if composer.json exists and was modified)
COMPOSER_INSTALL_DONE=false
if [ -f composer.json ] && { [ "$COMPOSER_PACKAGES_MODIFIED" = "true" ] || [ ${#COMPOSER_PLUGINS_TO_INSTALL[@]} -gt 0 ]; }; then
  if ! COMPOSER_OUTPUT=$(retry_command composer_run_filtered install --no-interaction); then
    echo "$COMPOSER_OUTPUT"
    handle_error "Error installing Composer dependencies (failed after retries)"
  fi
  COMPOSER_INSTALL_DONE=true
fi

  # Build list of Composer-installed plugin slugs
  COMPOSER_PLUGIN_SLUGS=""
  if [ -f composer.json ]; then
    COMPOSER_PLUGIN_SLUGS=$(php -r '
      $json = json_decode(file_get_contents("composer.json"), true);
      if (isset($json["require"])) {
        foreach ($json["require"] as $package => $version) {
          if (strpos($package, "/") !== false &&
              $package !== "composer/installers") {
            $slug = substr($package, strrpos($package, "/") + 1);
            echo $slug . "\n";
          }
        }
      }
    ' 2>/dev/null || echo "")
  fi

  # Link vendor-installed Composer library packages into wp-content/plugins so
  # WordPress can discover and activate them.
  for package_target in "${COMPOSER_PLUGIN_PACKAGE_TARGETS[@]}"; do
    PACKAGE_NAME="${package_target%%:*}"
    PACKAGE_SLUG="${package_target#*:}"
    TARGET_DIR="/var/www/html/${WP_PLUGINS_DIR}/${PACKAGE_SLUG}"
    if [ ! -d "$TARGET_DIR" ] && link_vendor_package_into_wordpress_dir "$PACKAGE_NAME" "$TARGET_DIR"; then
      echo "Linked Composer package into plugins directory: $PACKAGE_NAME -> ${WP_PLUGINS_DIR}/${PACKAGE_SLUG}"
    fi
  done

  # Install dependencies for each Composer-installed plugin (with skip check)
  for plugin_dir in ${WP_PLUGINS_DIR}/*/; do
    if [ -f "${plugin_dir}composer.json" ]; then
      PLUGIN_NAME=$(basename "$plugin_dir")

      if echo "$COMPOSER_PLUGIN_SLUGS" | grep -q "^${PLUGIN_NAME}$"; then
        # Skip if vendor/ exists and is not empty
        if [ -d "${plugin_dir}vendor" ] && [ -n "$(ls -A "${plugin_dir}vendor" 2>/dev/null)" ]; then
          [ "${DEBUG}" = "true" ] && echo "DEBUG: Skipping composer install for $PLUGIN_NAME (vendor/ exists)" >&2
          continue
        fi

        echo "Running composer install in plugin: $PLUGIN_NAME"
        cd "$plugin_dir" || continue

        echo "Installing Composer dependencies (this may take a while for plugins with many dependencies)..."

        if COMPOSER_PLUGIN_OUTPUT=$(retry_command composer_run_filtered install --no-dev --no-interaction --ignore-platform-reqs --no-security-blocking --no-progress 2>&1); then
          echo "$COMPOSER_PLUGIN_OUTPUT"
          echo "Successfully installed dependencies for plugin: $PLUGIN_NAME"
        else
          composer_exit=$?
          echo "$COMPOSER_PLUGIN_OUTPUT"
          echo "Warning: Could not install dependencies for plugin: $PLUGIN_NAME (Exit code: $composer_exit)"
          # Don't fail the whole init script, just warn
        fi

        cd /var/www/html || handle_error "Cannot return to WordPress root directory"
      fi
    fi
  done

  # Create MU-Plugin for Composer autoloader support early
  echo "Creating MU-Plugin for Composer autoloader support..."
  mkdir -p "${WP_MU_PLUGINS_DIR}"
  cat > "${WP_MU_PLUGINS_DIR}/composer-autoloader.php" << 'MUEOF'
<?php
/**
 * Plugin Name: Composer Autoloader
 * Description: Loads Composer autoloaders from active plugins and active theme
 * Author: Helm Chart
 * Version: 1.1.0
 */

// Only load autoloaders for active plugins (skip deactivated ones for security)
$active_plugins = get_option( 'active_plugins', array() );
foreach ( $active_plugins as $plugin ) {
	$plugin_dir = dirname( WP_CONTENT_DIR . '/plugins/' . $plugin );
	$autoloader = $plugin_dir . '/vendor/autoload.php';
	if ( file_exists( $autoloader ) ) {
		require_once $autoloader;
	}
}

// Load Composer autoloader from active theme only
$theme_autoloader = get_template_directory() . '/vendor/autoload.php';
if ( file_exists( $theme_autoloader ) ) {
	require_once $theme_autoloader;
}
MUEOF
  echo "Composer autoloader MU-Plugin created!"
  echo "Plugin dependencies checked!"

# Batch deactivate plugins (explicit activate: false)
if [ ${#PLUGINS_TO_DEACTIVATE[@]} -gt 0 ]; then
  PLUGINS_NEED_DEACTIVATION=()
  for plugin in "${PLUGINS_TO_DEACTIVATE[@]}"; do
    if echo "$ACTIVE_PLUGINS" | grep -q "^${plugin}$"; then
      PLUGINS_NEED_DEACTIVATION+=("$plugin")
    fi
  done

  if [ ${#PLUGINS_NEED_DEACTIVATION[@]} -gt 0 ]; then
    echo "Deactivating ${#PLUGINS_NEED_DEACTIVATION[@]} plugin(s) on main site..."
    wp plugin deactivate "${PLUGINS_NEED_DEACTIVATION[@]}" 2>/dev/null || echo "Warning: Some plugins could not be deactivated"
    PLUGINS_MODIFIED=true
  fi
fi

# Batch activate plugins
if [ ${#PLUGINS_TO_ACTIVATE[@]} -gt 0 ]; then
  PLUGINS_NEED_ACTIVATION=()
  for plugin in "${PLUGINS_TO_ACTIVATE[@]}"; do
    if ! echo "$ACTIVE_PLUGINS" | grep -q "^${plugin}$"; then
      PLUGINS_NEED_ACTIVATION+=("$plugin")
    fi
  done

  if [ ${#PLUGINS_NEED_ACTIVATION[@]} -gt 0 ]; then
    echo "Activating ${#PLUGINS_NEED_ACTIVATION[@]} plugin(s)..."
    wp plugin activate "${PLUGINS_NEED_ACTIVATION[@]}" 2>/dev/null || echo "Warning: Some plugins could not be activated"
    PLUGINS_MODIFIED=true
  fi
fi

# Batch network-activate plugins (multisite)
if [ ${#PLUGINS_TO_NETWORK_ACTIVATE[@]} -gt 0 ] && [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
  PLUGINS_NEED_NETWORK_ACTIVATION=()
  # Check which plugins are not yet network-active
  NETWORK_ACTIVE_PLUGINS=$(wp db query "SELECT meta_value FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='active_sitewide_plugins' AND site_id=1;" --skip-column-names 2>/dev/null || echo "")
  for plugin in "${PLUGINS_TO_NETWORK_ACTIVATE[@]}"; do
    if [ -n "$NETWORK_ACTIVE_PLUGINS" ] && echo "$NETWORK_ACTIVE_PLUGINS" | grep -qF "$plugin"; then
      [ "${DEBUG}" = "true" ] && echo "DEBUG: Plugin $plugin already network-active"
    else
      PLUGINS_NEED_NETWORK_ACTIVATION+=("$plugin")
    fi
  done

  if [ ${#PLUGINS_NEED_NETWORK_ACTIVATION[@]} -gt 0 ]; then
    echo "Network-activating ${#PLUGINS_NEED_NETWORK_ACTIVATION[@]} plugin(s)..."
    run wp_network plugin activate "${PLUGINS_NEED_NETWORK_ACTIVATION[@]}" || echo "Warning: Some plugins could not be network-activated"
    PLUGINS_MODIFIED=true
  fi
fi

# Activate Composer plugins
# NOTE: This may fail if composer install hasn't run yet - will be retried after composer install
if [ ${#COMPOSER_PLUGINS_TO_ACTIVATE[@]} -gt 0 ]; then
  COMPOSER_PLUGINS_NEED_ACTIVATION=()
  for plugin in "${COMPOSER_PLUGINS_TO_ACTIVATE[@]}"; do
    if ! echo "$ACTIVE_PLUGINS" | grep -q "^${plugin}$"; then
      COMPOSER_PLUGINS_NEED_ACTIVATION+=("$plugin")
    fi
  done

  if [ ${#COMPOSER_PLUGINS_NEED_ACTIVATION[@]} -gt 0 ]; then
    echo "Activating ${#COMPOSER_PLUGINS_NEED_ACTIVATION[@]} Composer plugin(s)..."
    # Don't fail here - plugins may not exist yet if composer install hasn't run
    # They will be activated after composer install runs
    if ! run wp plugin activate "${COMPOSER_PLUGINS_NEED_ACTIVATION[@]}"; then
      echo "Note: Some Composer plugins couldn't be activated yet - will retry after composer install"
      COMPOSER_PLUGINS_PENDING_ACTIVATION=("${COMPOSER_PLUGINS_NEED_ACTIVATION[@]}")
    else
      ACTIVE_PLUGINS=$(wp_plugin_list --status=active --field=name 2>/dev/null || echo "")
    fi
  fi
fi

# Network-activate Composer plugins (multisite)
# NOTE: This may fail if composer install hasn't run yet - will be retried after composer install
if [ ${#COMPOSER_PLUGINS_TO_NETWORK_ACTIVATE[@]} -gt 0 ] && [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
  echo "Network-activating ${#COMPOSER_PLUGINS_TO_NETWORK_ACTIVATE[@]} Composer plugin(s)..."
  if ! run wp_network plugin activate "${COMPOSER_PLUGINS_TO_NETWORK_ACTIVATE[@]}"; then
    echo "Note: Some Composer plugins couldn't be network-activated yet - will retry after composer install"
    COMPOSER_PLUGINS_PENDING_NETWORK_ACTIVATION=("${COMPOSER_PLUGINS_TO_NETWORK_ACTIVATE[@]}")
  else
    PLUGINS_MODIFIED=true
  fi
fi

{{- if and .Values.wordpress.init.enabled .Values.wordpress.init.multiSites.enabled }}
{{- $allSites := list }}
{{- range .Values.wordpress.init.multiSites.sites }}
{{- $allSites = append $allSites .name }}
{{- end }}
# Process site-specific plugin activations
{{- range $site := $allSites }}
{{- $siteVar := $site | upper | replace "-" "_" }}
if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ] && [ ${#PLUGINS_SITE_ACTIVATE_{{ $siteVar }}[@]} -gt 0 ]; then
  echo "Activating ${#PLUGINS_SITE_ACTIVATE_{{ $siteVar }}[@]} plugin(s) on site {{ $site }}..."
  for PLUGIN in "${PLUGINS_SITE_ACTIVATE_{{ $siteVar }}[@]}"; do
    if run wp_site "{{ $site }}" plugin is-installed "$PLUGIN"; then
      if run wp_site "{{ $site }}" plugin is-active "$PLUGIN"; then
        [ "${DEBUG}" = "true" ] && echo "DEBUG: Plugin $PLUGIN already active on site {{ $site }}, skipping"
      else
        echo "Activating plugin $PLUGIN on site {{ $site }}..."
        run wp_site "{{ $site }}" plugin activate "$PLUGIN" || echo "Warning: Could not activate $PLUGIN on site {{ $site }}"
      fi
    else
      echo "Warning: Plugin $PLUGIN not installed, skipping activation on site {{ $site }}"
    fi
  done
fi
{{- end }}
{{- end }}

{{- if and (default true .Values.metrics.wordpress.autoupdate) (ne (include "metrics.wordpress.pluginname" .) "\"\"") }}
# Include metrics plugin in autoupdate batch
if [ -n "${WORDPRESS_METRICS}" ]; then
  PLUGINS_TO_AUTOUPDATE+=("${WORDPRESS_METRICS}")
fi
{{- end }}

# Batch enable auto-updates using shared helper function (full-replace: always runs to ensure correct file paths)
if [ ${#PLUGINS_TO_AUTOUPDATE[@]} -gt 0 ]; then
  enable_autoupdates "plugins" "${PLUGINS_TO_AUTOUPDATE[@]}"
fi
{{- end }}

{{- if and (not .Values.wordpress.plugins) (default true .Values.metrics.wordpress.autoupdate) (ne (include "metrics.wordpress.pluginname" .) "\"\"") }}
# Enable autoupdates for metrics plugin (no regular plugins configured)
if [ -n "${WORDPRESS_METRICS}" ]; then
  enable_autoupdates "plugins" "${WORDPRESS_METRICS}"
fi
{{- end }}

{{- if .Values.wordpress.pluginsPrune }}
# ============================================================================
# Plugin Pruning - Remove plugins not in the defined list
# ============================================================================

# Build comma-separated list of plugins to exclude from deletion
# Includes both regular plugins and slugs extracted from Composer packages
EXCLUDE_PLUGINS=""
COMPOSER_PACKAGES_TO_KEEP=()
COMPOSER_THEME_PACKAGES_TO_KEEP=()
{{- $excludeList := list }}
{{- if .Values.wordpress.plugins }}
{{- range $plugin := .Values.wordpress.plugins }}
{{- $name := $plugin.name | lower }}
{{- if and (contains "/" $name) (not (hasPrefix "http://" $name)) (not (hasPrefix "https://" $name)) }}
# Composer package: {{ $name }} -> slug: {{ $name | splitList "/" | last }}
COMPOSER_PACKAGES_TO_KEEP+=("{{ $name }}")
{{- $excludeList = append $excludeList ($name | splitList "/" | last) }}
{{- else }}
# Regular plugin: {{ $name }}
{{- $excludeList = append $excludeList $name }}
{{- end }}
{{- end }}
{{- end }}
{{- if $excludeList }}
EXCLUDE_PLUGINS="{{ $excludeList | join "," }}"
{{- end }}
{{- if .Values.wordpress.themes }}
{{- range .Values.wordpress.themes }}
{{- $name := .name | lower }}
{{- if and (contains "/" $name) (not (hasPrefix "http://" $name)) (not (hasPrefix "https://" $name)) }}
# Composer theme package: {{ $name }}
COMPOSER_THEME_PACKAGES_TO_KEEP+=("{{ $name }}")
{{- end }}
{{- end }}
{{- end }}
{{- if .Values.metrics.wordpress.enabled }}
{{- if .Values.metrics.wordpress.installPlugin }}
{{- if .Values.metrics.wordpress.pluginNameOverride }}
[ -n "$EXCLUDE_PLUGINS" ] && EXCLUDE_PLUGINS="${EXCLUDE_PLUGINS},{{ .Values.metrics.wordpress.pluginNameOverride }}" || EXCLUDE_PLUGINS="{{ .Values.metrics.wordpress.pluginNameOverride }}"
{{- else }}
[ -n "$EXCLUDE_PLUGINS" ] && EXCLUDE_PLUGINS="${EXCLUDE_PLUGINS},slymetrics" || EXCLUDE_PLUGINS="slymetrics"
{{- end }}
{{- end }}
{{- end }}

# Delete all plugins except those in the exclude list
# Only show output if plugins are actually deleted
if [ -n "$EXCLUDE_PLUGINS" ]; then
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Keeping plugins: $EXCLUDE_PLUGINS"
  PLUGINS_BEFORE=$(wp_plugin_list --field=name 2>/dev/null | wc -l || echo "0")
  wp plugin delete --all --exclude="$EXCLUDE_PLUGINS" >/dev/null 2>&1 || true
  PLUGINS_AFTER=$(wp_plugin_list --field=name 2>/dev/null | wc -l || echo "0")
  PRUNED_COUNT=$((PLUGINS_BEFORE - PLUGINS_AFTER))
  if [ "$PRUNED_COUNT" -gt 0 ]; then
    echo "Pruned $PRUNED_COUNT plugin(s)"
  fi
else
  PLUGINS_COUNT=$(wp_plugin_list --field=name 2>/dev/null | wc -l || echo "0")
  if [ "$PLUGINS_COUNT" -gt 0 ]; then
    echo "Pruning all $PLUGINS_COUNT plugin(s)..."
    wp plugin delete --all >/dev/null 2>&1 || true
  fi
fi
{{- end }}

# ============================================================================
# Final Plugin State Refresh
# ============================================================================
# Only refresh if we made modifications (performance optimization)
if [ "$PLUGINS_MODIFIED" = "true" ] || [ "$COMPOSER_PACKAGES_MODIFIED" = "true" ]; then
  echo "Refreshing plugin state after modifications..."
  INSTALLED_PLUGINS=$(wp_plugin_list --field=name 2>/dev/null || echo "")
  ACTIVE_PLUGINS=$(wp_plugin_list --status=active --field=name 2>/dev/null || echo "")
fi

# ============================================================================
# Redis/Valkey Object Cache Enable (redis-cache plugin)
# ============================================================================
# Applies to both Redis and Valkey backends via the same redis-cache plugin.
if wp plugin is-active redis-cache 2>/dev/null; then
  echo "Ensuring redis-cache object cache is enabled (Redis/Valkey)..."
  echo "redis-cache status before:"
  (wp_with_plugins redis status 2>&1 | grep -E "Status:|Client:|Drop-in:" || true)

  if ! wp_with_plugins redis update-dropin 2>/dev/null; then
    echo "Warning: redis-cache drop-in update failed"
  fi

  if ! wp_with_plugins redis enable 2>/dev/null; then
    echo "Warning: redis-cache enable failed"
  fi

  echo "redis-cache status after:"
  (wp_with_plugins redis status 2>&1 | grep -E "Status:|Client:|Drop-in:" || wp_with_plugins redis status 2>&1 || true)
fi

{{- if .Values.memcached.enabled }}
# ============================================================================
# Memcached Plugin Safety
# ============================================================================

MEMCACHED_PLUGIN_DROPIN="/var/www/html/wp-content/plugins/memcached/object-cache.php"
MEMCACHED_DROPIN_TARGET="/var/www/html/wp-content/object-cache.php"

if wp plugin is-active memcached 2>/dev/null; then
  echo "Deactivating memcached plugin (drop-in mode)..."
  wp plugin deactivate memcached 2>/dev/null || true
fi

if php -m | grep -qi '^memcached$'; then
  if [ -f "$MEMCACHED_PLUGIN_DROPIN" ]; then
    if [ ! -f "$MEMCACHED_DROPIN_TARGET" ] || ! cmp -s "$MEMCACHED_PLUGIN_DROPIN" "$MEMCACHED_DROPIN_TARGET"; then
      echo "Installing/updating Memcached object-cache drop-in..."
      cp "$MEMCACHED_PLUGIN_DROPIN" "$MEMCACHED_DROPIN_TARGET"
    fi
    if [ -f "$MEMCACHED_DROPIN_DISABLED" ] && [ -f "$MEMCACHED_DROPIN_TARGET" ]; then
      rm -f "$MEMCACHED_DROPIN_DISABLED"
    fi
  fi
else
  echo "Memcached extension missing in init; drop-in deferred to bootstrap."
fi
{{- end }}

# ============================================================================
# Theme Management
# ============================================================================
#
# Process Overview:
#   1. Detect package type (Composer vs WP repository vs URL)
#   2. Validate package names for security
#   3. Batch operations for performance
#   4. Install with retry logic for network resilience
#   5. Activate theme and configure auto-updates
#
# Performance Optimizations:
#   - Batch installation (wp theme install theme1 theme2 theme3)
#   - Cached theme lists (avoid repeated wp-cli calls)
#   - Skip already installed packages
#
# Error Handling:
#   - Validation errors: Skip package with warning
#   - Network errors: Retry with exponential backoff
#   - Composer errors: Exit with detailed message
#
echo "========================================="
echo "Processing themes..."
echo "========================================="

# Cache all theme data upfront (single query, then derive individual lists)
ALL_THEME_DATA=$(wp_theme_list --fields=name,status,auto_update --format=csv 2>/dev/null || echo "")
INSTALLED_THEMES=$(echo "$ALL_THEME_DATA" | tail -n +2 | cut -d',' -f1 || echo "")
ACTIVE_THEME=$(echo "$ALL_THEME_DATA" | grep ",active," | cut -d',' -f1 || echo "")
AUTOUPDATE_ENABLED_THEMES=$(echo "$ALL_THEME_DATA" | grep ",on$" | cut -d',' -f1 || echo "")

# Extract theme slug from theme name or URL
# Handles both direct theme names and .zip URLs
#
# Args:
#   $1 - Theme name or URL (e.g., "astra" or "https://example.com/theme.zip")
#
# Returns:
#   Theme slug (filename without .zip extension for URLs)
#
# Examples:
#   get_theme_slug "astra" -> "astra"
#   get_theme_slug "https://example.com/mytheme.zip" -> "mytheme"
get_theme_slug() {
  local theme_name="$1"
  if [[ "$theme_name" == *".zip" ]]; then
    basename "$theme_name" .zip
  else
    echo "$theme_name"
  fi
}


THEMES_TO_INSTALL=()
THEME_TO_ACTIVATE=""
THEMES_TO_AUTOUPDATE=()
THEMES_TO_NETWORK_ENABLE=()         # Multisite: networkEnable themes

COMPOSER_THEMES_TO_INSTALL=()
COMPOSER_THEME_TO_ACTIVATE=""
COMPOSER_THEME_PENDING_ACTIVATION=""
COMPOSER_THEMES_TO_UPDATE=()
COMPOSER_THEME_PACKAGE_TARGETS=()
COMPOSER_THEMES_TO_NETWORK_ENABLE=() # Multisite: networkEnable Composer themes
COMPOSER_THEMES_PENDING_NETWORK_ENABLE=() # Retry after composer install

{{- if and .Values.wordpress.init.enabled .Values.wordpress.init.multiSites.enabled }}
{{- $allSites := list }}
{{- range .Values.wordpress.init.multiSites.sites }}
{{- $allSites = append $allSites .name }}
{{- end }}
# Initialize site-specific theme activation arrays
{{- range $allSites }}
{{- $siteVar := . | upper | replace "-" "_" }}
THEMES_SITE_ACTIVATE_{{ $siteVar }}=()
{{- end }}
{{- end }}

{{- range .Values.wordpress.themes }}
THEME_NAME="{{ .name | lower }}"

# Validate package name before processing
if ! validate_package_name "$THEME_NAME"; then
  echo "Skipping invalid theme name: $THEME_NAME"
  continue
fi

# Check if it's a Composer package
if is_composer_package "$THEME_NAME"; then
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Detected Composer theme package: $THEME_NAME"
  COMPOSER_THEME_SLUG=$(get_composer_slug "$THEME_NAME")
  COMPOSER_THEME_PACKAGE_TARGETS+=("$THEME_NAME:$COMPOSER_THEME_SLUG")

  # Check if already installed via composer.json AND theme directory exists
  # Theme might be in composer.json but files deleted (e.g., after pruning)
  if composer_package_is_required "$THEME_NAME" /var/www/html/composer.json; then
    if [ -d "/var/www/html/${WP_THEMES_DIR}/${COMPOSER_THEME_SLUG}" ]; then
      [ "${DEBUG}" = "true" ] && echo "DEBUG: Composer theme package $THEME_NAME already installed"

      {{- if .autoupdate }}
      {{- if not .version }}
      # Auto-update only works for packages without fixed version AND already installed
      COMPOSER_THEMES_TO_UPDATE+=("$THEME_NAME")
      {{- else }}
      echo "Note: Auto-update skipped for theme $THEME_NAME (fixed version specified)"
      {{- end }}
      {{- end }}
    else
      # Package in composer.json but files missing - need to run composer install
      echo "Composer theme package $THEME_NAME in composer.json but theme directory missing - will reinstall"
      COMPOSER_PACKAGES_MODIFIED=true
    fi
  else
    {{- if .version }}
    COMPOSER_THEMES_TO_INSTALL+=("{{ .name | lower }}:{{ .version }}")
    {{- else }}
    COMPOSER_THEMES_TO_INSTALL+=("$THEME_NAME")
    {{- end }}
  fi

  {{- if and .networkEnable ($.Values.wordpress.init.multiSites.enabled) }}
  COMPOSER_THEMES_TO_NETWORK_ENABLE+=("$COMPOSER_THEME_SLUG")
  {{- end }}
  {{- if .activate }}
  COMPOSER_THEME_TO_ACTIVATE="$COMPOSER_THEME_SLUG"
  {{- end }}
  {{- if .sites }}
  # Build site-specific activation arrays for Composer theme
  {{- range .sites }}
  {{- $siteVar := . | upper | replace "-" "_" }}
  THEMES_SITE_ACTIVATE_{{ $siteVar }}+=("$COMPOSER_THEME_SLUG")
  {{- end }}
  {{- end }}
else
  {{- if .slug }}
  THEME_SLUG="{{ .slug | lower }}"
  {{- else }}
  THEME_SLUG=$(get_theme_slug "{{ .name | lower }}")
  {{- end }}

  if ! echo "$INSTALLED_THEMES" | grep -q "^${THEME_SLUG}$"; then
    {{- if .version }}
    THEMES_TO_INSTALL+=("{{ .name | lower }}:{{ .version }}")
    {{- else }}
    THEMES_TO_INSTALL+=("{{ .name | lower }}")
    {{- end }}
  else
    [ "${DEBUG}" = "true" ] && echo "DEBUG: Theme ${THEME_SLUG} already installed, skipping installation"
  fi
  {{- if and .networkEnable ($.Values.wordpress.init.multiSites.enabled) }}
  THEMES_TO_NETWORK_ENABLE+=("${THEME_SLUG}")
  {{- end }}
  {{- if .activate }}
  THEME_TO_ACTIVATE="${THEME_SLUG}"
  {{- end }}
  {{- if .sites }}
  {{- $themeName := .name | lower }}
  # Build site-specific activation arrays for {{ $themeName }}
  {{- range .sites }}
  {{- $siteVar := . | upper | replace "-" "_" }}
  THEMES_SITE_ACTIVATE_{{ $siteVar }}+=("${THEME_SLUG}")
  {{- end }}
  {{- end }}
  {{- if .autoupdate }}
  THEMES_TO_AUTOUPDATE+=("${THEME_SLUG}")
  {{- end }}
fi
{{- end }}

# Batch install themes
if [ ${#THEMES_TO_INSTALL[@]} -gt 0 ]; then
  echo "Installing ${#THEMES_TO_INSTALL[@]} theme(s)..."


  THEMES_SIMPLE=()
  THEMES_URLS=()
  THEMES_WITH_VERSION=()


  for theme_spec in "${THEMES_TO_INSTALL[@]}"; do
    if [[ "$theme_spec" == http://* ]] || [[ "$theme_spec" == https://* ]]; then
      THEMES_URLS+=("$theme_spec")
    elif [[ "$theme_spec" == *":"* ]]; then
      THEMES_WITH_VERSION+=("$theme_spec")
    else
      THEMES_SIMPLE+=("$theme_spec")
    fi
  done


  if [ ${#THEMES_SIMPLE[@]} -gt 0 ]; then
    if ! OUTPUT=$(retry_command wp theme install "${THEMES_SIMPLE[@]}" 2>&1); then
      echo "$OUTPUT" | grep -v "already installed"
      echo "Warning: Some themes failed to install"
    elif [ "${DEBUG}" = "true" ]; then
      echo "$OUTPUT"
    fi
  fi


  for theme_url in "${THEMES_URLS[@]}"; do
    echo "Installing theme from URL: $theme_url"
    if ! OUTPUT=$(retry_command wp theme install "$theme_url" 2>&1); then
      echo "$OUTPUT" | grep -v "already installed"
      echo "Warning: Failed to install theme from URL: $theme_url"
    elif [ "${DEBUG}" = "true" ]; then
      echo "$OUTPUT"
    fi
  done


  for theme_spec in "${THEMES_WITH_VERSION[@]}"; do
    THEME_NAME="${theme_spec%%:*}"
    THEME_VERSION="${theme_spec##*:}"
    echo "Installing theme ${THEME_NAME} version ${THEME_VERSION}..."
    if ! OUTPUT=$(retry_command wp theme install "${THEME_NAME}" --version="${THEME_VERSION}" 2>&1); then
      echo "$OUTPUT" | grep -v "already installed"
      echo "Warning: Failed to install theme: ${THEME_NAME}"
    elif [ "${DEBUG}" = "true" ]; then
      echo "$OUTPUT"
    fi
  done


  INSTALLED_THEMES=$(wp_theme_list --field=name 2>/dev/null || echo "")
  ACTIVE_THEME=$(wp_theme_list --status=active --field=name 2>/dev/null || echo "")
fi

# Install Composer themes (batch operation for performance)
if [ ${#COMPOSER_THEMES_TO_INSTALL[@]} -gt 0 ]; then
  echo "Installing ${#COMPOSER_THEMES_TO_INSTALL[@]} Composer theme(s)..."

  # Try batch install first (faster: single dependency resolution)
  all_packages="${COMPOSER_THEMES_TO_INSTALL[@]}"
  echo "Attempting batch install: $all_packages"

  if COMPOSER_OUTPUT=$(retry_command composer require $all_packages --no-interaction 2>&1); then
    echo "Batch install successful!"
  else
    # Fallback: install one by one to identify failing package
    echo "Batch install failed, falling back to individual installation..."
    for package_spec in "${COMPOSER_THEMES_TO_INSTALL[@]}"; do
      echo "Installing Composer theme package: $package_spec"
      if ! COMPOSER_OUTPUT=$(retry_command composer require "$package_spec" --no-interaction 2>&1); then
        echo "$COMPOSER_OUTPUT"
        handle_error "Error installing Composer theme package: $package_spec (failed after retries)"
      fi
    done
  fi

  echo "Composer themes installed!"
  COMPOSER_PACKAGES_MODIFIED=true
  INSTALLED_THEMES=$(wp_theme_list --field=name 2>/dev/null || echo "")
  ACTIVE_THEME=$(wp_theme_list --status=active --field=name 2>/dev/null || echo "")
fi

# Update Composer themes (auto-update for packages without fixed version)
if [ ${#COMPOSER_THEMES_TO_UPDATE[@]} -gt 0 ]; then
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Checking for Composer theme updates..."

  # Get list of outdated packages once (performance optimization)
  # Re-use existing OUTDATED_PACKAGES if already fetched, otherwise fetch now
  if [ -z "$OUTDATED_PACKAGES" ]; then
    OUTDATED_PACKAGES=$(composer outdated --direct --format=json 2>/dev/null | php -r '
      $json = json_decode(file_get_contents("php://stdin"), true);
      if (isset($json["installed"])) {
        foreach ($json["installed"] as $pkg) {
          echo $pkg["name"] . "\n";
        }
      }
    ' 2>/dev/null || echo "")
  fi

  THEMES_UPDATED=0
  for package in "${COMPOSER_THEMES_TO_UPDATE[@]}"; do
    # Check if package has an available update
    if echo "$OUTDATED_PACKAGES" | grep -q "^${package}$"; then
      echo "Updating Composer theme package: $package"
      # Capture output and only show on error, with retry logic
      if ! COMPOSER_OUTPUT=$(retry_command composer update "$package" --no-interaction 2>&1); then
        echo "$COMPOSER_OUTPUT"
        handle_error "Error updating Composer theme package: $package (failed after retries)"
      fi
      THEMES_UPDATED=$((THEMES_UPDATED + 1))
    else
      [ "${DEBUG}" = "true" ] && echo "DEBUG: Theme package $package is already up to date" >&2
    fi
  done

  if [ $THEMES_UPDATED -gt 0 ]; then
    echo "$THEMES_UPDATED Composer theme(s) updated!"
    COMPOSER_PACKAGES_MODIFIED=true
  fi
fi

# Link vendor-installed Composer library themes into wp-content/themes so
# WordPress can discover and activate them.
for package_target in "${COMPOSER_THEME_PACKAGE_TARGETS[@]}"; do
  PACKAGE_NAME="${package_target%%:*}"
  PACKAGE_SLUG="${package_target#*:}"
  TARGET_DIR="/var/www/html/${WP_THEMES_DIR}/${PACKAGE_SLUG}"
  if [ ! -d "$TARGET_DIR" ] && link_vendor_package_into_wordpress_dir "$PACKAGE_NAME" "$TARGET_DIR"; then
    echo "Linked Composer package into themes directory: $PACKAGE_NAME -> ${WP_THEMES_DIR}/${PACKAGE_SLUG}"
  fi
done

# Network-enable themes (multisite) - must run BEFORE per-site activation
if [ ${#THEMES_TO_NETWORK_ENABLE[@]} -gt 0 ] && [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
  echo "Network-enabling ${#THEMES_TO_NETWORK_ENABLE[@]} theme(s)..."
  for theme in "${THEMES_TO_NETWORK_ENABLE[@]}"; do
    # Check if already network-enabled
    NETWORK_THEMES=$(wp db query "SELECT meta_value FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='allowedthemes' AND site_id=1;" --skip-column-names 2>/dev/null || echo "")
    if echo "$NETWORK_THEMES" | grep -qF "\"$theme\""; then
      [ "${DEBUG}" = "true" ] && echo "DEBUG: Theme $theme already network-enabled"
    else
      echo "Network-enabling theme: $theme"
      run wp_network theme enable "$theme" || echo "Warning: Could not network-enable theme $theme"
    fi
  done
fi

# Network-enable Composer themes
if [ ${#COMPOSER_THEMES_TO_NETWORK_ENABLE[@]} -gt 0 ] && [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
  for theme in "${COMPOSER_THEMES_TO_NETWORK_ENABLE[@]}"; do
    if run wp theme is-installed "$theme"; then
      echo "Network-enabling Composer theme: $theme"
      run wp_network theme enable "$theme" || echo "Warning: Could not network-enable Composer theme $theme"
    else
      echo "Note: Composer theme $theme couldn't be network-enabled yet - will retry after composer install"
      COMPOSER_THEMES_PENDING_NETWORK_ENABLE+=("$theme")
    fi
  done
fi

{{- if and .Values.wordpress.init.enabled .Values.wordpress.init.multiSites.enabled }}
{{- $allSites := list }}
{{- range .Values.wordpress.init.multiSites.sites }}
{{- $allSites = append $allSites .name }}
{{- end }}
# Process site-specific theme activations
{{- range $site := $allSites }}
{{- $siteVar := $site | upper | replace "-" "_" }}
if [ "${WP_MULTISITE_ENABLED:-false}" = "true" ] && [ ${#THEMES_SITE_ACTIVATE_{{ $siteVar }}[@]} -gt 0 ]; then
  echo "Activating ${#THEMES_SITE_ACTIVATE_{{ $siteVar }}[@]} theme(s) on site {{ $site }}..."
  for THEME in "${THEMES_SITE_ACTIVATE_{{ $siteVar }}[@]}"; do
    if run wp theme is-installed "$THEME"; then
      CURRENT_THEME=$(wp_site "{{ $site }}" theme list --status=active --field=name 2>/dev/null | head -n1 || echo "")
      if [ "$CURRENT_THEME" = "$THEME" ]; then
        [ "${DEBUG}" = "true" ] && echo "DEBUG: Theme $THEME already active on site {{ $site }}, skipping"
      else
        echo "Activating theme $THEME on site {{ $site }}..."
        run wp_site "{{ $site }}" theme activate "$THEME" || echo "Warning: Could not activate $THEME on site {{ $site }}"
      fi
    else
      echo "Warning: Theme $THEME not installed, skipping activation on site {{ $site }}"
    fi
  done
fi
{{- end }}
{{- end }}

# Activate theme
if [ -n "$THEME_TO_ACTIVATE" ] && [ "$ACTIVE_THEME" != "$THEME_TO_ACTIVATE" ]; then
  echo "Activating theme: $THEME_TO_ACTIVATE"
  run wp theme activate "$THEME_TO_ACTIVATE"
fi

# Activate Composer theme
if [ -n "$COMPOSER_THEME_TO_ACTIVATE" ] && [ "$ACTIVE_THEME" != "$COMPOSER_THEME_TO_ACTIVATE" ]; then
  if run wp theme is-installed "$COMPOSER_THEME_TO_ACTIVATE"; then
    echo "Activating Composer theme: $COMPOSER_THEME_TO_ACTIVATE"
    run wp theme activate "$COMPOSER_THEME_TO_ACTIVATE"
    ACTIVE_THEME="$COMPOSER_THEME_TO_ACTIVATE"
  else
    echo "Note: Composer theme $COMPOSER_THEME_TO_ACTIVATE couldn't be activated yet - will retry after composer install"
    COMPOSER_THEME_PENDING_ACTIVATION="$COMPOSER_THEME_TO_ACTIVATE"
  fi
fi

# Batch enable auto-updates using shared helper function (full-replace: always runs to ensure correct state)
if [ ${#THEMES_TO_AUTOUPDATE[@]} -gt 0 ]; then
  enable_autoupdates "themes" "${THEMES_TO_AUTOUPDATE[@]}"
fi

{{- if .Values.wordpress.themesPrune }}
# ============================================================================
# Theme Pruning - Remove themes not in the defined list
# ============================================================================

# Build list of theme slugs to keep
THEMES_TO_KEEP=()
{{- if .Values.wordpress.themes }}
{{- range .Values.wordpress.themes }}
{{- $name := .name | lower }}
{{- if and (contains "/" $name) (not (hasPrefix "http://" $name)) (not (hasPrefix "https://" $name)) }}
# Composer theme package: {{ $name }}
# Extract theme slug from Composer package name (e.g., wpackagist-theme/astra -> astra)
THEME_SLUG=$(echo "{{ $name }}" | sed 's/.*\///')
THEMES_TO_KEEP+=("$THEME_SLUG")
{{- else }}
# Regular theme: {{ $name }}
THEME_SLUG=$(get_theme_slug "{{ $name }}")
THEMES_TO_KEEP+=("$THEME_SLUG")
{{- end }}
{{- end }}
{{- end }}

# Get all installed themes and active theme
INSTALLED_THEMES=$(wp_theme_list --field=name 2>/dev/null || echo "")
ACTIVE_THEME=$(wp_theme_list --status=active --field=name 2>/dev/null || echo "")

# Check if active theme should be pruned (will be handled before deletion)
ACTIVE_THEME_SHOULD_BE_PRUNED=false
if [ -n "$ACTIVE_THEME" ]; then
  ACTIVE_IN_KEEP_LIST=false
  for keep_theme in "${THEMES_TO_KEEP[@]}"; do
    if [ "$ACTIVE_THEME" = "$keep_theme" ]; then
      ACTIVE_IN_KEEP_LIST=true
      break
    fi
  done

  if [ "$ACTIVE_IN_KEEP_LIST" = false ]; then
    ACTIVE_THEME_SHOULD_BE_PRUNED=true

    # Try to activate a theme from the keep list
    FALLBACK_THEME=""
    for keep_theme in "${THEMES_TO_KEEP[@]}"; do
      if echo "$INSTALLED_THEMES" | grep -q "^${keep_theme}$"; then
        FALLBACK_THEME="$keep_theme"
        break
      fi
    done

    if [ -n "$FALLBACK_THEME" ]; then
      echo "Activating fallback theme: $FALLBACK_THEME (current active theme '$ACTIVE_THEME' is not in keep list)"
      if wp theme activate "$FALLBACK_THEME" 2>/dev/null; then
        echo "Successfully activated fallback theme: $FALLBACK_THEME"
        ACTIVE_THEME="$FALLBACK_THEME"
      else
        echo "ERROR: Failed to activate fallback theme. Active theme '$ACTIVE_THEME' will be kept to prevent site breakage." >&2
        ACTIVE_THEME_SHOULD_BE_PRUNED=false
      fi
    else
      echo "ERROR: Active theme '$ACTIVE_THEME' is not in keep list but no alternative theme available. Keeping it to prevent site breakage." >&2
      ACTIVE_THEME_SHOULD_BE_PRUNED=false
    fi
  fi
fi

# Build list of themes to delete (installed themes minus keep list minus active theme)
THEMES_TO_DELETE=()
for theme in $INSTALLED_THEMES; do
  # Safety: Never delete the active theme (even if it should be pruned but couldn't be switched)
  if [ "$theme" = "$ACTIVE_THEME" ]; then
    continue
  fi

  # Check if theme is in the keep list
  KEEP=false
  for keep_theme in "${THEMES_TO_KEEP[@]}"; do
    if [ "$theme" = "$keep_theme" ]; then
      KEEP=true
      break
    fi
  done

  if [ "$KEEP" = false ]; then
    THEMES_TO_DELETE+=("$theme")
  fi
done

# Delete all themes in one command for better performance
if [ ${#THEMES_TO_DELETE[@]} -gt 0 ]; then
  echo "Pruning ${#THEMES_TO_DELETE[@]} theme(s): ${THEMES_TO_DELETE[*]}"
  wp theme delete "${THEMES_TO_DELETE[@]}" 2>/dev/null || true
fi

# Remove Composer packages (plugins & themes) not in the keep lists
if [ -f /var/www/html/composer.json ]; then

  # Ensure Composer is available for pruning operations
  ensure_composer

  # Get all currently required packages from composer.json (excluding chart-managed Composer plugins)
  # Use PHP for reliable JSON parsing (performance: single process vs multiple sed/grep calls)
  if [ -f composer.json ]; then
    CURRENT_PACKAGES=$(php -r '
      $json = json_decode(file_get_contents("composer.json"), true);
      if (isset($json["require"])) {
        foreach ($json["require"] as $package => $version) {
          if ($package !== "composer/installers") {
            echo $package . "\n";
          }
        }
      }
    ' 2>/dev/null || echo "")
  else
    CURRENT_PACKAGES=""
  fi

  # Debug: Show what we're keeping
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Composer packages to keep: ${COMPOSER_PACKAGES_TO_KEEP[*]}" >&2
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Composer theme packages to keep: ${COMPOSER_THEME_PACKAGES_TO_KEEP[*]}" >&2
  [ "${DEBUG}" = "true" ] && echo "DEBUG: Current packages in composer.json: $CURRENT_PACKAGES" >&2

  # Get active theme (might be a Composer theme)
  ACTIVE_THEME=$(wp_theme_list --status=active --field=name 2>/dev/null || echo "")

  # Track packages that should be removed
  PACKAGES_TO_REMOVE=()
  ACTIVE_THEME_PACKAGE=""

  for package in $CURRENT_PACKAGES; do
    KEEP=false

    # Check if it's in the plugin keep list
    for keep_package in "${COMPOSER_PACKAGES_TO_KEEP[@]}"; do
      if [ "$package" = "$keep_package" ]; then
        KEEP=true
        break
      fi
    done

    # If not found in plugins, check theme keep list
    if [ "$KEEP" = false ]; then
      for keep_package in "${COMPOSER_THEME_PACKAGES_TO_KEEP[@]}"; do
        if [ "$package" = "$keep_package" ]; then
          KEEP=true
          break
        fi
      done
    fi

    # Check if this package is the active theme
    if [[ "$package" == wpackagist-theme/* ]]; then
      PACKAGE_SLUG="${package#wpackagist-theme/}"
      if [ "$PACKAGE_SLUG" = "$ACTIVE_THEME" ]; then
        ACTIVE_THEME_PACKAGE="$package"
        if [ "$KEEP" = false ]; then
          echo "WARNING: Active theme '$ACTIVE_THEME' is a Composer package ($package) not in the keep list"
        else
          # Active theme is in keep list, safe to continue
          continue
        fi
      fi
    fi

    if [ "$KEEP" = false ]; then
      PACKAGES_TO_REMOVE+=("$package")
    fi
  done

  # If active theme should be removed, try to activate fallback first
  # Note: This handles Composer theme packages that were already checked during WordPress theme pruning
  if [ -n "$ACTIVE_THEME_PACKAGE" ]; then
    # Only show message if we haven't already handled this theme above
    if [ "$ACTIVE_THEME_SHOULD_BE_PRUNED" = "false" ]; then
      # Theme was already processed above, just skip removal silently
      TEMP_PACKAGES=()
      for pkg in "${PACKAGES_TO_REMOVE[@]}"; do
        if [ "$pkg" != "$ACTIVE_THEME_PACKAGE" ]; then
          TEMP_PACKAGES+=("$pkg")
        fi
      done
      PACKAGES_TO_REMOVE=("${TEMP_PACKAGES[@]}")
    fi
    # If ACTIVE_THEME_SHOULD_BE_PRUNED=true, the theme was already switched above, so we can safely remove it
  fi

  # Remove all packages in one go
  if [ ${#PACKAGES_TO_REMOVE[@]} -gt 0 ]; then
    echo "========================================="
    echo "Pruning Composer packages..."
    echo "========================================="
    echo "Removing ${#PACKAGES_TO_REMOVE[@]} Composer package(s): ${PACKAGES_TO_REMOVE[*]}"
    for package in "${PACKAGES_TO_REMOVE[@]}"; do
      echo "Removing: $package"
      if ! COMPOSER_OUTPUT=$(composer remove "$package" --no-interaction --quiet 2>&1); then
        echo "$COMPOSER_OUTPUT"
        echo "Error removing Composer package: $package"
      fi
    done
    echo "Composer packages pruned successfully!"
  fi
fi
{{- end }}

# Install Composer theme dependencies after theme installation
# Plugin dependencies were already installed before theme processing
#
# This section handles:
#   - Running composer install for themes with their own composer.json
#   - Activating Composer plugins that couldn't be activated before
#
# Note: Main composer install and plugin dependencies were already done
# before theme installation to prevent loading errors (e.g., s3-uploads AWS SDK)
if [ "$COMPOSER_PACKAGES_MODIFIED" = "true" ] || [ ! -d /var/www/html/vendor ]; then

  # Ensure vendor directory exists (skip if already installed during plugin dependency phase)
  if [ "$COMPOSER_INSTALL_DONE" != "true" ] && [ ! -d /var/www/html/vendor ]; then
    echo "Vendor directory missing, running composer install..."
    if ! COMPOSER_OUTPUT=$(retry_command composer_run_filtered install --no-interaction 2>&1); then
      echo "$COMPOSER_OUTPUT"
      handle_error "Error installing Composer dependencies (failed after retries)"
    fi
  fi

  # Build list of Composer-installed theme slugs from the require list
  COMPOSER_THEME_SLUGS=""
  if [ -f composer.json ]; then
    COMPOSER_THEME_SLUGS=$(php -r '
      $json = json_decode(file_get_contents("composer.json"), true);
      if (isset($json["require"])) {
        foreach ($json["require"] as $package => $version) {
          // Only process theme packages
          if (strpos($package, "wpackagist-theme/") === 0 ||
              (strpos($package, "/") !== false && strpos($package, "theme") !== false)) {
            $slug = substr($package, strrpos($package, "/") + 1);
            echo $slug . "\n";
          }
        }
      }
    ' 2>/dev/null || echo "")
  fi

  # Install theme-specific Composer dependencies
  THEMES_WITH_DEPS=0
  for theme_dir in ${WP_THEMES_DIR}/*/; do
    if [ -f "${theme_dir}composer.json" ]; then
      THEME_NAME=$(basename "$theme_dir")

      # Only run composer install if this theme was installed via Composer
      if echo "$COMPOSER_THEME_SLUGS" | grep -q "^${THEME_NAME}$"; then
        [ $THEMES_WITH_DEPS -eq 0 ] && echo "Installing theme-specific Composer dependencies..."
        echo "Running composer install in theme: $THEME_NAME"
        cd "$theme_dir" || continue
        if COMPOSER_THEME_OUTPUT=$(retry_command composer_run_filtered install --no-dev --no-interaction --ignore-platform-reqs 2>&1); then
          echo "$COMPOSER_THEME_OUTPUT"
          echo "Successfully installed dependencies for theme: $THEME_NAME"
        else
          echo "$COMPOSER_THEME_OUTPUT"
          echo "Warning: Could not install dependencies for theme: $THEME_NAME"
        fi
        cd /var/www/html || handle_error "Cannot return to WordPress root directory"
        THEMES_WITH_DEPS=$((THEMES_WITH_DEPS + 1))
      else
        [ "${DEBUG}" = "true" ] && echo "DEBUG: Skipping $THEME_NAME - not a Composer-installed theme" >&2
      fi
    fi
  done

  # Activate Composer plugins that couldn't be activated before (dependencies were missing)
  if [ ${#COMPOSER_PLUGINS_PENDING_ACTIVATION[@]} -gt 0 ]; then
    echo "Activating Composer plugins after dependency installation..."
    ACTIVE_PLUGINS=$(wp_plugin_list --status=active --field=name 2>/dev/null || echo "")
    PLUGINS_STILL_NEED_ACTIVATION=()
    for plugin in "${COMPOSER_PLUGINS_PENDING_ACTIVATION[@]}"; do
      if ! echo "$ACTIVE_PLUGINS" | grep -q "^${plugin}$"; then
        PLUGINS_STILL_NEED_ACTIVATION+=("$plugin")
      fi
    done
    if [ ${#PLUGINS_STILL_NEED_ACTIVATION[@]} -gt 0 ]; then
      echo "Activating ${#PLUGINS_STILL_NEED_ACTIVATION[@]} Composer plugin(s)..."
      run wp plugin activate "${PLUGINS_STILL_NEED_ACTIVATION[@]}" || echo "Warning: Some plugins could not be activated"
    fi
  fi

  # Network-activate Composer plugins after dependency installation (multisite retry)
  if [ ${#COMPOSER_PLUGINS_PENDING_NETWORK_ACTIVATION[@]} -gt 0 ] && [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
    echo "Network-activating Composer plugins after dependency installation..."
    run wp_network plugin activate "${COMPOSER_PLUGINS_PENDING_NETWORK_ACTIVATION[@]}" || echo "Warning: Some Composer plugins could not be network-activated"
  fi

  # Network-enable Composer themes after dependency installation (multisite retry)
  if [ ${#COMPOSER_THEMES_PENDING_NETWORK_ENABLE[@]} -gt 0 ] && [ "${WP_MULTISITE_ENABLED:-false}" = "true" ]; then
    echo "Network-enabling Composer themes after dependency installation..."
    THEMES_STILL_NEED_NETWORK_ENABLE=()
    for theme in "${COMPOSER_THEMES_PENDING_NETWORK_ENABLE[@]}"; do
      if run wp theme is-installed "$theme"; then
        run wp_network theme enable "$theme" || echo "Warning: Could not network-enable Composer theme $theme"
      else
        THEMES_STILL_NEED_NETWORK_ENABLE+=("$theme")
      fi
    done

    if [ ${#THEMES_STILL_NEED_NETWORK_ENABLE[@]} -gt 0 ]; then
      echo "Warning: Some Composer themes are still not installed for network enable: ${THEMES_STILL_NEED_NETWORK_ENABLE[*]}"
    fi
  fi

  # Activate Composer theme after dependency installation
  if [ -n "$COMPOSER_THEME_PENDING_ACTIVATION" ]; then
    ACTIVE_THEME=$(wp_theme_list --status=active --field=name 2>/dev/null || echo "")
    if [ "$ACTIVE_THEME" != "$COMPOSER_THEME_PENDING_ACTIVATION" ]; then
      if run wp theme is-installed "$COMPOSER_THEME_PENDING_ACTIVATION"; then
        echo "Activating Composer theme after dependency installation: $COMPOSER_THEME_PENDING_ACTIVATION"
        run wp theme activate "$COMPOSER_THEME_PENDING_ACTIVATION" || echo "Warning: Could not activate Composer theme $COMPOSER_THEME_PENDING_ACTIVATION"
        ACTIVE_THEME=$(wp_theme_list --status=active --field=name 2>/dev/null || echo "")
      else
        echo "Warning: Composer theme $COMPOSER_THEME_PENDING_ACTIVATION is still not installed after composer install, skipping activation"
      fi
    fi
  fi
fi

# ============================================================================
# Custom Init Commands
# ============================================================================
{{ .Values.wordpress.init.customInitScript }}
{{- if .Values.wordpress.init.customInitConfigMap.name }}
echo "Running custom init commands from ConfigMap..."
if [ -f /tmp/custom-init-commands/{{ .Values.wordpress.init.customInitConfigMap.key | default "commands.sh" }} ]; then
  # Execute the custom commands script (already executable via defaultMode: 0755)
  /tmp/custom-init-commands/{{ .Values.wordpress.init.customInitConfigMap.key | default "commands.sh" }}
  echo "Custom init commands completed!"
else
  echo "Warning: Custom commands file not found in ConfigMap"
fi
{{- end }}


{{- $hasAdminAppPass := not (empty .Values.wordpress.init.applicationPassword) }}
{{- $hasUserAppPass := false }}
{{- range .Values.wordpress.users }}
{{- if .applicationPassword }}{{- $hasUserAppPass = true }}{{- end }}
{{- end }}
{{- if or $hasAdminAppPass $hasUserAppPass }}
# ============================================================================
# Application Password Setup
# ============================================================================
apk add --no-cache curl > /dev/null 2>&1 || true

KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null || echo "")
KUBE_NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null || echo {{ .Release.Namespace | quote }})
KUBE_API="https://kubernetes.default.svc"
KUBE_CA="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

ap_k8s_secret_exists() {
  curl -sf --cacert "$KUBE_CA" \
    -H "Authorization: Bearer $KUBE_TOKEN" \
    "${KUBE_API}/api/v1/namespaces/${KUBE_NS}/secrets/${1}" \
    > /dev/null 2>&1
}

ap_k8s_secret_write() {
  local name="$1" wp_user="$2" app_pass="$3" url="$4"
  local u_key="$5" p_key="$6" l_key="$7"
  local enc_user enc_pass enc_url payload http_status
  enc_user=$(printf '%s' "$wp_user"  | base64 | tr -d '\n')
  enc_pass=$(printf '%s' "$app_pass" | base64 | tr -d '\n')
  enc_url=$(printf '%s'  "$url"      | base64 | tr -d '\n')
  payload="{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"metadata\":{\"name\":\"${name}\",\"namespace\":\"${KUBE_NS}\"},\"data\":{\"${u_key}\":\"${enc_user}\",\"${p_key}\":\"${enc_pass}\",\"${l_key}\":\"${enc_url}\"}}"
  http_status=$(curl -s --cacert "$KUBE_CA" \
      -H "Authorization: Bearer $KUBE_TOKEN" \
      -H "Content-Type: application/json" \
      -X POST "${KUBE_API}/api/v1/namespaces/${KUBE_NS}/secrets" \
      -d "$payload" \
      -o /dev/null -w "%{http_code}")
  if [ "$http_status" = "201" ]; then
    return 0
  fi
  echo "POST returned ${http_status}, trying PUT..."
  http_status=$(curl -s --cacert "$KUBE_CA" \
      -H "Authorization: Bearer $KUBE_TOKEN" \
      -H "Content-Type: application/json" \
      -X PUT "${KUBE_API}/api/v1/namespaces/${KUBE_NS}/secrets/${name}" \
      -d "$payload" \
      -o /dev/null -w "%{http_code}")
  if [ "$http_status" = "200" ] || [ "$http_status" = "201" ]; then
    return 0
  fi
  echo "ERROR: Failed to write Secret '${name}' (HTTP ${http_status})"
  return 1
}

ap_k8s_secret_delete() {
  curl -sf --cacert "$KUBE_CA" \
    -H "Authorization: Bearer $KUBE_TOKEN" \
    -X DELETE "${KUBE_API}/api/v1/namespaces/${KUBE_NS}/secrets/${1}" \
    > /dev/null 2>&1 || true
}

create_app_password() {
  local wp_user="$1" pass_name="$2" secret_name="$3"
  local u_key="$4" p_key="$5" l_key="$6"
  echo "--- Application Password '${pass_name}' for user '${wp_user}' ---"

  local existing_uuid
  existing_uuid=$(wp user application-password list "$wp_user" --fields=name,uuid --format=json 2>/dev/null | \
    php -r "
      \$list = json_decode(file_get_contents('php://stdin'), true) ?: [];
      \$name = '${pass_name}';
      foreach (\$list as \$p) {
        if ((\$p['name'] ?? '') === \$name) { echo \$p['uuid']; exit; }
      }
    " 2>/dev/null || echo "")

  local secret_exists=false
  if ap_k8s_secret_exists "$secret_name"; then
    secret_exists=true
  fi

  if [ -n "$existing_uuid" ] && [ "$secret_exists" = "true" ]; then
    echo "Already configured — skipping."
    return 0
  fi

  if [ -n "$existing_uuid" ]; then
    echo "App password exists but Secret '${secret_name}' missing — recreating both..."
    wp user application-password delete "$wp_user" "$existing_uuid" 2>/dev/null || true
  fi

  if [ "$secret_exists" = "true" ]; then
    echo "Secret '${secret_name}' exists but WP app password missing — deleting stale Secret..."
    ap_k8s_secret_delete "$secret_name"
  fi

  local raw_pass wpcli_out
  wpcli_out=$(wp user application-password create "$wp_user" "$pass_name" --porcelain 2>&1)
  raw_pass=$(printf '%s' "$wpcli_out" | tr -d '\n ')

  if [ -z "$raw_pass" ]; then
    echo "ERROR: Failed to create application password for '${wp_user}'"
    echo "WP-CLI output: ${wpcli_out}"
    return 1
  fi

  echo "Created application password, writing to Secret '${secret_name}'..."
  ap_k8s_secret_write "$secret_name" "$wp_user" "$raw_pass" {{ include "wordpress.normalizedUrl" . | quote }} "$u_key" "$p_key" "$l_key"
  echo "Credentials stored in Secret '${secret_name}'."
}

{{- if .Values.wordpress.init.applicationPassword }}
{{- $ap := .Values.wordpress.init.applicationPassword }}
{{- $sn := $ap.outputSecret.name | default (printf "%s-token-admin" .Release.Name) }}
create_app_password \
  "$WP_ADMIN_USER" \
  {{ $ap.name | quote }} \
  {{ $sn | quote }} \
  {{ $ap.outputSecret.usernameKey | default "WP_USERNAME" | quote }} \
  {{ $ap.outputSecret.passwordKey | default "WP_APP_PASSWORD" | quote }} \
  {{ $ap.outputSecret.urlKey | default "WP_SITE_URL" | quote }}
{{- end }}
{{- range .Values.wordpress.users }}
{{- if .applicationPassword }}
{{- $ap := .applicationPassword }}
{{- $sn := $ap.outputSecret.name | default (printf "%s-token-%s" $.Release.Name .username) }}
create_app_password \
  {{ .username | quote }} \
  {{ $ap.name | quote }} \
  {{ $sn | quote }} \
  {{ $ap.outputSecret.usernameKey | default "WP_USERNAME" | quote }} \
  {{ $ap.outputSecret.passwordKey | default "WP_APP_PASSWORD" | quote }} \
  {{ $ap.outputSecret.urlKey | default "WP_SITE_URL" | quote }}
{{- end }}
{{- end }}
{{- end }}

# ============================================================================
# Final Rewrite Flush (single flush at the end)
# ============================================================================
if [ "$PLUGINS_MODIFIED" = "true" ] || [ "$COMPOSER_PACKAGES_MODIFIED" = "true" ]; then
  echo "Flushing rewrite rules after all changes..."
  run wp rewrite flush
fi

# ============================================================================
# Release Lock and Complete
# ============================================================================

# Print test summary if in TEST_MODE
test_summary

# Lock will be released automatically via trap on EXIT
echo "Init script completed successfully!"

# Explicitly exit with success code
exit 0{{- end -}}
