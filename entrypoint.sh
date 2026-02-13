#!/bin/sh -l

# ███╗   ███╗███████╗████████╗████████╗██╗     ███████╗ ██████╗██╗
# ████╗ ████║██╔════╝╚══██╔══╝╚══██╔══╝██║     ██╔════╝██╔════╝██║
# ██╔████╔██║█████╗     ██║      ██║   ██║     █████╗  ██║     ██║
# ██║╚██╔╝██║██╔══╝     ██║      ██║   ██║     ██╔══╝  ██║     ██║
# ██║ ╚═╝ ██║███████╗   ██║      ██║   ███████╗███████╗╚██████╗██║
# ╚═╝     ╚═╝╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚══════╝ ╚═════╝╚═╝
# MettleCI DevOps for DataStage       (C) 2025-2026 Data Migrators
#      _       _            _
#   __| | __ _| |_ __ _ ___| |_ __ _  __ _  ___
#  / _` |/ _` | __/ _` / __| __/ _` |/ _` |/ _ \
# | (_| | (_| | || (_| \__ \ || (_| | (_| |  __/
#  \__,_|\__,_|\__\__,_|___/\__\__,_|\__, |\___|
#                                    |___/
#  _                            _
# (_)_ __ ___  _ __   ___  _ __| |_
# | | '_ ` _ \| '_ \ / _ \| '__| __|
# | | | | | | | |_) | (_) | |  | |_
# |_|_| |_| |_| .__/ \___/|_|   \__|
#             |_|

set -eu

# -----
# Setup
# -----
export MCIX_BIN_DIR="/usr/share/mcix/bin"
export MCIX_CMD="mcix" 
export MCIX_JUNIT_CMD="/usr/share/mcix/mcix-junit-to-summary"
export MCIX_JUNIT_CMD_OPTIONS="--annotations"
# Make us immune to runner differences or potential base-image changes
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$MCIX_BIN_DIR"

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

# Ensure report file lands in the GitHub workspace so it survives container exit
resolve_report_path() {
  p="$1"

  # If already absolute, keep it
  case "$p" in
    /*) echo "$p" ;;
    *)
      # If relative, anchor it under workspace
      base="${GITHUB_WORKSPACE:-/github/workspace}"
      echo "${base}/${p#./}"
      ;;
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
  if [ -n "${junit_xml:-}" ] && [ -f "$junit_xml" ]; then
    if [ -x "$MCIX_JUNIT_CMD" ]; then
      "$MCIX_JUNIT_CMD" "$MCIX_JUNIT_CMD_OPTIONS" "$junit_xml" "$GITHUB_STEP_SUMMARY" || \
        echo "Warning: JUnit summarizer failed" >&2
    else
      echo "Warning: JUnit summarizer not found or not executable: $MCIX_JUNIT_CMD" >&2
    fi
  else
    echo "Warning: JUnit XML file not found: ${junit_xml:-<unset>}" >&2
  fi

  # Only attempt a summary if GitHub provided a writable summary file
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -w "$GITHUB_STEP_SUMMARY" ]; then
    "$MCIX_JUNIT_CMD" "$PARAM_REPORT" "MCIX DataStage Compile" >>"$GITHUB_STEP_SUMMARY" || true
  else
    # GITHUB_STEP_SUMMARY is not available/writable (?), so write a warning to stderr 
    # but don't fail the action since the main command did run and produce a report.
    echo "GitHub didn't provide a writable summary file; skipping junit summary generation" >&2
  fi
}

# ---------
# Exit trap
# ---------
write_return_code_and_summary() {
  # Prefer MCIX_STATUS if set; fall back to $?
  rc=${MCIX_STATUS:-$?}

  echo "return-code=$rc" >>"$GITHUB_OUTPUT"
  # Note that the generated junit file is used internally to generate a well
  # formatted GitHub summary, and is not intended as a user-consumable artifact

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
"$@" 2>&1
MCIX_STATUS=$?
set -e

# write outputs / summary based on MCIX_STATUS 
echo "return-code=$MCIX_STATUS" >> "$GITHUB_OUTPUT"

# Let the trap handle outputs & summary using MCIX_STATUS
exit "$MCIX_STATUS"
