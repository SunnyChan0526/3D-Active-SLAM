# ActiveSLAM (D435i handheld / UAV active semantic SLAM)

Monorepo containing the three catkin workspaces' sources plus setup/run scripts.

| Path | Catkin workspace (symlinked as `src/<name>`) |
|---|---|
| `src/kr_3d_active_ms_slam` | `~/active_ms_slam_ws` |
| `src/VINS-Fusion` | `~/vins_ws` |
| `src/realsense-ros` | `~/realsense_ws` |
| `setup/` | install / build / start / diagnose scripts and notes |

Upstream origins and base commits: see [UPSTREAM.md](UPSTREAM.md).
System overview and how to run: [docs/SYSTEM_OVERVIEW.md](docs/SYSTEM_OVERVIEW.md).
What to do next: [docs/NEXT_STEPS_ROADMAP.md](docs/NEXT_STEPS_ROADMAP.md).
Related papers and reading order: [docs/RELATED_PAPERS.md](docs/RELATED_PAPERS.md).
UAV active SLAM paper comparison (2021–2026): [docs/UAV_ACTIVE_SLAM_COMPARISON.md](docs/UAV_ACTIVE_SLAM_COMPARISON.md).
New-machine setup: see [new_ubuntu_migration.md](new_ubuntu_migration.md) and
[local_migration_status.txt](local_migration_status.txt).

## Fresh clone

```bash
git clone git@github.com:SunnyChan0526/3D-Active-SLAM.git ~/Desktop/ActiveSLAM_move2Laptop
cd ~/Desktop/ActiveSLAM_move2Laptop
./scripts/download_models.sh          # yolov8x-seg.pt (not stored in git)
mkdir -p ~/active_ms_slam_ws/src ~/vins_ws/src ~/realsense_ws/src
ln -s $PWD/src/kr_3d_active_ms_slam ~/active_ms_slam_ws/src/
ln -s $PWD/src/VINS-Fusion          ~/vins_ws/src/
ln -s $PWD/src/realsense-ros        ~/realsense_ws/src/
```

Not in git: model weights, rosbags, build/devel/logs, `setup/` run data and `*.log`.

Safety: keep `fsm/planning_only=true`; do not start UAV control nodes.
