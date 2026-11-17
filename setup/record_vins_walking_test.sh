#!/usr/bin/env bash
set -e
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_TEST_MODE=walking
exec bash "$setup_dir/record_isolated_vins_test.sh"
