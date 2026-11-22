# EdgeMJ 專案交接說明（給 Claude 看的）

這份檔案會被 Claude Code 自動讀取。使用者在 **Windows**（主要開發機）和 **Mac**（只用來編譯 iPhone 版）兩邊都會用 Claude，
兩邊的對話紀錄不會互通，所以重要進度請更新在這份檔案，並推上 GitHub。

## 使用者偏好（很重要）
- 一律用 **繁體中文** 回答；使用者是新手，說明要簡單、避免專業術語、**先講結論**
- **刪除、覆蓋或大幅修改檔案前，先問**；不確定意思時先問清楚
- 完成後簡短說明做了什麼、檔案放在哪裡
- 程式碼註解用繁體中文
- 主要打 **台灣 16 張**（預設規則），也要能切換香港牌、日本牌；台灣牌不要加嚦咕嚦咕
- 訓練模型一律用 **GPU**（CUDA），不要用 CPU（只有 Windows 機器能訓練）

## 專案是什麼
完全離線的麻將聽牌辨識 App（Flutter）。鏡頭／照片 → YOLOv8n（TFLite）認牌 → 算聽牌。
- 私人 repo：github.com/nian556/EdgeMJ（main 分支）
- App 程式：`lib/`
  - `core/mahjong/`：牌型、聽牌計算
  - `core/vision/`：前處理、模型推論、解讀輸出、手牌過濾
  - `pages/`：三個分頁
    - `live_scan_page.dart`：即時辨識
    - `scan_page.dart`：拍照辨識
    - `manual_input_page.dart`：手動輸入
- 模型：`assets/models/edgemj_float16.tflite`（42 類，含 8 張花牌）+ `labels.txt`，已在 git 裡
- 訓練相關：`ml/`（Python，只在 Windows 用；照片 `tw_mj/` 和資料集不進 git）
- 測試：`flutter test`（目前 79 項全過）

## 目前進度（2026-11-21）
- ✅ 拍照辨識版完成；模型已用自拍台灣牌補訓練（台灣牌測試 86.8% → 99.5%）
- ✅ 第二次補訓練（2026-11-21）：加入 Roboflow 台灣牌 30 張 + 使用者照片 8 張（標註在 `ml/raw/extra_mj_labels/`，
  匯出用 `ml/scripts/export_extra_dataset.py`）。模型在 `ml/runs/mahjong-tw-finetune2/`，已換進 App。
  比較結果：台灣牌測試 98.9% → 99.5%、新照片測試 87.3% → 93.0%、原大資料集 mAP50 0.972 → 0.978。
  換掉的舊模型備份在 Windows 本機 `ml/exports_v2_old/`（不進 git）
- ✅ Windows 桌面版可編譯執行（`flutter build windows`）
- ✅ 相公提醒（2026-11-23）：手牌（不含花牌）是 3 的倍數張時，拍照頁和即時頁都會跳紅色提醒
  （`lib/core/vision/hand_filter.dart` 的 `checkHandWarnings`）
- 🔶 **即時辨識頁** 剛寫好：用 `camera` 套件不停 `takePicture()` → 辨識，連續兩輪一樣才更新結果。
  Windows 電腦沒有鏡頭，所以另有「照片模擬鏡頭」模式。**還沒在真的鏡頭／手機上測過。**
- 🔶 **iPhone 版**：從沒編譯過。教學在 `docs/iPhone測試教學.docx`。
  `ios/Runner/Info.plist` 已加相機、相簿權限說明。

## 在 Mac 上要做的事（iPhone 測試）
使用者的測試手機是 **iPhone 11**，用 **免費 Apple ID** 簽名（App 7 天後要重裝）。
1. 確認 Xcode、Homebrew、Flutter、CocoaPods 已安裝（`flutter doctor`，Xcode 那項要打勾）
2. 在專案資料夾執行 `flutter pub get`
3. 簽名要在 Xcode 裡設定（`open ios/Runner.xcworkspace` → Runner → Signing & Capabilities → Team 選 Personal Team）。
   原本的 Bundle ID `com.edgemj.edgeMj` 可能已被佔用，要換成獨一無二的，例如 `com.nian556.edgemj`。
   這一步要引導使用者自己點，Claude 無法代點 Xcode 畫面
4. iPhone 接線、按「信任」、開「開發者模式」，然後執行 `flutter run --release`
5. 第一次裝好要到 iPhone「設定 → 一般 → VPN 與裝置管理」信任開發者
6. 測試重點：即時辨識頁的框有沒有對準牌（手機直拍時，照片的 EXIF 旋轉和預覽畫面可能對不上）、每秒辨識幾次、拍照頁、選相簿

### Mac 上的注意事項
- 需要輸入 Mac 密碼的指令（`sudo`）請使用者自己在終端機輸入
- 在 Mac 上 **不要改模型、不要跑訓練**；改程式就 commit 並 push，Windows 那邊再 `git pull`
- 測試結果和遇到的問題記在下面「Mac 測試紀錄」，並 push 回 GitHub，Windows 的 Claude 才看得到

## App Store 上架準備清單（2026-11-23 評估，尚未開始）
App 完全離線、沒有登入／內購／伺服器，所以帳號刪除、IAP、UGC、測試帳號等規定都不適用。要做的事：
- 🔴 **付費開發者帳號**（Apple Developer Program，每年 99 美元）：免費 Apple ID 不能上架。建議個人帳號（不用 D-U-N-S，但賣家名稱會顯示本名）
- 🔴 **隱私權政策網址**（HTTPS、能打開）：內容寫「不收集任何資料，照片只在手機上處理」。repo 是私人的，要另外找地方放（例如 Google 協作平台或另開公開 repo）
- 🔴 **先在 iPhone 實機測過**，確定不閃退（見上面「在 Mac 上要做的事」）
- 🟡 **藏起「照片模擬鏡頭」按鈕**（`live_scan_page.dart`）：只給 Windows 測試用，手機版會被當成半成品
- 🟡 **iPad**：目前 `TARGETED_DEVICE_FAMILY = "1,2"`（iPhone＋iPad）。要嘛在 iPad 測版面，要嘛改成只支援 iPhone（`"1"`）
- 🟡 **Bundle ID**：換成自己的（例如 `com.nian556.edgemj`），第一次上傳後就不能改
- 🟡 **加密問卷**：`Info.plist` 加 `ITSAppUsesNonExemptEncryption` = NO
- 🟡 每次上傳 Build 號要遞增（`pubspec.yaml` 的 `version: x.y.z+N`，N 要加 1）；送審前用 TestFlight 裝同一個 Build 測
- ✅ 相機／相簿權限說明已寫好；隱私權標籤填「不收集資料」
- 審核備註：寫清楚怎麼用（對手牌拍照、或用手動輸入分頁），附範例手牌照片（審核員手邊不一定有麻將）
- ⚠️ 麻將可能被聯想成賭博：說明寫明是「聽牌計算工具，不涉及金錢」，截圖與文字避免籌碼、金額字眼；年齡分級照實填

順序：Mac 編譯＋實機測試 → 付費加入開發者計畫 → 處理 🟡 項目 → TestFlight → 送審

## Windows 開發環境備忘
- Flutter 3.50.0 在 `C:\Users\user\develop\flutter`；已開啟 Windows 開發人員模式（plugin 需要）
- `flutter pub get`／`build` 要在 PowerShell 跑（Git Bash 會誤判沒有 symlink 權限）
- tflite 的 Windows DLL 是自己編的，放在 `blobs/`（已進 git）
- 訓練：`ml\.venv\Scripts\python ml/scripts/train.py`；Windows 上跑 ultralytics val 的腳本要加 `workers=0`，否則會卡住

## Mac 測試紀錄
（尚無。測完在這裡記：日期、iOS 版本、哪些功能正常、哪裡有問題）
