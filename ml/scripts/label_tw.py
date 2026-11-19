"""台灣牌標註修正工具：在自己電腦開一個網頁，修正 draft_tw_labels.py 產生的草稿。

用法（在專案根目錄執行）：
    ml\\.venv\\Scripts\\python ml/scripts/label_tw.py

接著用瀏覽器打開畫面上顯示的網址。每次修改都會自動存檔，關掉後可以接著做。
只有這台電腦能連線；原始照片只會被讀取，不會被修改。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from classes import CODES, ZH

ML_ROOT = Path(__file__).resolve().parents[1]
PAGE = Path(__file__).with_name("label_tw.html")
MASK_CLASS = -1  # 遮蔽區：太遠或看不清楚的牌，匯出訓練資料時會塗掉
MAX_BODY = 2_000_000
MAX_BOXES = 500
STATUSES = {"todo", "done", "skip"}


def clean_boxes(raw: object) -> list[dict]:
    """檢查網頁送來的框，不合法就丟出 ValueError，避免寫入壞資料。"""
    if not isinstance(raw, list) or len(raw) > MAX_BOXES:
        raise ValueError("框的資料不正確")
    boxes = []
    for b in raw:
        cls = b["cls"]
        if not isinstance(cls, int) or isinstance(cls, bool) or not MASK_CLASS <= cls < len(CODES):
            raise ValueError("牌的類別不正確")
        x1, y1, x2, y2 = (float(b[k]) for k in ("x1", "y1", "x2", "y2"))
        if not (0 <= x1 < x2 <= 1 and 0 <= y1 < y2 <= 1):
            raise ValueError("框的位置不正確")
        conf = b.get("conf")
        boxes.append({
            "cls": cls,
            "x1": round(x1, 5), "y1": round(y1, 5), "x2": round(x2, 5), "y2": round(y2, 5),
            "conf": float(conf) if isinstance(conf, (int, float)) else None,
            "check": bool(b.get("check", False)),
        })
    return boxes


class Store:
    """讀寫每張照片的標註進度（一張照片一個 JSON）。"""

    def __init__(self, images: Path, work: Path) -> None:
        self.images = images
        self.work = work
        self.stems = {p.stem for p in work.glob("*.json") if (images / f"{p.stem}.jpg").is_file()}

    def load(self, stem: str) -> dict:
        return json.loads((self.work / f"{stem}.json").read_text(encoding="utf-8"))

    def save(self, stem: str, body: dict) -> dict:
        doc = self.load(stem)
        status = body.get("status")
        if status not in STATUSES:
            raise ValueError("狀態不正確")
        doc["status"] = status
        doc["boxes"] = clean_boxes(body.get("boxes"))
        target = self.work / f"{stem}.json"
        tmp = target.with_suffix(".tmp")
        tmp.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
        os.replace(tmp, target)  # 寫完才替換，中途當機也不會弄壞舊檔
        return doc

    def listing(self) -> list[dict]:
        rows = []
        for stem in self.stems:
            d = self.load(stem)
            rows.append({"stem": stem, "status": d["status"], "note": d.get("note", ""),
                         "count": len(d["boxes"]), "priority": d.get("priority", 0)})
        rows.sort(key=lambda r: (-r["priority"], r["stem"]))  # 最可能有錯的排前面
        return rows


def make_handler(store: Store) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args: object) -> None:
            pass  # 不把每個請求都印出來

        def _send(self, code: int, data: bytes, kind: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _json(self, obj: object, code: int = 200) -> None:
            self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

        def _stem(self, prefix: str) -> str | None:
            stem = unquote(urlparse(self.path).path[len(prefix):])
            return stem if stem in store.stems else None  # 只接受清單內的檔名

        def do_GET(self) -> None:
            path = urlparse(self.path).path
            if path == "/":
                self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
            elif path == "/api/meta":
                self._json({"codes": CODES, "names": ZH, "mask": MASK_CLASS})
            elif path == "/api/list":
                self._json(store.listing())
            elif path.startswith("/api/item/") and (stem := self._stem("/api/item/")):
                self._json(store.load(stem))
            elif path.startswith("/img/") and (stem := self._stem("/img/")):
                self._send(200, (store.images / f"{stem}.jpg").read_bytes(), "image/jpeg")
            else:
                self._json({"error": "找不到"}, 404)

        def do_POST(self) -> None:
            # 只接受本機網頁送來的 JSON，避免其他網站誤觸
            host = self.headers.get("Host", "").split(":")[0]
            kind = self.headers.get("Content-Type", "")
            length = int(self.headers.get("Content-Length") or 0)
            stem = self._stem("/api/item/") if self.path.startswith("/api/item/") else None
            if host not in {"127.0.0.1", "localhost"} or not kind.startswith("application/json"):
                return self._json({"error": "不允許"}, 403)
            if stem is None or not 0 < length <= MAX_BODY:
                return self._json({"error": "請求不正確"}, 400)
            try:
                doc = store.save(stem, json.loads(self.rfile.read(length)))
            except (ValueError, KeyError, TypeError) as e:
                return self._json({"error": str(e)}, 400)
            self._json({"ok": True, "status": doc["status"], "count": len(doc["boxes"])})

    return Handler


def main() -> None:
    p = argparse.ArgumentParser(description="台灣牌標註修正工具")
    p.add_argument("--images", type=Path, default=ML_ROOT.parent / "tw_mj", help="照片資料夾")
    p.add_argument("--work", type=Path, default=ML_ROOT / "raw" / "tw_mj_labels", help="標註進度資料夾")
    p.add_argument("--port", type=int, default=8765, help="網址使用的連接埠")
    args = p.parse_args()

    store = Store(args.images, args.work)
    if not store.stems:
        sys.exit("找不到標註草稿，請先執行 draft_tw_labels.py")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(store))
    print(f"請用瀏覽器打開：http://127.0.0.1:{args.port}/")
    print("要結束時，在這個視窗按 Ctrl+C（進度已自動存檔）")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    main()
