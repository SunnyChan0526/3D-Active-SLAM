#!/usr/bin/env bash
set -eo pipefail
test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$test_dir/../source_active_slam.bash"
python - "$test_dir" <<'PY'
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

test_dir = Path(sys.argv[1])
build = Path.home() / 'active_ms_slam_ws/build/plan_manage/CMakeFiles/plan_manage.dir'
flags = (build / 'flags.make').read_text()
includes = shlex.split(next(line.split(' = ', 1)[1] for line in flags.splitlines()
                           if line.startswith('CXX_INCLUDES = ')))
link = shlex.split((build / 'link.txt').read_text())
libraries = link[next(i for i, value in enumerate(link) if value.startswith('-Wl,-rpath')):]
with tempfile.TemporaryDirectory(prefix='active_slam_yaw_test_') as temporary:
    executable = str(Path(temporary) / 'yaw_timing_regression')
    command = ['/usr/bin/c++', '-std=c++14', '-O0'] + includes + [
        str(test_dir / 'yaw_timing_regression.cpp'), '-o', executable,
        str(Path.home() / 'active_ms_slam_ws/devel/.private/plan_manage/lib/libplan_manage.so')
    ] + libraries
    subprocess.run(command, check=True)
    with (test_dir / 'yaw_timing_regression.log').open('w') as log:
        subprocess.run([executable], stdout=log, stderr=subprocess.STDOUT, check=True)
print('Yaw timing regression passed. Log:', test_dir / 'yaw_timing_regression.log')
PY
