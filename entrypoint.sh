#!/bin/sh -l

# ███╗   ███╗███████╗████████╗████████╗██╗     ███████╗ ██████╗██╗
# ████╗ ████║██╔════╝╚══██╔══╝╚══██╔══╝██║     ██╔════╝██╔════╝██║
# ██╔████╔██║█████╗     ██║      ██║   ██║     █████╗  ██║     ██║
# ██║╚██╔╝██║██╔══╝     ██║      ██║   ██║     ██╔══╝  ██║     ██║
# ██║ ╚═╝ ██║███████╗   ██║      ██║   ███████╗███████╗╚██████╗██║
# ╚═╝     ╚═╝╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚══════╝ ╚═════╝╚═╝
# MettleCI DevOps for DataStage       (C) 2025-2026 Data Migrators

set -eu

# -----
# Setup
# -----
MCIX_BIN_DIR="/usr/share/mcix/bin"
MCIX_CMD="$MCIX_BIN_DIR/mcix"
PATH="$PATH:$MCIX_BIN_DIR"

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

# We'll store the real command status here so the trap can see it
MCIX_STATUS=0

# -----------------
# Utility functions
# -----------------

# Failure handling utility functions
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Validate mutually exclusive project/project-id arguments
choose_project() {
  if [ -n "$PARAM_PROJECT" ] && [ -n "$PARAM_PROJECT_ID" ]; then
    die "Provide either 'project' or 'project-id', not both."
  fi

  if [ -z "$PARAM_PROJECT" ] && [ -z "$PARAM_PROJECT_ID" ]; then
    die "You must provide either 'project' or 'project-id'."
  fi
}

# Normalise "true/false", "1/0", etc.
normalise_bool() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) echo 1 ;;
    0|false|FALSE|no|NO|off|OFF|"") echo 0 ;;
    *) die "Invalid boolean: $1" ;;
  esac
}

# -------------------
# Validate parameters
# -------------------

# Required arguments
require() {
  # $1 = var name, $2 = human label (for error)
  eval "v=\${$1-}"
  if [ -z "$v" ]; then
    die "Missing required input: $2"
  fi
}

require PARAM_API_KEY "api-key"
require PARAM_URL "url"
require PARAM_USER "user"
require PARAM_ASSETS "assets"

# ------------------------
# Build command to execute
# ------------------------

# Start argv
set -- "$MCIX_CMD" datastage import

# Core flags
set -- "$@" -api-key "$PARAM_API_KEY"
set -- "$@" -url "$PARAM_URL"
set -- "$@" -user "$PARAM_USER"
set -- "$@" -assets "$PARAM_ASSETS"

# Mutually exclusive project / project-id handling (safe with set -u)
PROJECT="${PARAM_PROJECT:-}"
PROJECT_ID="${PARAM_PROJECT_ID:-}"
choose_project
[ -n "$PROJECT" ]    && set -- "$@" -project "$PROJECT"
[ -n "$PROJECT_ID" ] && set -- "$@" -project-id "$PROJECT_ID"

# Optional scalar flags
# None in this action

# Optional boolean flags (with parameter variation handling)
if [ "$(normalise_bool "${PARAM_INCLUDE_JOB_IN_TEST_NAME:-0}")" -eq 1 ]; then
  set -- "$@" -include-job-in-test-name
fi

# ------------
# Step summary
# ------------
write_step_summary() {
  rc=$1

  status_emoji="✅"
  status_title="Success"
  [ "$rc" -ne 0 ] && status_emoji="❌" && status_title="Failure"

  project_display="${PROJECT:-<none>}"
  [ -n "${PROJECT_ID:-}" ] && project_display="${project_display} (ID: ${PROJECT_ID})"

  {
    cat <<EOF
### ${status_emoji} MCIX DataStage Import – ${status_title}

| Property    | Value                          |
|------------|---------------------------------|
| **Project**  | \`${project_display}\`        |
| **Assets**   | \`${PARAM_ASSETS:-<none>}\`   |
EOF

    if [ -n "${CMD_OUTPUT:-}" ]; then
      #printf '\n### MettleCI Command Output\n\n'
      #echo '```text'
      #printf '%s\n' "$CMD_OUTPUT" 
      #echo '```'
      #echo

      echo '<details>'
      echo '<summary>Imported assets</summary>'
      echo
      echo '| Asset | Type | Status |' >>"$GITHUB_STEP_SUMMARY"
      echo '|-------|------|--------|' >>"$GITHUB_STEP_SUMMARY"

      printf '%s\n' "$CMD_OUTPUT" | awk '
        BEGIN { in_assets = 0 }

        /^Deploying project containing/ {
          in_assets = 1
          next
        }

        in_assets && /^Import report\(s\):/ {
          exit
        }

        in_assets && /^[[:space:]]*\*/ {
          line = $0

          # strip leading "* Import "
          sub(/^[[:space:]]*\*[[:space:]]*Import[[:space:]]+/, "", line)

          asset_type = line
          status = ""

          # extract status: "... - STATUS"
          if (match(asset_type, /[[:space:]]-[[:space:]]([A-Z_]+)$/)) {
            status = substr(asset_type, RSTART + 3, RLENGTH - 3)
            asset_type = substr(asset_type, 1, RSTART - 1)
            sub(/[[:space:]]*$/, "", asset_type)
          }

          asset = asset_type
          type  = ""

          # extract type in parentheses
          if (match(asset_type, /\(([^()]*)\)[[:space:]]*$/)) {
            type  = substr(asset_type, RSTART + 1, RLENGTH - 2)
            asset = substr(asset_type, 1, RSTART - 1)
            
            # Trim whitespace
            sub(/[[:space:]]*$/, "", asset)

            # 🔥 NEW FIX: Remove any leading "(" from type
            sub(/^[[:space:]]*\(/, "", type)

            # Trim whitespace again
            sub(/^[[:space:]]+/, "", type)
            sub(/[[:space:]]+$/, "", type)
          }

          printf("| %s | %s | %s |\n", asset, type, status)
        }
      '

      echo
      echo '</details>'
    fi
  } >>"$GITHUB_STEP_SUMMARY"
}

# ---------
# Exit trap
# ---------
write_return_code_and_summary() {
  # Prefer MCIX_STATUS if set; fall back to $?
  rc=${MCIX_STATUS:-$?}

  echo "return-code=$rc" >>"$GITHUB_OUTPUT"

  [ -z "${GITHUB_STEP_SUMMARY:-}" ] && return

  write_step_summary "$rc"
}
trap write_return_code_and_summary EXIT

# -------
# Execute
# -------
echo "Executing: $*"

# Check the repository has been checked out
if [ ! -e "/github/workspace/.git" ] && [ ! -e "/github/workspace/$PARAM_ASSETS" ]; then
  die "Repo contents not found in /github/workspace. Did you forget to run actions/checkout@v4 before this action?"
fi

# Run the command, capture its output and status, but don't let `set -e` kill us.
set +e
CMD_OUTPUT="$("$@" 2>&1)"
MCIX_STATUS=$?
set -e

# Echo original command output into the job logs
printf '%s\n' "$CMD_OUTPUT"

# Let the trap handle outputs & summary using MCIX_STATUS
exit "$MCIX_STATUS"
