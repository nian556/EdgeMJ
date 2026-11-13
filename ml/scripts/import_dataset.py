"""把網路上下載的 YOLO 格式資料集，轉成 EdgeMJ 的 42 類編號並合併進來。

用法（在專案根目錄執行）：
    python ml/scripts/import_dataset.py <下載的資料集資料夾> [選項]

例如：
    python ml/scripts/import_dataset.py ml/raw/makinoi --dry-run   # 先預覽對照表，不複製
    python ml/scripts/import_dataset.py ml/raw/makinoi             # 確認沒問題後正式匯入

支援兩種常見資料夾結構：
    Roboflow 匯出：  train/images, train/labels, valid/..., test/...
    Ultralytics：    images/train, labels/train, ...

選項：
    --name 前綴         匯入後的檔名前綴（預設用資料夾名稱），避免不同資料集檔名相撞
    --mapping 檔案.json  自訂對照，例如 {"1D": "1z", "back": null}（null 代表丟掉這個類別）
    --drop-unknown      對不到的類別直接丟掉（例如牌背 "back"），否則會停下來請你確認
    --dry-run           只印出對照表與統計，不複製任何檔案
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from collections import Counter
from pathlib import Path

from classes import ALIASES, CODES, DATASET_DIR, ZH, check_target_yaml, normalize, read_names

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SPLIT_ALIASES = {"train": "train", "valid": "val", "val": "val", "validation": "val", "test": "test"}


def find_splits(src: Path) -> list[tuple[str, Path, Path]]:
    """找出 (我們的 split 名稱, 圖片資料夾, 標註資料夾)。"""
    found = []
    for name, split in SPLIT_ALIASES.items():
        for img_dir, lbl_dir in (
            (src / name / "images", src / name / "labels"),  # Roboflow 結構
            (src / "images" / name, src / "labels" / name),  # Ultralytics 結構
        ):
            if img_dir.is_dir():
                found.append((split, img_dir, lbl_dir))
    return found


def to_box(coords: list[str]) -> str:
    """把座標統一成方框（中心x 中心y 寬 高）。
    有些資料集混用多邊形標註（x1 y1 x2 y2 ...），這裡取外框轉成方框。"""
    if len(coords) == 4:
        return " ".join(coords)
    xs = [float(v) for v in coords[0::2]]
    ys = [float(v) for v in coords[1::2]]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    return f"{(x0 + x1) / 2:.6f} {(y0 + y1) / 2:.6f} {x1 - x0:.6f} {y1 - y0:.6f}"


def build_mapping(source_names: list[str], custom: dict[str, str | None]) -> dict[int, int | None]:
    """來源類別編號 → 我們的類別編號（None 代表丟掉）。對不到的不放進結果。"""
    custom_norm = {normalize(k): v for k, v in custom.items()}
    mapping: dict[int, int | None] = {}
    for i, name in enumerate(source_names):
        key = normalize(name)
        if key in custom_norm:
            target = custom_norm[key]
            mapping[i] = None if target is None else CODES.index(target)
        elif key in ALIASES:
            mapping[i] = ALIASES[key]
    return mapping


def main() -> None:
    parser = argparse.ArgumentParser(description="匯入外部 YOLO 資料集到 EdgeMJ 格式")
    parser.add_argument("source", type=Path, help="下載的資料集資料夾（裡面要有 data.yaml）")
    parser.add_argument("--name", help="檔名前綴，預設為資料夾名稱")
    parser.add_argument("--mapping", type=Path, help="自訂對照 JSON 檔")
    parser.add_argument("--drop-unknown", action="store_true", help="丟掉對不到的類別")
    parser.add_argument("--dry-run", action="store_true", help="只預覽，不複製")
    args = parser.parse_args()

    check_target_yaml()
    src: Path = args.source.resolve()
    yaml_path = next((p for p in (src / "data.yaml", src / "dataset.yaml") if p.exists()), None)
    if yaml_path is None:
        sys.exit(f"錯誤：在 {src} 找不到 data.yaml")

    source_names = read_names(yaml_path)
    custom = json.loads(args.mapping.read_text(encoding="utf-8")) if args.mapping else {}
    bad = [v for v in custom.values() if v is not None and v not in CODES]
    if bad:
        sys.exit(f"錯誤：自訂對照裡有不存在的類別代碼 {bad}，可用的代碼見 data.yaml")
    mapping = build_mapping(source_names, custom)

    # ── 印出對照表讓使用者確認 ──
    print(f"\n類別對照表（來源 {len(source_names)} 類）：")
    unknown = []
    for i, name in enumerate(source_names):
        if i not in mapping:
            unknown.append(name)
            print(f"  {i:>3} {name:<20} → ？？ 對不到")
        elif mapping[i] is None:
            print(f"  {i:>3} {name:<20} → （丟掉）")
        else:
            t = mapping[i]
            print(f"  {i:>3} {name:<20} → {t:>2} {CODES[t]}（{ZH[t]}）")
    if unknown and not args.drop_unknown:
        sys.exit(
            f"\n有 {len(unknown)} 個類別對不到：{unknown}\n"
            "請用 --mapping 指定對照，或加上 --drop-unknown 丟掉它們。"
        )

    splits = find_splits(src)
    if not splits:
        sys.exit("錯誤：找不到 train/valid/test 資料夾")

    prefix = args.name or src.name
    stats: dict[str, Counter] = {}
    image_counts: Counter = Counter()
    dropped = 0

    for split, img_dir, lbl_dir in splits:
        counter = stats.setdefault(split, Counter())
        out_img = DATASET_DIR / "images" / split
        out_lbl = DATASET_DIR / "labels" / split
        for img in sorted(img_dir.iterdir()):
            if img.suffix.lower() not in IMAGE_EXTS:
                continue
            new_lines = []
            label = lbl_dir / f"{img.stem}.txt"
            if label.exists():
                for line in label.read_text(encoding="utf-8").splitlines():
                    parts = line.split()
                    if not parts:
                        continue
                    target = mapping.get(int(float(parts[0])))
                    if target is None:  # 丟掉的類別或對不到的類別
                        dropped += 1
                        continue
                    counter[target] += 1
                    new_lines.append(f"{target} {to_box(parts[1:])}")
            image_counts[split] += 1
            if not args.dry_run:
                out_img.mkdir(parents=True, exist_ok=True)
                out_lbl.mkdir(parents=True, exist_ok=True)
                shutil.copy2(img, out_img / f"{prefix}_{img.name}")
                # 沒有任何牌的圖片也保留（空標註檔 = 背景圖，可減少誤判）
                (out_lbl / f"{prefix}_{img.stem}.txt").write_text(
                    "\n".join(new_lines) + ("\n" if new_lines else ""), encoding="utf-8"
                )

    # ── 統計 ──
    print("\n圖片數量：" + "、".join(f"{s} {n} 張" for s, n in image_counts.items()))
    if dropped:
        print(f"丟掉的標註框：{dropped} 個")
    total = sum(stats.values(), Counter())
    missing = [f"{CODES[i]}（{ZH[i]}）" for i in range(len(CODES)) if total[i] == 0]
    if missing:
        print(f"這個資料集完全沒有的牌：{'、'.join(missing)}")
    print("（預覽模式，沒有複製任何檔案）" if args.dry_run else f"\n已匯入到 {DATASET_DIR}")


if __name__ == "__main__":
    main()
