# EdgeMJ 專案技術棧與學習地圖

> 寫給想看懂這個專案的初學者。內容依照 2026-11-18 的程式碼整理（包含尚未 commit 的「掃描框＋手牌過濾」）。

一句話介紹：**EdgeMJ 是一個完全離線的麻將聽牌辨識 App**。拍一張手牌照片 → AI 認出每張牌 → 算出聽哪些牌。
「Edge（邊緣）」的意思是 AI 直接在你的手機或電腦上跑，不需要網路、也不用租雲端伺服器。

---

## 1. 整體系統架構圖

專案分成兩大塊，彼此只靠**一個模型檔**和**同一套牌的編號**連在一起：

```
┌──────────────────────── A. 電腦端：訓練 AI（Python，只做一次）────────────────────────┐
│                                                                                       │
│  網路上的公開資料集          import_dataset.py        check_dataset.py                 │
│  (Roboflow, YOLO 格式)  ──►  轉成我們的 42 類編號  ──►  檢查數量、錯誤                  │
│   ml/raw/                    ml/datasets/mahjong/                                     │
│                                       │                                               │
│                                       ▼                                               │
│                              train.py（YOLOv8n，用顯示卡 GPU 訓練 100 輪）              │
│                              → ml/runs/.../weights/best.pt                            │
│                                       │                                               │
│                                       ▼                                               │
│                              export_tflite.py（轉成手機格式）＋ evaluate.py（驗證）     │
│                              → ml/exports/edgemj_float16.tflite                       │
└───────────────────────────────────────┬───────────────────────────────────────────────┘
                                        │  手動複製到 assets/models/（唯一的交接點）
                                        ▼
┌──────────────────────── B. App 端：使用 AI（Flutter / Dart，離線）────────────────────┐
│                                                                                       │
│  scan_page.dart  使用者拍照/選相簿（image_picker）、拖拉掃描框                          │
│        │                                                                              │
│        ▼                                                                              │
│  tile_detector.dart（總指揮）                                                         │
│    ① preprocess.dart     解碼照片、轉正、裁切掃描框、縮成 640×640（letterbox）          │
│    ② TFLite 模型          tflite_flutter 執行 edgemj_float16.tflite                    │
│    ③ yolo_decoder.dart   把 8400 個候選框解讀成「哪裡有什麼牌」、去除重疊（NMS）         │
│    ④ hand_filter.dart    剔除不像手牌的框、標記需確認的牌                                │
│        │                                                                              │
│        ▼                                                                              │
│  tile_reading.dart  由左到右排好 → 手牌（Tile）＋花牌                                   │
│        │                                                                              │
│        ▼                                                                              │
│  core/mahjong/hand_analyzer.dart  純演算法：算聽哪些牌（台灣16張／香港／日本）           │
│        │                                                                              │
│        ▼                                                                              │
│  畫面顯示：框框（綠=手牌、黃=需確認、灰=被過濾）＋ 聽牌結果                             │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

**兩邊的「約定」**（改了任何一邊，另一邊就要跟著改）：

| 約定 | Python 端 | Dart 端 |
|------|-----------|---------|
| 牌的編號 0–33（萬筒條字）、34–41（花牌） | `ml/scripts/classes.py`、`data.yaml` | `lib/core/mahjong/tile.dart`、`tile_reading.dart` |
| 輸入格式 640×640、RGB、0~1、灰色 114 補邊 | `evaluate.py` 的 `letterbox()` | `preprocess.dart` |
| 輸出格式 `[1, 46, 8400]` | `evaluate.py` 的 `decode()` | `yolo_decoder.dart` |

> 小提醒：`evaluate.py` 的 NMS 門檻是 0.7，App 端 `decodeYoloOutput()` 預設 0.5，兩邊數字不完全一樣，比較結果時要記得。

---

## 2. 技術清單盤點

### App 端（Flutter / Dart）

| 技術 | 在這個專案負責什麼 | 在哪裡看到 |
|------|-------------------|-----------|
| **Dart**（程式語言） | 寫整個 App 和演算法 | `lib/` 全部 |
| **Flutter**（3.50） | 用一套程式做出 Windows / Android / iOS 畫面 | `lib/main.dart`、`lib/pages/` |
| **Material 3** | 現成的按鈕、分頁列等介面元件 | `main.dart` 的 `NavigationBar` |
| **tflite_flutter**（0.12） | 在 App 裡執行 AI 模型；`IsolateInterpreter` 讓模型在背景跑、畫面不卡 | `tile_detector.dart` |
| **image**（4.x） | 純 Dart 的圖片處理：解碼 jpg、轉正（EXIF）、裁切、縮放 | `preprocess.dart` |
| **image_picker** | 開相機拍照、從相簿選照片 | `scan_page.dart` |
| **Isolate**（Dart 內建） | 把耗時工作丟到背景執行緒，避免畫面凍結 | `tile_detector.dart` 的 `Isolate.run` |
| **CustomPainter**（Flutter 內建） | 在照片上畫辨識框、畫可拖拉的掃描框 | `scan_page.dart` 的 `_BoxPainter`、`_CropPainter` |
| **flutter_test** | 自動化測試（目前 74 個） | `test/` |
| **flutter_lints** | 檢查程式寫法是否規範 | `analysis_options.yaml` |
| **TFLite C 函式庫 DLL** | Windows 版執行模型需要的底層檔案（自己從 TF 2.19 原始碼編譯） | `blobs/libtensorflowlite_c-win.dll`、`windows/CMakeLists.txt` |
| **CMake + Visual Studio** | 編譯 Windows 桌面版 | `windows/` |

### AI 訓練端（Python）

| 技術 | 在這個專案負責什麼 | 在哪裡看到 |
|------|-------------------|-----------|
| **Python + venv** | 訓練專用的獨立環境，不污染系統 | `ml/.venv/`、`ml/requirements.txt` |
| **YOLOv8n** | 物件偵測模型：一次找出照片中「每張牌的位置＋種類」。n = nano，最小最快，適合手機 | `train.py` |
| **Ultralytics** | YOLO 官方套件：訓練、資料增強、匯出格式都靠它 | `train.py`、`export_tflite.py` |
| **PyTorch（CUDA 版）** | Ultralytics 底層的深度學習框架，用 NVIDIA 顯示卡（RTX 3060 Ti）加速 | `train.py` 的 `torch.cuda` |
| **TensorFlow / TFLite** | 把模型轉成手機能跑的 `.tflite` 輕量格式 | `export_tflite.py` |
| **OpenCV、NumPy、torchvision** | 驗證時讀圖、算數字、做 NMS | `evaluate.py` |
| **PyYAML、Pillow** | 讀寫資料集設定、檢查圖片 | `import_dataset.py`、`check_dataset.py` |
| **Roboflow Universe** | 下載公開的麻將牌標註資料（目前用 Mahjong-Tiles-Merged，3,942 張） | `ml/README.md`、`ml/mappings/` |

### 開發工具

| 工具 | 用途 |
|------|------|
| Git + GitHub（私人 repo） | 版本控制，`.gitignore` 排除照片、權重等大檔 |
| Windows 開發人員模式 | Flutter plugin 需要建立捷徑（symlink） |

---

## 3. 關鍵實作流程解析

### 環節一：資料準備 —— 讓 AI 有東西可學

**檔案**：`ml/scripts/import_dataset.py`、`ml/mappings/mahjong-tiles-merged.json`、`ml/datasets/mahjong/data.yaml`

- YOLO 的標註格式很簡單：每張照片配一個同名 `.txt`，每一行是一張牌：
  `類別編號 中心x 中心y 寬 高`（座標是 0~1 的比例）。
- 每個網路資料集的命名都不同（有人叫 `z5`、有人叫 `1D`），所以 `import_dataset.py` 會依照對照表把它們**統一翻譯成我們的 42 類編號**。
  實際踩過的坑：Mahjong-Tiles-Merged 的 `z5` 是白板、`z7` 是紅中，剛好跟我們相反，所以要寫在 mapping 檔裡。
- **最重要的設計**：編號 0–33 和 App 的 `Tile` 編號完全一樣，模型輸出的類別號碼可以直接變成牌，不用再轉換。

### 環節二：YOLOv8 訓練 —— 讓 AI 學會認牌

**檔案**：`ml/scripts/train.py`

- 從 `yolov8n.pt`（已經在大量一般照片上學過的「預訓練模型」）出發，再用麻將照片微調。這叫**遷移學習**，比從零開始快很多、需要的照片也少。
- 幾個針對麻將特別調整的設定，很值得看：
  - `fliplr=0.0`、`flipud=0.0`：**不翻轉圖片**，因為「萬」「東」翻過來會變成不存在的鏡像字。
  - `degrees=10.0`：小角度旋轉，模擬牌沒擺正。
  - `hsv_v=0.5`：亮度變化大，模擬不同燈光。
  - `patience=20`：連續 20 輪沒進步就自動停，避免浪費時間。
- 強制使用 GPU：偵測不到顯示卡就停止，不會偷偷用很慢的 CPU。
- 成果：F1 94.1%（花牌較弱，81~98%）。

### 環節三：匯出格式 —— 從電腦模型變成手機模型

**檔案**：`ml/scripts/export_tflite.py`、`ml/scripts/evaluate.py`

- `.pt`（PyTorch 格式）太大、手機跑不動，要轉成 `.tflite`（TensorFlow Lite，專給手機的輕量格式）。
- 會產出三種精度：
  - `float32`：原始精度，最大
  - `float16`：**目前 App 使用**，檔案小一半、準確度幾乎不變
  - `int8`：最小最快，需要用部分照片「校正」
- `nms=False`：去除重複框的步驟**不放在模型裡**，交給 App 自己做，相容性比較好。
- 在 Windows 上不能直接用 `format="tflite"`，所以繞道 `saved_model`，過程中會順便產出 `.tflite`。
- `evaluate.py` 用「和 App 完全相同的方式」解讀模型輸出，等於是 App 端的**參考答案**：轉檔前後分數接近，就代表轉檔沒壞。

### 環節四：影像前處理 —— 把照片變成模型看得懂的格式

**檔案**：`lib/core/vision/preprocess.dart`

模型只吃一種格式：`640×640`、RGB、每個數值 0~1。所以照片要經過：

1. **解碼**：jpg/png → 像素。
2. **轉正**（`bakeOrientation`）：手機照片常把方向記在 EXIF 裡，不轉正的話框會畫歪。
3. **裁切掃描框**：只把框內給模型，牌在模型眼中變大、比較好認，框外的海底牌也不會被誤認。
4. **Letterbox**：等比例縮小，空白處補灰色（114）。不直接拉伸成正方形，是因為牌會變形、模型就認不準。
5. 記下「縮放比例、補邊多少、裁切位置」，之後才能把框**還原**到原圖上。

這一步很耗時，所以用 `Isolate.run` 丟到背景跑。

### 環節五：Flutter 載入模型、推論、解讀與過濾

**檔案**：`lib/core/vision/tile_detector.dart` → `yolo_decoder.dart` → `hand_filter.dart` → `tile_reading.dart`

1. **載入**（`TileDetector.load()`）：從 `assets/models/` 讀模型，建立背景執行用的 `IsolateInterpreter`。第一次辨識時才載入，之後重複使用。
2. **推論**：把 640×640×3 的數字餵進去，拿回 `46 × 8400` 個數字。
3. **解讀**（`decodeYoloOutput()`）：
   - 8400 個候選框，每個框有 4 個座標 + 42 個類別分數。
   - 取分數最高的類別，低於 0.25 的丟掉。
   - 減去補邊、除以縮放比例 → 還原成原圖座標。
   - **NMS（非極大值抑制）**：重疊太多的框只留分數最高的。這裡「不分類別」一起比，因為一張實體牌只該算一次。
4. **手牌過濾**（`filterHandDetections()`）：這是針對麻將自己寫的規則：
   - 同一位置只留一張（處理「牌頂白色被認成白板」「七條被拆成兩張」）
   - 面積小於**中位數**一半的剔除（用中位數不用平均，因為海底牌一多平均會被拉低）
   - 不在同一橫排的剔除
   - 信心低於 0.6 的標黃色「需確認」
   - 張數不對只提醒，不偷偷刪牌
5. **整理**（`TileReading.fromDetections()`）：由左到右排序，分成手牌和花牌。

### 加碼：聽牌演算法（不用 AI，純邏輯）

**檔案**：`lib/core/mahjong/hand_analyzer.dart`

- 把手牌變成長度 34 的「張數陣列」。
- 胡牌判定：先挑一組將（眼），剩下的用**遞迴**拆成順子或刻子；每次只看最小的那張牌，所以又快又不會漏。
- 聽牌：34 種牌各「假設摸進來」一次，看會不會胡。
- 用 `MahjongRules` 切換台灣 16 張／香港 13 張／日本 13 張。

---

## 4. 給初學者的學習路線

建議**從不需要 AI 的部分開始**，先建立信心，再慢慢往 AI 走。

### 第 1 站：Dart 基礎 ＋ 純邏輯（約 1～2 週）

- **要學**：變數、函式、類別（class）、List / Map、`const`、遞迴
- **從這些檔案開始看**：
  1. `lib/core/mahjong/tile.dart` —— 最簡單，看「一張牌」怎麼用程式表示
  2. `lib/core/mahjong/hand_analyzer.dart` —— 聽牌演算法，練習看懂遞迴
  3. `test/core/mahjong/hand_analyzer_test.dart` —— 看測試怎麼寫，自己加一個牌型試試
- **動手練習**：執行 `flutter test`，故意改壞一行看測試失敗的樣子。

### 第 2 站：Flutter 畫面（約 1～2 週）

- **要學**：Widget、StatelessWidget / StatefulWidget、`setState`、`async / await`
- **從這些檔案開始看**：
  1. `lib/main.dart` —— App 的入口，兩個分頁怎麼切換
  2. `lib/pages/manual_input_page.dart` —— 輸入框＋按鈕＋顯示結果，結構單純
  3. `lib/pages/wait_text.dart` —— 很短的共用元件
- **動手練習**：改主題顏色、改分頁文字，執行 `flutter run -d windows` 看變化。

### 第 3 站：影像基礎概念（約 1 週）

- **要學**：像素與 RGB、圖片座標、縮放比例、EXIF 方向
- **從這些檔案開始看**：
  1. `lib/core/vision/preprocess.dart` —— letterbox 和裁切
  2. `lib/core/vision/yolo_decoder.dart` 裡的 `LetterboxInfo` —— 座標怎麼換算回去

### 第 4 站：物件偵測與 YOLO 概念（約 1～2 週）

- **要學**：什麼是物件偵測、bounding box（框）、信心分數、IoU、NMS、精確率／召回率／F1
- **從這些檔案開始看**：
  1. `lib/core/vision/yolo_decoder.dart` —— IoU 和 NMS 寫得很短，很適合理解原理
  2. `test/core/vision/yolo_decoder_test.dart` —— 用簡單的假資料看結果
  3. `lib/core/vision/hand_filter.dart` —— 看「AI 結果不完美時，怎麼用規則補救」
- **推薦資源**：Ultralytics 官方文件的 YOLOv8 介紹頁

### 第 5 站：Python 與模型訓練（約 2～3 週）

- **要學**：Python 基礎、venv、pip、命令列參數（argparse）、訓練／驗證／測試集的差別、過擬合、資料增強
- **從這些檔案開始看**：
  1. `ml/README.md` —— 整個訓練流程的說明書，先讀這個
  2. `ml/scripts/classes.py` —— 42 類怎麼定義
  3. `ml/scripts/train.py` —— 重點看 `model.train(...)` 的參數和註解
  4. `ml/runs/mahjong-yolov8n/` —— 訓練產生的圖表（混淆矩陣、loss 曲線），對照著看最有感
- **動手練習**：`ml\.venv\Scripts\python ml/scripts/train.py --epochs 3 --name test-run` 跑一次小訓練。

### 第 6 站：部署到裝置（約 1～2 週）

- **要學**：模型格式（.pt / .tflite）、量化（float16 / int8）、Flutter assets、Isolate 背景執行
- **從這些檔案開始看**：
  1. `ml/scripts/export_tflite.py` —— 轉檔
  2. `ml/scripts/evaluate.py` —— 對照 Python 和 Dart 的解讀方式（和 `yolo_decoder.dart` 並排看）
  3. `lib/core/vision/tile_detector.dart` —— 全部串起來的地方
  4. `lib/pages/scan_page.dart` —— 最長（約 500 行），留到最後看：拍照、掃描框、畫框、修改牌

### 建議的閱讀順序總整理

```
tile.dart → hand_analyzer.dart → main.dart → manual_input_page.dart
   → preprocess.dart → yolo_decoder.dart → hand_filter.dart → tile_reading.dart
   → ml/README.md → train.py → export_tflite.py → evaluate.py
   → tile_detector.dart → scan_page.dart
```

---

## 附錄：名詞小辭典

| 名詞 | 白話解釋 |
|------|----------|
| Edge AI | AI 在你自己的裝置上跑，不用連網 |
| 物件偵測 | 找出照片裡「東西在哪裡、是什麼」 |
| 預訓練模型 | 別人已經訓練好的通用模型，我們拿來微調 |
| Epoch（輪） | 把全部訓練照片看過一次 |
| 資料增強 | 把照片旋轉、調亮度等，讓 AI 看到更多變化 |
| Letterbox | 縮圖時保持比例，空白處補灰色 |
| 信心分數 | AI 覺得自己猜對的把握，0~1 |
| IoU | 兩個框重疊的程度，0=不重疊、1=完全重疊 |
| NMS | 重複的框只留最好的那個 |
| 量化 | 把模型的數字精度降低，換取更小更快 |
| Isolate | Dart 的背景執行緒，避免畫面卡住 |
| F1 | 綜合「抓得準」和「抓得全」的分數 |
