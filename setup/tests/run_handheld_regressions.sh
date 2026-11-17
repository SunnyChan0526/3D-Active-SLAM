#!/usr/bin/env bash
set -eo pipefail
test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$test_dir/../source_active_slam.bash"
python - "$test_dir" <<'PY'
from pathlib import Path
import shlex, subprocess, sys, tempfile
root = Path.home() / 'active_ms_slam_ws'
tests = Path(sys.argv[1])
base = root / 'build/exploration_manager/CMakeFiles'
flags = (base / 'exploration_manager.dir/flags.make').read_text()
includes = shlex.split(next(line.split(' = ',1)[1] for line in flags.splitlines()
                           if line.startswith('CXX_INCLUDES = ')))
link = shlex.split((base / 'exploration_node.dir/link.txt').read_text())
libs = link[next(i for i, value in enumerate(link) if value.startswith('-Wl,-rpath')):]
with tempfile.TemporaryDirectory(prefix='handheld_regression_') as temporary:
    for name in ('handheld_policy_regression', 'handheld_progress_regression', 'handheld_astar_regression'):
        executable = str(Path(temporary) / name)
        subprocess.run(['/usr/bin/c++','-std=c++14','-O0'] + includes +
                       [str(tests / (name+'.cpp')), '-o', executable] +
                       (libs if name != 'handheld_policy_regression' else []), check=True)
        with (tests / (name+'.log')).open('w') as log:
            subprocess.run([executable], stdout=log, stderr=subprocess.STDOUT, check=True)
        print(name + ': passed')
PY
python "$test_dir/handheld_cli_regression.py"
