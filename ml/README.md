# EdgeMJ 機器學習（YOLO 麻將辨識）

## 資料夾結構

```
ml/
├── datasets/mahjong/        ← 最終訓練用的資料集
│   ├── data.yaml            ← YOLO 設定檔（42 類）
│   ├── images/
│   │   ├── train/           ← 訓練用照片（約 80%）
│   │   ├── val/             ← 驗證用照片（約 15%），訓練時用來評分
│   │   └── test/            ← 測試用照片（約 5%），最後檢驗用
│   └── labels/
│       ├── train/           ← 每張照片對應一個同名 .txt 標註檔
│       ├── val/
│       └── test/
├── raw/                     ← 從網路下載的原始資料集放這裡（解壓縮後）
├── scripts/
│   ├── classes.py           ← 42 類定義與別名對照
│   ├── import_dataset.py    ← 把下載的資料集轉成我們的類別編號
│   ├── check_dataset.py     ← 統計每種牌的數量、檢查錯誤
│   ├── train.py             ← 訓練 YOLOv8n 模型
│   ├── export_tflite.py     ← 轉成手機用的 .tflite
│   └── evaluate.py          ← 比較轉檔前後準確度（也是 App 解讀輸出的參考）
├── exports/                 ← 轉好的 .tflite（不進版控）
├── weights/                 ← 預訓練權重（不進版控）
├── runs/                    ← 訓練結果（不進版控）
├── .venv/                   ← 訓練專用的 Python 環境（不進版控）
└── requirements.txt
```

照片和標註檔不會上傳到 GitHub（檔案太大），只保留資料夾結構。

## 42 個類別

| 編號 | 牌 |
|------|----|
| 0–8 | 一萬～九萬（1m–9m） |
| 9–17 | 一筒～九筒（1p–9p） |
| 18–26 | 一條～九條（1s–9s） |
| 27–33 | 東南西北中發白（1z–7z） |
| 34–41 | 春夏秋冬梅蘭菊竹（1f–8f，依牌面數字 1～4 排序） |

編號 0–33 與 App 裡的牌編號完全相同。**開始標註後就不要再改順序。**

## 標註檔格式

每張照片 `abc.jpg` 對應一個 `abc.txt`，每一行是一張牌：

```
類別編號 中心x 中心y 寬 高
4 0.512 0.430 0.061 0.118
```

座標都是 0～1 的比例（相對於照片寬高）。沒有任何牌的照片可以放空的 .txt，當作背景圖。

---

## 開源資料集建議

### 推薦先下載的（Roboflow Universe，免費帳號即可下載）

| 資料集 | 規模 | 說明 |
|--------|------|------|
| [Mahjong-Tiles-Merged](https://universe.roboflow.com/test-ag8z6/mahjong-tiles-merged/dataset/1) | 約 3,900 張 | 已合併多個來源，有 YOLOv8 格式 |
| [Makinoi](https://universe.roboflow.com/lester-so-h8rfw/makinoi) | 約 2,100 張 | 實拍照片，用途和我們很接近 |
| [mahjong_data](https://universe.roboflow.com/mahjong-asqzm/mahjong_data/dataset/3) | 約 3,700 張 | 數量多 |
| [Mahjong (roman-nguyen)](https://universe.roboflow.com/roman-nguyen/mahjong-vtacs) | — | 34 類 |
| [Mahjong Tiles universal](https://universe.roboflow.com/test-ag8z6/mahjong-tiles-universal) | — | CC BY 4.0 授權 |

其他可以參考的：在 [Roboflow Universe](https://universe.roboflow.com/search?q=mahjong) 搜尋 `mahjong`，會有幾十個專案。

### 避開的類型
- **雀魂（Mahjong Soul）遊戲截圖**的資料集：那是電腦畫面，不是實體牌，對相機辨識幫助不大
- **只有分類（classification）、沒有框（bounding box）的**資料集：YOLO 用不了

### 重要提醒
1. **大部分公開資料集是日本麻將牌**，跟台灣牌的字體、顏色、大小不太一樣，而且**幾乎都沒有花牌**。
   最有效的做法是：先用公開資料集訓練一個基礎模型，**再用自己家的牌拍照補資料**。
2. 下載前看一下授權（License），CC BY 4.0 或 Public Domain 最安全。
3. 每個資料集的類別命名都不同，匯入時腳本會印出對照表，**請一定要看過一次確認對得正確**。
   特別注意 `flower1~4`、`1D` 這類寫法，不同作者的意思可能不一樣。

### 搜尋關鍵字
- Roboflow Universe：`mahjong`、`mahjong tiles`、`麻將`、`riichi`
- Kaggle：`mahjong tiles`
- Hugging Face Datasets：`mahjong`
- GitHub：`mahjong yolo dataset`、`麻将识别 数据集`（簡體中文搜尋常會找到中國大陸的專案）

---

## 下載與匯入步驟

1. 在 Roboflow 資料集頁面按 **Download Dataset**，格式選 **YOLOv8**，下載 zip
2. 解壓縮到 `ml/raw/資料集名稱/`（例如 `ml/raw/makinoi/`）
3. 安裝工具（只需一次）：
   ```
   pip install -r ml/requirements.txt
   ```
4. 先預覽對照表（不會複製檔案）：
   ```
   python ml/scripts/import_dataset.py ml/raw/makinoi --dry-run
   ```
5. 如果有對不到的類別（例如牌背 `back`），可以：
   - 加上 `--drop-unknown` 直接丟掉
   - 或寫一個 JSON 檔自訂對照，例如 `{"1D": "5z", "back": null}`，再加上 `--mapping 檔名.json`
6. 確認沒問題後正式匯入：
   ```
   python ml/scripts/import_dataset.py ml/raw/makinoi --drop-unknown
   ```
7. 檢查資料集：
   ```
   python ml/scripts/check_dataset.py
   ```

## 已匯入的資料集

| 資料集 | 對照檔 | 說明 |
|--------|--------|------|
| [Mahjong-Tiles-Merged v1](https://universe.roboflow.com/test-ag8z6/mahjong-tiles-merged/dataset/1)（CC BY 4.0） | `mappings/mahjong-tiles-merged.json` | 3,942 張，中式牌含花牌。已看照片確認：它的 `z5`=白、`z7`=中（和我們相反），花牌 `f5~f8`=梅蘭菊竹 |

重新匯入的指令：
```
python ml/scripts/import_dataset.py ml/raw/merged --name merged --mapping ml/mappings/mahjong-tiles-merged.json
```

## 訓練模型

所有指令都在專案根目錄執行，並使用 `ml\.venv` 裡的 Python：

```
ml\.venv\Scripts\python ml/scripts/train.py --epochs 3    # 先跑 3 輪，確認一切正常
ml\.venv\Scripts\python ml/scripts/train.py               # 正式訓練（預設 100 輪）
ml\.venv\Scripts\python ml/scripts/train.py --resume      # 中斷後繼續
```

- 會自動使用 NVIDIA 顯示卡；顯示卡記憶體不足時加上 `--batch 8`
- 連續 20 輪沒進步會自動提早結束
- 結果在 `ml/runs/mahjong-yolov8n/`，最好的模型是 `weights/best.pt`
- 不做左右／上下翻轉：翻轉後的「萬」「東」是鏡像字，現實中不存在

## 轉成手機用的 .tflite

```
ml\.venv\Scripts\python ml/scripts/export_tflite.py --int8
```

輸出到 `ml/exports/`（不進版控）：

| 檔案 | 大小 | 說明 |
|------|------|------|
| `edgemj_float32.tflite` | 約 12 MB | 原始精度 |
| `edgemj_float16.tflite` | 約 6 MB | 建議手機使用 |
| `edgemj_int8.tflite` | 約 3 MB | 最小最快（`--int8` 才會產生） |
| `labels.txt` | — | 類別名稱，順序 = 類別編號 |

**為什麼在 Windows 走 SavedModel 路線**：新版 Ultralytics 的 `format="tflite"` 只支援 Linux／macOS，
`format="saved_model"` 在 Windows 也能用，過程中會一併產生 .tflite。

**為什麼不用 Ultralytics 內建的驗證**：它會把 .tflite 輸出的座標當成 0～1 比例再乘一次 640，
導致分數錯誤地變成 0%。所以改用 `evaluate.py` 自己解讀輸出，和原始模型用同一套標準比較。

### 模型的輸入與輸出（App 端要照這個格式）
- **輸入**：`[1, 640, 640, 3]` float32，RGB，數值 0～1；等比例縮放後用灰色 (114) 補邊
- **輸出**：`[1, 46, 8400]`；46 = 4 個座標 + 42 個類別分數
  - 座標是**像素**單位的 中心x、中心y、寬、高（以 640×640 輸入為基準）
  - 後處理：取每個候選框最高的類別分數 → 過濾低分（例如 < 0.25）→ NMS 去除重疊框
- 完整的參考實作在 `scripts/evaluate.py`

### 第一版模型成績（驗證集 449 張）

| 模型 | 精確率 | 召回率 | F1 |
|------|--------|--------|----|
| best.pt（原始） | 92.4% | 95.9% | 94.1% |
| float32.tflite | 92.4% | 95.9% | 94.1% |
| float16.tflite | 92.3% | 95.9% | 94.1% |
| int8.tflite | 92.6% | 95.7% | 94.1% |

## 自己拍照與標註（提升台灣牌準確度的關鍵）

**拍照技巧**
- 用**手機**拍（跟之後 App 實際使用的鏡頭一樣）
- 變化越多越好：白天／晚上燈光、不同桌布顏色、正面／斜角、牌立著／躺著、遠近
- 每張照片放 10～17 張牌，盡量每種牌都出現，**花牌也要拍**
- 目標：每種牌在 train 至少 **100～200 個**標註框

**標註工具（都可以完全離線使用）**
- [X-AnyLabeling](https://github.com/CVHub520/X-AnyLabeling)：有中文介面，可以用訓練好的模型自動標註，再手動修正
- [Label Studio](https://labelstud.io/)：在自己電腦上開網頁使用，功能完整

**省力技巧**：先用公開資料集訓練出第一版模型，用它自動標註你拍的照片，你只要修正錯的地方就好，速度可以快好幾倍。
