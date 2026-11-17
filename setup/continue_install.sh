#!/usr/bin/env bash
set -euo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$setup_dir/install_project_deps.sh"
bash "$setup_dir/build_workspaces.sh"
