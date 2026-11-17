# ActiveSLAM (D435i handheld / UAV active semantic SLAM)

Monorepo containing the three catkin workspaces' sources plus setup/run scripts.

| Path | Catkin workspace (symlinked as `src/<name>`) |
|---|---|
| `src/kr_3d_active_ms_slam` | `~/active_ms_slam_ws` |
| `src/VINS-Fusion` | `~/vins_ws` |
| `src/realsense-ros` | `~/realsense_ws` |
| `setup/` | install / build / start / diagnose scripts and notes |

Upstream origins and base commits: see [UPSTREAM.md](UPSTREAM.md).
New-machine setup: see [new_ubuntu_migration.md](new_ubuntu_migration.md) and
[local_migration_status.txt](local_migration_status.txt).

## Fresh clone

```bash
git clone git@github.com:<user>/<repo>.git ~/Desktop/ActiveSLAM_move2Laptop
cd ~/Desktop/ActiveSLAM_move2Laptop
./scripts/download_models.sh          # yolov8x-seg.pt (not stored in git)
mkdir -p ~/active_ms_slam_ws/src ~/vins_ws/src ~/realsense_ws/src
ln -s $PWD/src/kr_3d_active_ms_slam ~/active_ms_slam_ws/src/
ln -s $PWD/src/VINS-Fusion          ~/vins_ws/src/
ln -s $PWD/src/realsense-ros        ~/realsense_ws/src/
```

Not in git: model weights, rosbags, build/devel/logs, `setup/` run data and `*.log`.

Safety: keep `fsm/planning_only=true`; do not start UAV control nodes.
