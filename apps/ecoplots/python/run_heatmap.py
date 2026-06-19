#!/usr/bin/env python3
"""
Run EcoQuant heatmap generation.

Usage:
    python run_heatmap.py [YYYY-MM-DD] [--prev-date YYYY-MM-DD]
"""
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import heatmap


def parse_args():
    cur_date = None
    prev_date = None
    args = sys.argv[1:]
    i = 0

    while i < len(args):
        arg = args[i]
        if arg == "--prev-date" and i + 1 < len(args):
            prev_date = args[i + 1]
            i += 2
        elif arg.startswith("--"):
            print(f"Unknown option: {arg}", file=sys.stderr)
            return None, None, 2
        else:
            cur_date = arg
            i += 1

    if cur_date is None:
        cur_date = datetime.now().strftime("%Y-%m-%d")

    return cur_date, prev_date, 0


def main():
    cur_date, prev_date, status = parse_args()
    if status != 0:
        return status

    print(f"Running heatmap generation for {cur_date}")
    print(f"Results dir: {heatmap.DATA_DIR}")
    print(f"Output dir: {heatmap.OUTPUT_DIR}")
    print(f"Previous date: {prev_date or 'auto-detect'}")

    outputs = heatmap.run_dashboard(cur_date=cur_date, prev_date_arg=prev_date)

    print("\n=== Generated heatmaps ===")
    for name, path in outputs.items():
        ok = bool(path) and os.path.exists(path)
        mark = "✓" if ok else "✗"
        print(f"{mark} {name:25s} -> {path}")
        if not ok:
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
