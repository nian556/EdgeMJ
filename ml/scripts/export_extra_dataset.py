"""把第二批照片（ml/raw/extra_mj + ml/raw/extra_mj_labels：Roboflow 30 張 + maj 8 張）
匯出成 YOLO 資料集，並產生「第二次補訓練」用的清單。

用法（在專案根目錄執行）：
    ml\\.venv\\Scripts\\python ml/scripts/export_extra_dataset.py

會產生（原始照片、標註、之前的資料集都不會被改動）：
    ml/datasets/mahjong_extra/images|labels/{train,val,test}/  第二批照片（遮蔽區已塗灰）
    ml/datasets/mahjong_extra/data.yaml                        只看第二批（比較新舊模型用）
    ml/datasets/mahjong_finetune2.yaml + finetune2_train.txt + finetune2_val.txt
        舊資料集 + 台灣牌（×5）+ 第二批（×5）；test 仍是自己拍的台灣牌測試組
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_tw_dataset as tw  # noqa: E402  沿用第一批的匯出方式（遮蔽區塗灰等）

ML_ROOT = tw.ML_ROOT
EXTRA_PHOTOS = ML_ROOT / "raw" / "extra_mj"
EXTRA_LABELS = ML_ROOT / "raw" / "extra_mj_labels"
EXTRA_OUT = ML_ROOT / "datasets" / "mahjong_extra"
GROUP_SIZE = 2  # 相鄰兩張（常是同場景連拍）一起分組，避免訓練和考試出現幾乎一樣的照片


def split_of(group: int) -> str:
    # 每 6 組：第 2 組驗證、第 5 組測試，其餘訓練
    return {2: "val", 5: "test"}.get(group % 6, "train")


def main() -> None:
    p = argparse.ArgumentParser(description="匯出第二批照片並產生第二次補訓練清單")
    p.add_argument("--repeat", type=int, default=5, help="第二批訓練組重複幾次（加權，預設 5）")
    args = p.parse_args()

    labels = sorted(EXTRA_LABELS.glob("*.json"))
    not_done = [f.name for f in labels if json.loads(f.read_text(encoding="utf-8"))["status"] != "done"]
    if not_done:
        sys.exit(f"還有 {len(not_done)} 張沒標完，先不匯出：{not_done[:5]}")

    # 讓 export_one 讀第二批照片、寫到第二批資料夾
    tw.PHOTO_DIR, tw.OUT_DIR = EXTRA_PHOTOS, EXTRA_OUT
    if EXTRA_OUT.exists():
        shutil.rmtree(EXTRA_OUT)  # 只刪這支程式自己產生的資料夾
    for s in ("train", "val", "test"):
        (EXTRA_OUT / "images" / s).mkdir(parents=True)
        (EXTRA_OUT / "labels" / s).mkdir(parents=True)

    split_info, stats = {}, {s: [0, 0] for s in ("train", "val", "test")}
    for i, f in enumerate(labels):
        split = split_of(i // GROUP_SIZE)
        n_tiles, _ = tw.export_one(f, split)
        split_info[f.stem] = split
        stats[split][0] += 1
        stats[split][1] += n_tiles
    (EXTRA_OUT / "split.json").write_text(json.dumps(split_info, ensure_ascii=False, indent=1), encoding="utf-8")
    tw.write_yaml(EXTRA_OUT / "data.yaml", "images/train", "images/val", "images/test", "只有第二批照片（比較新舊模型用）")

    def imgs(folder: Path) -> list[str]:
        return [x.resolve().as_posix() for x in sorted(folder.glob("*.jpg"))]

    # 第一批清單直接沿用（裡面已經是 舊資料 + 台灣牌×5），再加上第二批
    ds = tw.DATASETS_DIR
    old_train = (ds / "finetune_train.txt").read_text(encoding="utf-8").split()
    old_val = (ds / "finetune_val.txt").read_text(encoding="utf-8").split()
    ex_train, ex_val = imgs(EXTRA_OUT / "images" / "train"), imgs(EXTRA_OUT / "images" / "val")
    (ds / "finetune2_train.txt").write_text("\n".join(old_train + ex_train * args.repeat) + "\n", encoding="utf-8")
    (ds / "finetune2_val.txt").write_text("\n".join(old_val + ex_val) + "\n", encoding="utf-8")
    tw.write_yaml(ds / "mahjong_finetune2.yaml", "finetune2_train.txt", "finetune2_val.txt",
                  (tw.OUT_DIR.parent / "mahjong_tw" / "images" / "test").as_posix(),
                  f"第二次補訓練：舊資料 + 台灣牌×5 + 第二批×{args.repeat}")

    print("✓ 匯出完成：", EXTRA_OUT)
    for s, (n, t) in stats.items():
        print(f"  {s:5s}：{n:3d} 張照片、{t:4d} 個牌框")
    print(f"  訓練清單：{len(old_train)} + {len(ex_train)}×{args.repeat} = {len(old_train) + len(ex_train) * args.repeat} 張")


if __name__ == "__main__":
    main()
