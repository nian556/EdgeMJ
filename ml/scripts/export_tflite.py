"""把訓練好的 .pt 模型轉成手機 App 用的 .tflite 格式，並驗證轉檔後的準確度。

用法（在專案根目錄執行）：
    ml\\.venv\\Scripts\\python ml/scripts/export_tflite.py            # 轉成 float32 與 float16
    ml\\.venv\\Scripts\\python ml/scripts/export_tflite.py --int8     # 另外產生 int8 量化版（更小更快）
    ml\\.venv\\Scripts\\python ml/scripts/export_tflite.py --no-val   # 不驗證準確度（比較快）

輸出到 ml/exports/：
    edgemj_float32.tflite   原始精度，檔案最大
    edgemj_float16.tflite   ★ 建議手機使用：檔案小一半、準確度幾乎不變
    edgemj_int8.tflite      （--int8）檔案最小、速度最快，但準確度可能下降
    labels.txt              類別名稱，一行一個，順序 = 類別編號

第一次轉檔時 Ultralytics 會自動安裝 TensorFlow 等轉檔工具（需要連網一次），之後就不用。
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ML_ROOT = Path(__file__).resolve().parents[1]
DATA_YAML = ML_ROOT / "datasets" / "mahjong" / "data.yaml"
DEFAULT_WEIGHTS = ML_ROOT / "runs" / "mahjong-yolov8n" / "weights" / "best.pt"
EXPORT_DIR = ML_ROOT / "exports"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")  # Windows 中文輸出不亂碼


def main() -> None:
    p = argparse.ArgumentParser(description="把 .pt 模型轉成 .tflite")
    p.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS, help="要轉檔的 .pt 模型")
    p.add_argument("--imgsz", type=int, default=640, help="輸入圖片大小，要和訓練時相同（預設 640）")
    p.add_argument("--int8", action="store_true", help="另外產生 int8 量化版")
    p.add_argument("--no-val", action="store_true", help="跳過轉檔後的準確度驗證")
    args = p.parse_args()

    from ultralytics import YOLO

    if not args.weights.exists():
        sys.exit(f"找不到模型：{args.weights}\n請先執行 train.py 訓練模型。")

    print(f"轉檔中：{args.weights}")
    model = YOLO(str(args.weights))
    # 注意：新版 Ultralytics 的 format="tflite"（LiteRT）只支援 Linux / macOS，
    # 所以改用 "saved_model"：它在 Windows 也能用，轉檔過程會一併產生 .tflite 檔。
    exported = Path(
        model.export(
            format="saved_model",
            imgsz=args.imgsz,
            int8=args.int8,
            data=str(DATA_YAML),  # int8 量化需要用部分訓練照片校正
            nms=False,            # NMS（去除重複框）留給 App 端處理，相容性最好
        )
    )

    # ── 把產生的 .tflite 整理到 ml/exports/ ──
    EXPORT_DIR.mkdir(exist_ok=True)
    results: list[Path] = []
    search_dir = exported if exported.is_dir() else exported.parent
    for kind in ("float32", "float16", "int8"):
        found = sorted(search_dir.rglob(f"*_{kind}.tflite"))
        if found:
            dst = EXPORT_DIR / f"edgemj_{kind}.tflite"
            shutil.copy2(found[0], dst)
            results.append(dst)
    if not results:
        sys.exit(f"轉檔失敗：在 {search_dir} 找不到任何 .tflite 檔")

    names = [model.names[i] for i in sorted(model.names)]
    (EXPORT_DIR / "labels.txt").write_text("\n".join(names) + "\n", encoding="utf-8")

    print("\n✓ 轉檔完成：")
    for r in results:
        print(f"  {r.name:<24} {r.stat().st_size / 1024 / 1024:6.1f} MB")
    print(f"  labels.txt               {len(names)} 個類別")

    if args.no_val:
        return

    # ── 驗證：.pt 與各個 .tflite 用同一套標準比較 ──
    # 註：不用 Ultralytics 內建的 val()，因為它會把 .tflite 的座標當成 0~1 比例再乘一次圖片大小，
    #     而這裡轉出的 .tflite 輸出本來就是像素座標，會導致分數錯誤地變成 0。
    from evaluate import evaluate_pt, evaluate_tflite

    print("\n驗證轉檔後的準確度（用 CPU 跑，需要幾分鐘）...")
    rows = [("原始模型 best.pt", evaluate_pt(args.weights, args.imgsz))]
    for r in results:
        rows.append((r.name, evaluate_tflite(r, args.imgsz)))

    print(f"\n{'模型':<24}{'精確率':>8}{'召回率':>8}{'F1':>8}")
    for name, (precision, recall, f1) in rows:
        print(f"  {name:<22}{precision * 100:7.1f}%{recall * 100:7.1f}%{f1 * 100:7.1f}%")
    print("（信心門檻 0.25、IoU 0.5；轉檔後的分數和原始模型接近就代表轉檔成功）")


if __name__ == "__main__":
    main()
