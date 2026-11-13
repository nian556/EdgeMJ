"""用驗證集比較 .pt 與 .tflite 模型的準確度（精確率、召回率、F1）。

.tflite 的解讀方式和之後 App 要做的完全一樣，可當成 App 端的參考實作：
    輸入：[1, 640, 640, 3] float32，RGB，數值 0~1，等比例縮放並以灰色 (114) 補邊（letterbox）
    輸出：[1, 46, 8400]，46 = 4 個座標 + 42 個類別分數
          座標是「像素」單位的 中心x、中心y、寬、高（以 640x640 輸入圖為基準）
    後處理：取每個候選框最高的類別分數 → 過濾低分 → NMS 去除重疊框
"""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
import torch
import torchvision

ML_ROOT = Path(__file__).resolve().parents[1]
VAL_IMAGES = ML_ROOT / "datasets" / "mahjong" / "images" / "val"
VAL_LABELS = ML_ROOT / "datasets" / "mahjong" / "labels" / "val"
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

CONF = 0.25  # 信心門檻
NMS_IOU = 0.7  # NMS 重疊門檻（與 Ultralytics 預設相同）
MATCH_IOU = 0.5  # 判斷「框對了」的重疊門檻


def letterbox(img: np.ndarray, size: int) -> tuple[np.ndarray, float, tuple[int, int]]:
    """等比例縮放到 size x size，不足的地方補灰色。回傳 (圖片, 縮放比例, (左補邊, 上補邊))。"""
    h, w = img.shape[:2]
    r = min(size / h, size / w)
    nh, nw = round(h * r), round(w * r)
    top, left = (size - nh) // 2, (size - nw) // 2
    out = np.full((size, size, 3), 114, dtype=np.uint8)
    out[top : top + nh, left : left + nw] = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LINEAR)
    return out, r, (left, top)


def decode(output: np.ndarray, ratio: float, pad: tuple[int, int]) -> np.ndarray:
    """把 [46, 8400] 原始輸出轉成 [N, 6]：x1, y1, x2, y2（原圖像素）, 分數, 類別。"""
    boxes, scores = output[:4].T, output[4:].T
    cls = scores.argmax(1)
    conf = scores.max(1)
    keep = conf > CONF
    boxes, cls, conf = boxes[keep], cls[keep], conf[keep]
    xyxy = np.stack(
        [boxes[:, 0] - boxes[:, 2] / 2, boxes[:, 1] - boxes[:, 3] / 2,
         boxes[:, 0] + boxes[:, 2] / 2, boxes[:, 1] + boxes[:, 3] / 2], 1
    )
    idx = torchvision.ops.batched_nms(
        torch.from_numpy(xyxy).float(), torch.from_numpy(conf).float(), torch.from_numpy(cls), NMS_IOU
    ).numpy()
    xyxy = xyxy[idx]
    xyxy[:, [0, 2]] = (xyxy[:, [0, 2]] - pad[0]) / ratio  # 去掉補邊、還原到原圖大小
    xyxy[:, [1, 3]] = (xyxy[:, [1, 3]] - pad[1]) / ratio
    return np.concatenate([xyxy, conf[idx, None], cls[idx, None]], 1)


def load_ground_truth(img_path: Path, w: int, h: int) -> np.ndarray:
    """讀取標註，回傳 [M, 5]：x1, y1, x2, y2（像素）, 類別。"""
    label = VAL_LABELS / f"{img_path.stem}.txt"
    rows = []
    if label.exists():
        for line in label.read_text(encoding="utf-8").splitlines():
            p = line.split()
            if len(p) >= 5:
                c, x, y, bw, bh = int(p[0]), *map(float, p[1:5])
                rows.append([(x - bw / 2) * w, (y - bh / 2) * h, (x + bw / 2) * w, (y + bh / 2) * h, c])
    return np.array(rows, dtype=np.float32).reshape(-1, 5)


def match(pred: np.ndarray, gt: np.ndarray) -> int:
    """回傳「框對位置、類別也對」的數量（每個標註最多配對一次）。"""
    if len(pred) == 0 or len(gt) == 0:
        return 0
    ious = torchvision.ops.box_iou(torch.from_numpy(pred[:, :4]).float(), torch.from_numpy(gt[:, :4]).float()).numpy()
    used, tp = set(), 0
    for i in np.argsort(-pred[:, 4]):  # 分數高的先配對
        for j in np.argsort(-ious[i]):
            if ious[i, j] < MATCH_IOU:
                break
            if j not in used and int(pred[i, 5]) == int(gt[j, 4]):
                used.add(j)
                tp += 1
                break
    return tp


def _score(predict_fn) -> tuple[float, float, float]:
    tp = n_pred = n_gt = 0
    for img_path in sorted(VAL_IMAGES.iterdir()):
        if img_path.suffix.lower() not in IMAGE_EXTS:
            continue
        img = cv2.imread(str(img_path))
        pred = predict_fn(img)
        gt = load_ground_truth(img_path, img.shape[1], img.shape[0])
        tp += match(pred, gt)
        n_pred += len(pred)
        n_gt += len(gt)
    precision = tp / max(n_pred, 1)
    recall = tp / max(n_gt, 1)
    f1 = 2 * precision * recall / max(precision + recall, 1e-9)
    return precision, recall, f1


def evaluate_tflite(model_path: Path, imgsz: int = 640) -> tuple[float, float, float]:
    try:
        from ai_edge_litert.interpreter import Interpreter
    except ImportError:
        from tensorflow.lite import Interpreter  # type: ignore
    it = Interpreter(model_path=str(model_path))
    it.allocate_tensors()
    inp, out = it.get_input_details()[0], it.get_output_details()[0]

    def predict(img: np.ndarray) -> np.ndarray:
        boxed, ratio, pad = letterbox(img, imgsz)
        x = cv2.cvtColor(boxed, cv2.COLOR_BGR2RGB).astype(np.float32)[None] / 255.0
        if inp["dtype"] in (np.int8, np.uint8):  # 完全量化的模型：輸入要先量化
            scale, zero = inp["quantization"]
            x = (x / scale + zero).astype(inp["dtype"])
        it.set_tensor(inp["index"], x)
        it.invoke()
        y = it.get_tensor(out["index"])[0]
        if out["dtype"] in (np.int8, np.uint8):  # 輸出反量化
            scale, zero = out["quantization"]
            y = (y.astype(np.float32) - zero) * scale
        return decode(y, ratio, pad)

    return _score(predict)


def evaluate_pt(model_path: Path, imgsz: int = 640) -> tuple[float, float, float]:
    from ultralytics import YOLO

    model = YOLO(str(model_path))

    def predict(img: np.ndarray) -> np.ndarray:
        r = model.predict(img, imgsz=imgsz, conf=CONF, iou=NMS_IOU, device="cpu", verbose=False)[0].boxes
        return np.concatenate([r.xyxy.numpy(), r.conf.numpy()[:, None], r.cls.numpy()[:, None]], 1)

    return _score(predict)
