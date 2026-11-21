# 第二批標註（2026-11-21）

照片放在 `ml/raw/extra_mj/`（不進 git），一張照片對應一個 JSON，格式和 `tw_mj_labels/` 相同，可用 `label_tw.py` 開啟：

    ml\.venv\Scripts\python ml/scripts/label_tw.py --images ml\raw\extra_mj --work ml\raw\extra_mj_labels

- `rf_IMG_*`：來自 Roboflow Universe「台灣麻將牌辨識」v1（https://universe.roboflow.com/-krbph/-jgzyu），
  授權 CC BY 4.0。原始標註已由使用者人工重新檢查、修正（例如部分筒子、條子被誤標為萬子）。
- `S__*`、`Snipaste_*`：使用者提供的照片（原檔在 `ml/raw/maj/`）。

匯出訓練資料：`ml\.venv\Scripts\python ml/scripts/export_extra_dataset.py`
