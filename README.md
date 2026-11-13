# EdgeMJ

完全離線、零成本的麻將聽牌辨識輔助 App（Flutter + YOLO + TFLite）。

## 開發進度

- [x] 階段一：麻將聽牌／胡牌判定演算法（純 Dart）＋單元測試
- [ ] 階段二：資料集資料夾結構與 `data.yaml`
- [ ] 階段三：YOLOv8n 訓練與 TFLite 轉檔腳本

## 第一次使用

1. 安裝 Flutter：https://docs.flutter.dev/get-started/install/windows
2. 在專案資料夾執行（補上 Android／iOS 平台資料夾，已存在的檔案不會被覆蓋）：
   ```
   flutter create . --project-name edge_mj --platforms=android,ios
   ```
3. 執行測試：`flutter test`
4. 執行 App：`flutter run`

> iOS 版需要在 Mac 上才能編譯。

## 專案結構

```
lib/
  main.dart                     暫時的手動輸入畫面
  core/mahjong/
    tile.dart                   34 種牌的定義、簡寫解析（123m456p789s1z）
    hand_analyzer.dart          胡牌／聽牌判定
    mahjong.dart                統一匯出
test/
  core/mahjong/                 演算法單元測試
  widget_test.dart              畫面測試
```

## 牌的編號（之後也作為 YOLO 類別 id）

| id | 牌 | 簡寫 |
|----|----|------|
| 0–8 | 一萬～九萬 | 1m–9m |
| 9–17 | 一筒～九筒 | 1p–9p |
| 18–26 | 一條～九條 | 1s–9s |
| 27–33 | 東南西北中發白 | 1z–7z |

## 使用範例

```dart
// 預設是台灣牌（16 張）
final waits = const HandAnalyzer().waitingTiles(parseTiles('1112345678999m123p'));
// → 1m ~ 9m

// 切換規則
const HandAnalyzer(MahjongRules.hongKong).waitingTiles(...);
const HandAnalyzer(MahjongRules.japanese).waitingTiles(...);
```

| 規則 | 手牌 | 特殊牌型 |
|------|------|----------|
| 台灣牌（預設） | 16 張 | 無（只看一般牌型） |
| 香港牌 | 13 張 | 七對子、十三么 |
| 日本牌 | 13 張 | 七對子、國士無雙 |
