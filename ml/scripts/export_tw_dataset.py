"""把自己拍的台灣牌照片（tw_mj/ + ml/raw/tw_mj_labels/）匯出成 YOLO 訓練用資料集。

用法（在專案根目錄執行）：
    ml\\.venv\\Scripts\\python ml/scripts/export_tw_dataset.py

會產生（原始照片和標註完全不會被改動）：
    ml/datasets/mahjong_tw/
        images/{train,val,test}/   照片複本（遮蔽區已塗灰）
        labels/{train,val,test}/   YOLO 格式標註
        data.yaml                  只看台灣牌（用來比較新舊模型）
        split.json                 每張照片分到哪一組、屬於哪個場景組
    ml/datasets/mahjong_finetune.yaml + finetune_train.txt + finetune_val.txt
        補訓練用：舊資料集 + 台灣牌（訓練組重複 N 次＝加權）

分組方式：
    照片依拍攝順序（檔名）每 GROUP_SIZE 張分成一組，整組一起分到 train/val/test，
    避免幾乎一樣的連拍照片同時出現在訓練和驗證，讓分數失真。

遮蔽區（cls = -1）：
    在訓練圖上塗成灰色，模型就不會把「沒標到的牌」當成背景學。
    塗完後再把「已標註的牌」從原圖貼回來，保證遮蔽區不會蓋到要學的牌。
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")  # Windows 中文輸出不亂碼

ML_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = ML_ROOT.parent
PHOTO_DIR = PROJECT_ROOT / "tw_mj"
LABEL_DIR = ML_ROOT / "raw" / "tw_mj_labels"
OUT_DIR = ML_ROOT / "datasets" / "mahjong_tw"
OLD_DIR = ML_ROOT / "datasets" / "mahjong"
DATASETS_DIR = ML_ROOT / "datasets"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from classes import CODES, ZH  # noqa: E402

GROUP_SIZE = 7
# 每 7 組中：第 2 組當驗證、第 5 組當測試，其餘訓練（約 70% / 15% / 15%）
VAL_SLOT, TEST_SLOT = 2, 5
MASK_COLOR = (114, 114, 114)  # 和 YOLO 補邊用的灰色相同


def split_of(group: int) -> str:
    slot = group % 7
    if slot == VAL_SLOT:
        return "val"
    if slot == TEST_SLOT:
        return "test"
    return "train"


def export_one(label_path: Path, split: str) -> tuple[int, int]:
    """匯出一張照片，回傳（牌框數, 遮蔽區數）。"""
    d = json.loads(label_path.read_text(encoding="utf-8"))
    src = PHOTO_DIR / d["image"]
    img = Image.open(src).convert("RGB")
    w, h = img.size

    tiles = [b for b in d["boxes"] if b["cls"] >= 0]
    masks = [b for b in d["boxes"] if b["cls"] < 0]

    def px(b: dict) -> tuple[int, int, int, int]:
        # 0~1 座標 → 像素座標，並限制在圖片範圍內
        x1 = max(0, min(w, round(min(b["x1"], b["x2"]) * w)))
        x2 = max(0, min(w, round(max(b["x1"], b["x2"]) * w)))
        y1 = max(0, min(h, round(min(b["y1"], b["y2"]) * h)))
        y2 = max(0, min(h, round(max(b["y1"], b["y2"]) * h)))
        return x1, y1, x2, y2

    if masks:
        out = img.copy()
        draw = ImageDraw.Draw(out)
        for b in masks:
            draw.rectangle(px(b), fill=MASK_COLOR)
        # 已標註的牌從原圖貼回來，避免被遮蔽區蓋掉
        for b in tiles:
            box = px(b)
            if box[2] > box[0] and box[3] > box[1]:
                out.paste(img.crop(box), box[:2])
        img = out

    stem = Path(d["image"]).stem
    img.save(OUT_DIR / "images" / split / f"{stem}.jpg", quality=95)

    lines = []
    for b in tiles:
        x1, y1, x2, y2 = px(b)
        if x2 - x1 < 2 or y2 - y1 < 2:
            continue  # 太小的框（誤點）略過
        cx, cy = (x1 + x2) / 2 / w, (y1 + y2) / 2 / h
        bw, bh = (x2 - x1) / w, (y2 - y1) / h
        lines.append(f"{b['cls']} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}")
    (OUT_DIR / "labels" / split / f"{stem}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(lines), len(masks)


def write_yaml(path: Path, train: str, val: str, test: str | None, comment: str) -> None:
    names = "\n".join(f"  {i}: {c}   # {ZH[i]}" for i, c in enumerate(CODES))
    test_line = f"test: {test}\n" if test else ""
    path.write_text(
        f"# {comment}\n"
        f"path: {path.parent.as_posix()}\n"
        f"train: {train}\nval: {val}\n{test_line}"
        f"nc: {len(CODES)}\nnames:\n{names}\n",
        encoding="utf-8",
    )


def main() -> None:
    p = argparse.ArgumentParser(description="匯出台灣牌訓練資料集")
    p.add_argument("--repeat", type=int, default=5, help="補訓練時台灣牌訓練組重複幾次（加權，預設 5）")
    args = p.parse_args()

    labels = sorted(LABEL_DIR.glob("*.json"))
    not_done = [f.name for f in labels if json.loads(f.read_text(encoding="utf-8"))["status"] != "done"]
    if not_done:
        sys.exit(f"還有 {len(not_done)} 張沒標完，先不匯出：{not_done[:5]}")

    # 重新建立輸出資料夾（只刪我們自己產生的 mahjong_tw）
    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    for s in ("train", "val", "test"):
        (OUT_DIR / "images" / s).mkdir(parents=True)
        (OUT_DIR / "labels" / s).mkdir(parents=True)

    split_info = {}
    stats = {s: Counter() for s in ("train", "val", "test")}
    cls_count = {s: Counter() for s in ("train", "val", "test")}
    for i, f in enumerate(labels):
        group = i // GROUP_SIZE
        split = split_of(group)
        n_tiles, n_masks = export_one(f, split)
        split_info[f.stem] = {"split": split, "group": group}
        stats[split]["images"] += 1
        stats[split]["tiles"] += n_tiles
        stats[split]["masks"] += n_masks
        for b in json.loads(f.read_text(encoding="utf-8"))["boxes"]:
            if b["cls"] >= 0:
                cls_count[split][b["cls"]] += 1

    (OUT_DIR / "split.json").write_text(json.dumps(split_info, ensure_ascii=False, indent=1), encoding="utf-8")
    write_yaml(OUT_DIR / "data.yaml", "images/train", "images/val", "images/test",
               "只有自己拍的台灣牌（用來比較新舊模型）")

    # 補訓練用清單：舊資料 + 台灣牌（訓練組重複 repeat 次）
    def imgs(folder: Path) -> list[str]:
        return [x.resolve().as_posix() for x in sorted(folder.glob("*.jpg"))]

    old_train, old_val = imgs(OLD_DIR / "images" / "train"), imgs(OLD_DIR / "images" / "val")
    tw_train, tw_val = imgs(OUT_DIR / "images" / "train"), imgs(OUT_DIR / "images" / "val")
    (DATASETS_DIR / "finetune_train.txt").write_text("\n".join(old_train + tw_train * args.repeat) + "\n", encoding="utf-8")
    (DATASETS_DIR / "finetune_val.txt").write_text("\n".join(old_val + tw_val) + "\n", encoding="utf-8")
    write_yaml(DATASETS_DIR / "mahjong_finetune.yaml", "finetune_train.txt", "finetune_val.txt",
               (OUT_DIR / "images" / "test").as_posix(), f"補訓練：舊資料集 + 台灣牌（訓練組 ×{args.repeat}）")

    # ── 印出統計 ──
    print("✓ 匯出完成：", OUT_DIR)
    for s in ("train", "val", "test"):
        st = stats[s]
        print(f"  {s:5s}：{st['images']:3d} 張照片、{st['tiles']:4d} 個牌框、{st['masks']:3d} 個遮蔽區")
    print(f"  補訓練：舊 {len(old_train)} 張 + 台灣牌 {len(tw_train)} 張 ×{args.repeat} = {len(old_train) + len(tw_train) * args.repeat} 張")
    missing = [ZH[c] for c in range(len(CODES)) if cls_count["train"][c] == 0]
    if missing:
        print("  ⚠ 訓練組完全沒有這些牌：", "、".join(missing))
    few_val = [ZH[c] for c in range(len(CODES)) if 0 < sum(cls_count[s][c] for s in cls_count) and cls_count["val"][c] + cls_count["test"][c] == 0]
    if few_val:
        print("  ℹ 驗證／測試組沒有這些牌（無法評估）：", "、".join(few_val))


if __name__ == "__main__":
    main()
