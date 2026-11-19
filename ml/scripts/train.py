"""用 Ultralytics YOLOv8n 訓練麻將辨識模型（可離線、自動使用 GPU）。

用法（在專案根目錄執行，使用 ml/.venv 裡的 Python）：
    ml\\.venv\\Scripts\\python ml/scripts/train.py                 # 預設設定開始訓練
    ml\\.venv\\Scripts\\python ml/scripts/train.py --epochs 3      # 先跑 3 輪試試看
    ml\\.venv\\Scripts\\python ml/scripts/train.py --resume        # 中斷後從上次進度繼續

訓練結果會放在 ml/runs/<名稱>/，最好的模型是 weights/best.pt。

離線說明：
    第一次需要的檔案（預訓練權重 yolov8n.pt、畫圖用字型）已在安裝時下載好，
    之後訓練完全不用連網。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ML_ROOT = Path(__file__).resolve().parents[1]
DATA_YAML = ML_ROOT / "datasets" / "mahjong" / "data.yaml"
WEIGHTS_DIR = ML_ROOT / "weights"
RUNS_DIR = ML_ROOT / "runs"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")  # Windows 中文輸出不亂碼


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="訓練 EdgeMJ 麻將辨識模型")
    p.add_argument("--data", default=str(DATA_YAML), help="資料集設定檔（預設 ml/datasets/mahjong/data.yaml；補訓練用 mahjong_finetune.yaml）")
    p.add_argument("--model", default="yolov8n.pt", help="起始權重（預設 yolov8n.pt；補訓練時指定舊模型的 best.pt）")
    p.add_argument("--epochs", type=int, default=100, help="訓練幾輪（預設 100）")
    p.add_argument("--imgsz", type=int, default=640, help="訓練圖片大小（預設 640）")
    p.add_argument("--batch", type=int, default=16, help="每批幾張（顯示卡記憶體不足時調小；-1 = 自動）")
    p.add_argument("--patience", type=int, default=20, help="連續幾輪沒進步就提早結束（預設 20）")
    p.add_argument("--workers", type=int, default=4, help="讀取資料的執行緒數（預設 4）")
    p.add_argument("--name", default="mahjong-yolov8n", help="這次訓練的名稱（結果資料夾名）")
    p.add_argument("--device", default=None, help="指定裝置，例如 0（第一張顯示卡）或 cpu；預設用顯示卡，偵測不到就停止")
    p.add_argument("--resume", action="store_true", help="從上次中斷的地方繼續訓練")
    return p.parse_args()


def main() -> None:
    args = parse_args()

    import torch
    from ultralytics import YOLO

    # ── 選擇裝置：預設一定用 NVIDIA 顯示卡（CUDA），偵測不到就停止，不偷偷改用 CPU ──
    if args.device is None:
        if not torch.cuda.is_available():
            sys.exit(
                "錯誤：偵測不到可用的 NVIDIA 顯示卡（CUDA），已停止訓練。\n"
                "請確認顯示卡驅動正常，或安裝的是 GPU 版 PyTorch。\n"
                "若真的要用 CPU 訓練，請明確加上 --device cpu。"
            )
        args.device = 0
    if args.device == "cpu":
        print("⚠ 使用 CPU 訓練（會非常慢）。")
    else:
        print(f"✓ 使用 GPU（CUDA）：{torch.cuda.get_device_name(int(args.device))}")

    if args.resume:
        last = RUNS_DIR / args.name / "weights" / "last.pt"
        if not last.exists():
            sys.exit(f"找不到上次的進度：{last}")
        print(f"從上次進度繼續：{last}")
        YOLO(str(last)).train(resume=True)
        return

    data_yaml = Path(args.data)
    if not data_yaml.exists():
        sys.exit(f"找不到資料集設定檔：{data_yaml}")

    # 預訓練權重放在 ml/weights/，安裝時已下載；若不存在會自動下載一次
    WEIGHTS_DIR.mkdir(exist_ok=True)
    model_path = Path(args.model)
    if not model_path.is_absolute() and model_path.parent == Path("."):
        model_path = WEIGHTS_DIR / model_path.name
    model = YOLO(str(model_path))

    model.train(
        data=str(data_yaml),
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        patience=args.patience,
        workers=args.workers,
        device=args.device,
        project=str(RUNS_DIR),
        name=args.name,
        exist_ok=False,          # 同名時自動改名（mahjong-yolov8n2...），不覆蓋舊結果
        seed=0,
        # ── 資料增強：針對麻將牌調整 ──
        fliplr=0.0,              # 不左右翻轉：翻轉後的字（萬、東…）是鏡像字，現實中不存在
        flipud=0.0,              # 不上下翻轉（同上）
        degrees=10.0,            # 小角度旋轉，模擬牌沒擺正
        hsv_v=0.5,               # 亮度變化大一點，模擬不同燈光
    )

    best = Path(model.trainer.best)
    print("\n✓ 訓練完成！")
    print(f"  最好的模型：{best}")
    print(f"  訓練圖表與結果：{best.parents[1]}")
    print("  下一步：轉成手機用的 .tflite 格式")


if __name__ == "__main__":  # Windows 多執行緒讀資料時一定要有這行
    main()
