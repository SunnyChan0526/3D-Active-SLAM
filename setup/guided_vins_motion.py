"""Terminal prompts and timestamps for the isolated VINS translation test."""
import argparse
import json
import os
from pathlib import Path
import time

STAGES = [
    ("1/5　保持靜止", "不要移動或轉動相機，記住目前位置與朝向。", 10),
    ("2/5　現在慢慢向右平移", "用 10 秒向右移動約 15 公分；保持高度與朝向，不要刻意旋轉。", 10),
    ("3/5　在右側停住", "保持目前位置與朝向，不要移動。", 5),
    ("4/5　現在慢慢移回起點", "用 10 秒向左移回最初位置；保持高度與朝向。", 10),
    ("5/5　已回起點：保持靜止", "固定相機，不要遮住鏡頭，也不要放下；等待保存完成提示。", 20),
]

ROTATION_STAGES = [
    ("1/5　保持靜止", "固定相機，記住起始位置與朝向；這次只測水平轉向。", 10),
    ("2/5　現在慢慢向右轉約 15 度", "用 10 秒完成小角度水平轉向；盡量繞相機中心，不平移、不俯仰或側傾。", 10),
    ("3/5　保持轉後方向", "停在右轉約 15 度的位置，不要繼續轉動或移動。", 5),
    ("4/5　現在慢慢轉回原方向", "用 10 秒轉回起始朝向，保持相機中心位置與高度。", 10),
    ("5/5　已回原方向：保持靜止", "固定位置與朝向，不要遮鏡頭或放下相機；等待保存完成提示。", 20),
]

WALKING_STAGES = [
    ("1/3　站穩，保持相機靜止", "先不要走動；保持起始高度與朝向，對準有紋理的環境。", 10),
    ("2/3　現在開始直線慢走", "向前慢走約 1～2 公尺，保持相機朝前，不要轉身；到達終點可提前停住。", 20),
    ("3/3　現在停住，不要轉身", "站在終點固定相機 20 秒；不要走回起點、遮鏡頭或放下，等待保存完成提示。", 20),
]

CORNER_STAGES = [
    ("1/5　站穩，保持相機靜止", "固定相機 10 秒；等待直走提示，不要調整站位。", 10),
    ("2/5　現在直走 7.35 公尺", "用約 20 秒慢走到量好的轉角；到達後停住，等待右轉提示，不要提前轉彎。", 20),
    ("3/5　現在緩慢右轉 90 度", "站在轉角，用約 5 秒慢慢右轉 90 度；讓相機隨身體平順轉向，不要快速甩動。", 5),
    ("4/5　向前慢走，離牆約 1 公尺處停住", "保持右轉後的朝向，最多走約 5 公尺；接近牆壁、桌椅前就停下，盡量保留約 1 公尺距離。可以提前停住，剩餘倒數保持不動，不要為了走滿距離而靠近障礙物。", 20),
    ("5/5　終點保持靜止", "固定相機 20 秒；不要轉身、走回、遮鏡頭或放下，等待保存完成提示。", 20),
]


def banner(title, instruction):
    print("\a\n\033[1;93m" + "=" * 66, flush=True)
    print("  " + title + "\n", flush=True)
    print("  " + instruction, flush=True)
    print("=" * 66 + "\033[0m", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--watch-pid", action="append", type=int, default=[])
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--mode", choices=["translation", "rotation", "walking", "corner"], default="translation")
    parser.add_argument("--walking-distance-m", type=float)
    args = parser.parse_args()
    if not args.preview and args.output is None:
        parser.error("--output is required for a real test")
    records = []
    stages = {"translation": STAGES, "rotation": ROTATION_STAGES,
              "walking": WALKING_STAGES, "corner": CORNER_STAGES}[args.mode]
    if args.walking_distance_m is not None:
        if not 0 < args.walking_distance_m < 100:
            parser.error("walking distance must be between 0 and 100 metres")
        if args.mode == "walking":
            stages = list(stages)
            stages[1] = (stages[1][0],
                         "向前直線慢走量好的 {:g} 公尺，保持相機朝向，不要轉身；到終點立即停住，剩餘時間保持不動，不要為了走滿倒數而超過終點。".format(args.walking_distance_m),
                         stages[1][2])
    for title, instruction, seconds in stages:
        banner(title, instruction)
        if args.preview:
            print("  倒數 {} 秒（此為文字預覽，不執行測試）".format(seconds))
            continue
        record = {"mode": args.mode, "stage": title, "instruction": instruction,
                  "planned_seconds": seconds, "start_wall_time": time.time()}
        if args.mode == "corner":
            record["reference_route"] = {"first_leg_m": 7.35, "right_turn_degrees": 90,
                                         "second_leg_max_m": 5.0,
                                         "second_leg_actual_m": None,
                                         "target_obstacle_clearance_m": 1.0}
        if args.mode == "walking" and args.walking_distance_m is not None:
            record["reference_walk_distance_m"] = args.walking_distance_m
        records.append(record)
        args.output.write_text(json.dumps(records, ensure_ascii=False, indent=2))
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            for pid in args.watch_pid:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    raise SystemExit("\n測試程序已停止，請保留紀錄並回報；本輪未完成。")
            remaining = max(1, int(end - time.monotonic() + .999))
            print("  【{}】剩餘 {:2d} 秒     ".format(title, remaining), end="\r", flush=True)
            time.sleep(min(1, max(0, end - time.monotonic())))
        print()
        record["end_wall_time"] = time.time()
        args.output.write_text(json.dumps(records, ensure_ascii=False, indent=2))
    banner("動作測試結束，正在保存", "仍請保持相機不動，等候「已全部完成，可以放下相機」。")


if __name__ == "__main__":
    main()
