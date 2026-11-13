"""檢查資料集：每種牌各有幾個標註框、有沒有缺標註或格式錯誤。

用法（在專案根目錄執行）：
    python ml/scripts/check_dataset.py

建議每次匯入或自己標註完都跑一次，訓練前確認每種牌的數量是否足夠。
"""

from __future__ import annotations

from collections import Counter

from classes import CODES, DATASET_DIR, ZH, check_target_yaml

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SPLITS = ["train", "val", "test"]
MIN_RECOMMENDED = 100  # 每種牌在 train 至少建議的標註框數量


def main() -> None:
    check_target_yaml()
    counts = {s: Counter() for s in SPLITS}
    problems: list[str] = []

    print("各資料夾圖片數：")
    for split in SPLITS:
        img_dir = DATASET_DIR / "images" / split
        lbl_dir = DATASET_DIR / "labels" / split
        images = [p for p in img_dir.glob("*") if p.suffix.lower() in IMAGE_EXTS]
        no_label = 0
        for img in images:
            label = lbl_dir / f"{img.stem}.txt"
            if not label.exists():
                no_label += 1
                continue
            for n, line in enumerate(label.read_text(encoding="utf-8").splitlines(), 1):
                parts = line.split()
                if not parts:
                    continue
                try:
                    cls = int(parts[0])
                    coords = [float(x) for x in parts[1:]]
                except ValueError:
                    problems.append(f"{label.name} 第 {n} 行：格式錯誤")
                    continue
                if not 0 <= cls < len(CODES):
                    problems.append(f"{label.name} 第 {n} 行：類別編號 {cls} 超出範圍")
                elif len(coords) < 4 or any(not 0 <= c <= 1 for c in coords):
                    problems.append(f"{label.name} 第 {n} 行：座標必須是 0~1 之間的比例")
                else:
                    counts[split][cls] += 1
        note = f"（其中 {no_label} 張沒有標註檔，會被當成背景圖）" if no_label else ""
        print(f"  {split:<5} {len(images):>6} 張{note}")

    print(f"\n{'類別':<6}{'名稱':<6}{'train':>8}{'val':>8}{'test':>8}")
    low = []
    for i, code in enumerate(CODES):
        row = [counts[s][i] for s in SPLITS]
        mark = ""
        if row[0] < MIN_RECOMMENDED:
            mark = "  ← 偏少"
            low.append(ZH[i])
        print(f"{code:<8}{ZH[i]:<5}{row[0]:>8}{row[1]:>8}{row[2]:>8}{mark}")

    if problems:
        print(f"\n發現 {len(problems)} 個問題（只列前 20 個）：")
        for p in problems[:20]:
            print("  " + p)
    if low:
        print(f"\n有 {len(low)} 種牌在 train 少於 {MIN_RECOMMENDED} 個標註框，建議補拍或補標註。")
    if not problems and not low:
        print("\n✓ 資料集看起來沒問題，可以開始訓練！")


if __name__ == "__main__":
    main()
