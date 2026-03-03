#!/usr/bin/env bash
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

set -euo pipefail

# Import MettleCI GitHub Actions utility functions
. "/usr/share/mcix/common.sh"

# -----
# Setup
# -----
export MCIX_CMD_NAME="mcix datastage import"
export MCIX_BIN_DIR="/usr/share/mcix/bin"
export MCIX_LOG_DIR="/usr/share/mcix"
export MCIX_JUNIT_CMD="/usr/share/mcix/mcix-junit-to-summary"
export MCIX_JUNIT_CMD_OPTIONS="--annotations"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$MCIX_BIN_DIR"

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

# We'll store the real command status here so the trap can see it
MCIX_STATUS=0
# Populated if command output matches: "It has been logged (ID ...)"
MCIX_LOGGED_ERROR_ID=""

# -------------------
# Validate parameters
# -------------------

require PARAM_API_KEY "api-key"
require PARAM_URL "url"
require PARAM_USER "user"
require PARAM_ASSETS "assets"

# Normalize Assets path
ASSETS_PATH="$(resolve_workspace_path "${PARAM_ASSETS}")"

# No current PARAM_REPORT provided by import, but likely to change
# in future when we add junit output, so leaving this here as a reminder
#   require PARAM_REPORT "report"
#   REPORT_PATH="$(resolve_workspace_path "$PARAM_REPORT")"
#   mkdir -p "$(dirname "$REPORT_PATH")"
#   report_display="${REPORT_PATH#${GITHUB_WORKSPACE:-/github/workspace}/}"

# Temporary until 'mcix datastage import' provides us with a file
REPORT_PATH="$(pwd)/${GITHUB_RUN_ID}.xml"
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
# There are GOOD REASONS we don't use MCIX_CMD_NAME here.
set -- mcix datastage import

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

# Optional boolean flags
if [ "$(normalise_bool "${PARAM_INCLUDE_JOB_IN_TEST_NAME:-0}")" -eq 1 ]; then
  set -- "$@" -include-job-in-test-name
fi
 
# ------------
# Step summary
# ------------
write_step_summary() {
  # Surface "logged error ID" failures (if detected)
  if [ -n "${MCIX_LOGGED_ERROR_ID:-}" ] && \
     [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -w "$GITHUB_STEP_SUMMARY" ]; then
    {
      echo "**❌ Error:** There was an error logged while running the command."
      if [ -n "${MCIX_LOGGED_ERROR_ID:-}" ]; then
        # Capture the log entry and include it in the summary for visibility. 
        grep "(ID ${MCIX_LOGGED_ERROR_ID}" ${MCIX_LOG_DIR}/*.log | sed -n 's/.*(ID [^)]*): //p' \
          || echo "(Failed to extract log details for ID ${MCIX_LOGGED_ERROR_ID})"
      fi
    } >>"$GITHUB_STEP_SUMMARY"
    # Set a workflow error annotation for visibility. This will show up in the 'Annotations' tab 
    # but it won't fail the action on its own (since some errors are "log and continue".)
    gh_error "$MCIX_CMD_NAME" "There was an error logged during the execution of '$MCIX_CMD_NAME'"
  fi

  # Do we have a junit_xml variable pointing to a file?
  if [ -z "${REPORT_PATH:-}" ] || [ ! -f "$REPORT_PATH" ]; then
    gh_warn "JUnit XML file not found" "Path: ${REPORT_PATH:-<unset>}"

  # Do we have a junit-to-summary command available?
  elif [ -z "${MCIX_JUNIT_CMD:-}" ] || [ ! -x "$MCIX_JUNIT_CMD" ]; then
    gh_warn "JUnit summarizer not executable" "Command: ${MCIX_JUNIT_CMD:-<unset>}"

  # Did GitHub provide a writable summary file?
  elif [ -z "${GITHUB_STEP_SUMMARY:-}" ] || [ ! -w "$GITHUB_STEP_SUMMARY" ]; then
    gh_warn "GITHUB_STEP_SUMMARY not writable" "Skipping JUnit summary generation."

  else
    # Generate summary
    # mcix-junit-to-summary [--annotations] [--max-annotations N] <junit.xml> [title]
    echo "Publishing JUnit results to GitHub..."
    echo "$MCIX_JUNIT_CMD $MCIX_JUNIT_CMD_OPTIONS $REPORT_PATH \"$MCIX_CMD_NAME\""
    "$MCIX_JUNIT_CMD" \
      "$MCIX_JUNIT_CMD_OPTIONS" \
      "$REPORT_PATH" \
      "${MCIX_CMD_NAME}"  >> "$GITHUB_STEP_SUMMARY" || \
      gh_warn "JUnit summarizer for '${MCIX_CMD_NAME}' failed" "Continuing without failing the action."
  fi
}

# ---------
# Exit trap
# ---------
write_return_code_and_summary() {
  # Prefer MCIX_STATUS if set; fall back to $?
  rc=${MCIX_STATUS:-$?}

  echo "return-code=$rc" >> "$GITHUB_OUTPUT"
  # Note that the generated junit file is used internally to generate a well
  # formatted GitHub summary, and is not intended as a user-consumable artifact

  [ -z "${GITHUB_STEP_SUMMARY:-}" ] && return

  write_step_summary
}
# Combine summary/output writing + temp cleanup in a single EXIT trap.
trap write_return_code_and_summary EXIT

# -------
# Execute
# -------
# Check the repository has been checked out
if [ ! -e "/github/workspace/.git" ] && [ ! -e "$ASSETS_PATH" ]; then
  die "Repo contents not found in /github/workspace. Did you forget to run actions/checkout before this action?"
fi

# Prepare a file to capture output so we can detect "It has been logged (ID ...)" failures.
tmp_out="$(mktemp)"
cleanup() { rm -f "$tmp_out"; }

# Run the command, capture its output and status, but don't let `set -e` kill us.
set +e
"$@" 2>&1 | tee "$tmp_out"
MCIX_STATUS=$?
set -e

# If the known "logged error" signature occurred, stash details for the summary.
MCIX_LOGGED_ERROR_ID=""
if mcix_has_logged_error "$tmp_out"; then
  MCIX_LOGGED_ERROR_ID="$(mcix_extract_logged_error_id "$tmp_out")"
  # Treat logged errors as failures for the purpose of the step summary, even if the command itself didn't return a non-zero code.
  MCIX_STATUS=1
fi

# Let the trap handle outputs & summary using MCIX_STATUS
exit "$MCIX_STATUS"
