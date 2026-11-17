#!/usr/bin/env bash
# Default to the confirmed legacy single-shot planning-only setup.
set -e
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$setup_dir/start_legacy_planning_only.sh" "$@"
