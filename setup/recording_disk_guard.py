"""Disk guard for recording sessions; never deletes recordings."""
import argparse
import os
import shutil
import signal
import time

GIB = 1024 ** 3
START_BYTES = 6 * GIB
RESERVE_BYTES = 2 * GIB


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path')
    parser.add_argument('--watch-parent', type=int)
    args = parser.parse_args()
    if args.watch_parent is None:
        free = shutil.disk_usage(args.path).free
        if free < START_BYTES:
            print('【空間不足，尚未啟動】剩餘 {:.2f} GiB；至少需要 6 GiB（當輪錄製約 4 GiB，加上 2 GiB 保留空間）。'.format(free / GIB), flush=True)
            print('請先移存或清理舊紀錄，再重新執行。歷次 bag 不會自動刪除。', flush=True)
            return 1
        return 0
    while os.getppid() == args.watch_parent:
        free = shutil.disk_usage(args.path).free
        if free < RESERVE_BYTES:
            print('\a【空間過低，停止本輪】剩餘 {:.2f} GiB，低於 2 GiB；正在停止錄製與本輪節點，請勿繼續行走。'.format(free / GIB), flush=True)
            os.kill(args.watch_parent, signal.SIGTERM)
            return 1
        time.sleep(1)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
