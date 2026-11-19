"""用現有模型替自己拍的台灣牌照片產生「標註草稿」，之後用 label_tw.py 修正。

用法（在專案根目錄執行）：
    ml\\.venv\\Scripts\\python ml/scripts/draft_tw_labels.py

已經存在的標註進度一律不會被覆蓋，所以重複執行也不會弄丟修正結果。
原始照片只會被讀取，不會被修改。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

from classes import CODES

ML_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IMAGES = ML_ROOT.parent / "tw_mj"
DEFAULT_WORK = ML_ROOT / "raw" / "tw_mj_labels"
DEFAULT_MODEL = ML_ROOT / "runs" / "mahjong-yolov8n" / "weights" / "best.pt"

# 太模糊、不適合拿來訓練的照片：預設標成「略過」，工具裡可以改回來
SKIP_NOTES = {"S__286351456_0": "照片偏模糊"}

# 目前模型特別容易認錯的牌（北常被認成南／西／發，所以這三種也要多看一眼）
WATCH_CODES = {"4z", "2z", "3z", "6z", "6m", "7m", "1s"} | {f"{n}f" for n in range(1, 9)}
WATCH_CLASSES = {CODES.index(code) for code in WATCH_CODES}
LOW_CONFIDENCE = 0.6
CONTAINED_RATIO = 0.6  # 小框有這個比例被大框蓋住，就當作同一張牌


def overlap_of_smaller(a: np.ndarray, b: np.ndarray) -> float:
    """交集面積 ÷ 較小框的面積。"""
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    if w <= 0 or h <= 0:
        return 0.0
    smaller = min((a[2] - a[0]) * (a[3] - a[1]), (b[2] - b[0]) * (b[3] - b[1]))
    return float(w * h / smaller) if smaller > 0 else 0.0


def build_boxes(xyxy: np.ndarray, conf: np.ndarray, cls: np.ndarray, width: int, height: int) -> list[dict]:
    """去掉同一張牌上的重複框，轉成 0~1 比例，並標記需要特別確認的框。"""
    kept: list[int] = []
    merged: set[int] = set()
    for i in np.argsort(-conf):  # 信心高的優先留下
        hit = next((k for k in kept if overlap_of_smaller(xyxy[i], xyxy[k]) > CONTAINED_RATIO), None)
        if hit is None:
            kept.append(int(i))
        else:
            merged.add(hit)

    boxes = []
    for i in kept:
        x1, y1, x2, y2 = xyxy[i]
        boxes.append({
            "cls": int(cls[i]),
            "x1": round(max(0.0, float(x1) / width), 5),
            "y1": round(max(0.0, float(y1) / height), 5),
            "x2": round(min(1.0, float(x2) / width), 5),
            "y2": round(min(1.0, float(y2) / height), 5),
            "conf": round(float(conf[i]), 3),
            "check": bool(conf[i] < LOW_CONFIDENCE or i in merged or int(cls[i]) in WATCH_CLASSES),
        })
    boxes.sort(key=lambda b: (round(b["y1"], 2), b["x1"]))
    return boxes


def main() -> None:
    p = argparse.ArgumentParser(description="產生台灣牌標註草稿")
    p.add_argument("--images", type=Path, default=DEFAULT_IMAGES, help="照片資料夾")
    p.add_argument("--work", type=Path, default=DEFAULT_WORK, help="標註進度資料夾")
    p.add_argument("--model", type=Path, default=DEFAULT_MODEL, help="用來產生草稿的模型")
    p.add_argument("--imgsz", type=int, default=640, help="辨識時的圖片大小")
    args = p.parse_args()

    import torch
    from ultralytics import YOLO

    if not torch.cuda.is_available():
        sys.exit("錯誤：偵測不到 NVIDIA 顯示卡（CUDA），已停止。")

    args.work.mkdir(parents=True, exist_ok=True)
    model = YOLO(str(args.model))
    files = sorted(args.images.glob("*.jpg"))
    created = kept_existing = total_boxes = total_check = 0

    for f in files:
        target = args.work / f"{f.stem}.json"
        if target.exists():  # 不覆蓋已有的進度
            kept_existing += 1
            continue
        with Image.open(f) as raw:
            image = ImageOps.exif_transpose(raw).convert("RGB")
        width, height = image.size
        result = model.predict(np.asarray(image)[:, :, ::-1], imgsz=args.imgsz, conf=0.25, iou=0.5,
                               agnostic_nms=True, device=0, verbose=False)[0]
        boxes = build_boxes(result.boxes.xyxy.cpu().numpy(), result.boxes.conf.cpu().numpy(),
                            result.boxes.cls.cpu().numpy().astype(int), width, height)
        note = SKIP_NOTES.get(f.stem, "")
        doc = {
            "image": f.name, "width": width, "height": height,
            "status": "skip" if note else "todo", "note": note,
            "priority": sum(b["check"] for b in boxes), "boxes": boxes,
        }
        tmp = target.with_suffix(".tmp")
        tmp.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
        os.replace(tmp, target)
        created += 1
        total_boxes += len(boxes)
        total_check += doc["priority"]

    print(f"新產生 {created} 張草稿，保留原有進度 {kept_existing} 張")
    print(f"共 {total_boxes} 個框，其中 {total_check} 個標記為需要特別確認")
    print(f"存放位置：{args.work}")


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    main()
