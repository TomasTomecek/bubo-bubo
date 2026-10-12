#!/bin/bash
# Exports the last sync-configuration run status to a Prometheus textfile
# for node_exporter's textfile collector.
#
# Installed by the sync-configuration ansible role (do not edit by hand).
# Run by sync-configuration-export.service (system unit, root).
#
# Reads {{ ansible_facts['user_home'] }}/.local/state/sync-configuration/last-run
# ("<epoch> <status>", status = success|skipped|failure, written by the
# user-level sync-configuration.service).
#
# Metrics:
#   sync_configuration_last_run_success            1 if the last run succeeded
#   sync_configuration_last_run_skipped            1 if the last run was skipped (dirty repo)
#   sync_configuration_last_run_timestamp_seconds  unix time of the last run
set -euo pipefail

STATE_FILE="{{ ansible_facts['user_home'] }}/.local/state/sync-configuration/last-run"
OUT_DIR=/var/lib/node_exporter/textfile_collector
OUT="$OUT_DIR/sync-configuration.prom"
TMP="$OUT.tmp.$$"

ts=0
status=""
if [ -f "$STATE_FILE" ]; then
  read -r ts status < "$STATE_FILE" || true
fi
case "$ts" in
  ''|*[!0-9]*) ts=0 ;;
esac

success=0
skipped=0
case "$status" in
  success) success=1 ;;
  skipped) skipped=1 ;;
esac

{
  echo "# HELP sync_configuration_last_run_success 1 if the last sync-configuration run succeeded"
  echo "# TYPE sync_configuration_last_run_success gauge"
  echo "sync_configuration_last_run_success $success"
  echo "# HELP sync_configuration_last_run_skipped 1 if the last sync-configuration run was skipped (dirty repo)"
  echo "# TYPE sync_configuration_last_run_skipped gauge"
  echo "sync_configuration_last_run_skipped $skipped"
  echo "# HELP sync_configuration_last_run_timestamp_seconds Unix timestamp of the last sync-configuration run"
  echo "# TYPE sync_configuration_last_run_timestamp_seconds gauge"
  echo "sync_configuration_last_run_timestamp_seconds $ts"
} > "$TMP"
mv "$TMP" "$OUT"
