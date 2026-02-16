#!/bin/sh
# Don't use -l here; we want to preserve the PATH and other env vars 
# as set in the base image, and not have it overridden by a login shell

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
#  _                            _     |___/
# (_)_ __ ___  _ __   ___  _ __| |_
# | | '_ ` _ \| '_ \ / _ \| '__| __|
# | | | | | | | |_) | (_) | |  | |_
# |_|_| |_| |_| .__/ \___/|_|   \__|
#             |_|

set -eu

# Import MettleCI GitHub Actions utility functions
. "/usr/share//mcix/common.sh"

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

# -------------------
# Validate parameters
# -------------------

require PARAM_API_KEY "api-key"
require PARAM_URL "url"
require PARAM_USER "user"
require PARAM_ASSETS "assets"
ASSETS_PATH="$(resolve_workspace_path "$PARAM_ASSETS")"

# No current PARAM_REPORT provided by import, but likely to change
# in future when we add junit output, so leaving this here as a reminder
#   require PARAM_REPORT "report"
#   REPORT_PATH="$(resolve_workspace_path "$PARAM_REPORT")"
#   mkdir -p "$(dirname "$REPORT_PATH")"
#   report_display="${REPORT_PATH#${GITHUB_WORKSPACE:-/github/workspace}/}"

# Temporary until 'mcix datastage import' provides us with a file
REPORT_PATH="$(pwd)/junit.xml"
cat <<'EOF' > "$REPORT_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="ExampleTestSuite" tests="1" failures="0" errors="0" skipped="0" time="0.001">
    <testcase classname="ExampleTestClass" name="testSomething" time="0.001"/>
</testsuite>
EOF

# ------------------------
# Build command to execute
# ------------------------

# Start argv
set -- "$MCIX_CMD" datastage import

# Core flags
set -- "$@" -api-key "$PARAM_API_KEY"
set -- "$@" -url "$PARAM_URL"
set -- "$@" -user "$PARAM_USER"
set -- "$@" -assets "$ASSETS_PATH"

# Mutually exclusive project / project-id handling (safe with set -u)
PROJECT="${PARAM_PROJECT:-}"
PROJECT_ID="${PARAM_PROJECT_ID:-}"
validate_project
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
  # Do we have a junit_xml variable pointing to a file?
  if [ -z "${REPORT_PATH:-}" ] || [ ! -f "$REPORT_PATH" ]; then
    gh_warn "JUnit XML file not found" "Path: ${REPORT_PATH:-<unset>}"

  # Do we have a junit-to-summary command available?
  elif [ -z "${MCIX_JUNIT_CMD:-}" ] || [ ! -x "$MCIX_JUNIT_CMD" ]; then
    gh_warn "JUnit summarizer not executable" "Command: ${MCIX_JUNIT_CMD:-<unset>}"

  # Did GitHub provide a writable summary file?
  elif [ -z "${GITHUB_STEP_SUMMARY:-}" ] || [ ! -w "$GITHUB_STEP_SUMMARY" ]; then
    gh_warn "GITHUB_STEP_SUMMARY not writable" "Skipping JUnit summary generation."

  # Generate summary
  else
    gh_notice "Generating step summary" "Running JUnit summarizer and appending to GITHUB_STEP_SUMMARY."

    # mcix-junit-to-summary [--annotations] [--max-annotations N] <junit.xml> [title]
    echo "Executing: $MCIX_JUNIT_CMD $MCIX_JUNIT_CMD_OPTIONS $REPORT_PATH \"MCIX DataStage Import\""
    "$MCIX_JUNIT_CMD" \
      "$MCIX_JUNIT_CMD_OPTIONS" \
      "$REPORT_PATH" \
      "MCIX DataStage Import" >> "$GITHUB_STEP_SUMMARY" || \
      gh_warn "JUnit summarizer failed" "Continuing without failing the action."
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

  write_step_summary
}
trap write_return_code_and_summary EXIT

# -------
# Execute
# -------
# Check the repository has been checked out
if [ ! -e "/github/workspace/.git" ] && [ ! -e "$ASSETS_PATH" ]; then
  die "Repo contents not found in /github/workspace. Did you forget to run actions/checkout before this action?"
fi

# Run the command, capture its output and status, but don't let `set -e` kill us.
set +e
"$@" 2>&1
MCIX_STATUS=$?
set -e

# Let the trap handle writing outputs & step summary
exit "$MCIX_STATUS"
