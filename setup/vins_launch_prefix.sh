#!/usr/bin/env bash
set -eo pipefail
disable_emitter="$1"
shift
if [[ "$disable_emitter" == true ]]; then
  echo 'VIO diagnostic: disabling IR emitter before starting VINS.'
  rosrun dynamic_reconfigure dynparam set /camera/stereo_module emitter_enabled 0
fi
exec "$@"
