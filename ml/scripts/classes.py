"""EdgeMJ 的 42 種類別定義，以及各種常見別名的對照表。

別名對照表用來把網路上下載的資料集（每個人命名方式都不同，
例如 "1B"、"bamboo_1"、"一條"）統一轉成我們的類別編號。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

# 讓 Windows 終端機的中文輸出不會變亂碼
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ML_ROOT = Path(__file__).resolve().parents[1]
DATASET_DIR = ML_ROOT / "datasets" / "mahjong"

# 類別代碼（順序 = 類別編號，必須和 data.yaml 一致）
CODES: list[str] = (
    [f"{n}m" for n in range(1, 10)]
    + [f"{n}p" for n in range(1, 10)]
    + [f"{n}s" for n in range(1, 10)]
    + [f"{n}z" for n in range(1, 8)]
    + [f"{n}f" for n in range(1, 9)]
)

_CN = "一二三四五六七八九"
_HONORS = "東南西北中發白"
_FLOWERS = "春夏秋冬梅蘭菊竹"  # 依牌面數字：春1夏2秋3冬4、梅1蘭2菊3竹4

# 中文名稱，方便印出統計表
ZH: list[str] = (
    [f"{_CN[i]}萬" for i in range(9)]
    + [f"{_CN[i]}筒" for i in range(9)]
    + [f"{_CN[i]}條" for i in range(9)]
    + list(_HONORS)
    + list(_FLOWERS)
)


def normalize(name: str) -> str:
    """統一大小寫並去掉空白、底線、連字號、句點，例如 "Red_Dragon" → "reddragon"。"""
    return re.sub(r"[\s_\-.]", "", str(name)).lower()


def _build_aliases() -> dict[str, int]:
    aliases: dict[str, int] = {}

    def add(cls: int, *names: str) -> None:
        for n in names:
            aliases[normalize(n)] = cls

    # 數牌：各種花色寫法 × 數字（前後都試）
    suit_words = {
        0: ["m", "man", "wan", "c", "character", "characters", "crak", "萬", "万"],
        9: ["p", "pin", "d", "dot", "dots", "circle", "circles", "tong", "筒", "餅", "饼"],
        18: ["s", "sou", "b", "bam", "bamboo", "bamboos", "tiao", "條", "条", "索"],
    }
    for base, words in suit_words.items():
        for n in range(1, 10):
            for w in words:
                add(base + n - 1, f"{n}{w}", f"{w}{n}")
        # 紅五（日麻常見 0m / 5mr）視為一般的五
        for w in words:
            add(base + 4, f"0{w}", f"5{w}r", f"r5{w}", f"red5{w}")
    for n in range(1, 10):
        add(n - 1, f"{_CN[n - 1]}萬", f"{_CN[n - 1]}万")
        add(9 + n - 1, f"{_CN[n - 1]}筒", f"{_CN[n - 1]}餅")
        add(18 + n - 1, f"{_CN[n - 1]}條", f"{_CN[n - 1]}条", f"{_CN[n - 1]}索")

    # 字牌
    # ⚠ 我們的 5z=中、7z=白；但日本麻將（天鳳）的寫法是 5z=白、7z=中，剛好相反。
    #   匯入日麻風格的資料集時，請務必看照片確認，必要時用 --mapping 對調。
    honor_words = [
        ["east", "ton", "東", "东", "eastwind"],
        ["south", "nan", "南", "southwind"],
        ["west", "sha", "xi", "西", "westwind"],
        ["north", "pei", "bei", "北", "northwind"],
        ["red", "reddragon", "chun", "zhong", "中", "dragonred"],
        ["green", "greendragon", "hatsu", "fa", "發", "发", "dragongreen"],
        ["white", "whitedragon", "haku", "bai", "白", "dragonwhite"],
    ]
    for i, words in enumerate(honor_words):
        add(27 + i, f"{i + 1}z", f"z{i + 1}", *words)

    # 花牌：很多資料集用 season1~4 = 春夏秋冬、flower1~4 = 梅蘭菊竹（牌面數字順序）
    flower_words = [
        ["spring", "春", "season1"],
        ["summer", "夏", "season2"],
        ["autumn", "fall", "秋", "season3"],
        ["winter", "冬", "season4"],
        ["plum", "梅", "flower1", "plumblossom"],
        ["orchid", "蘭", "兰", "flower2"],
        ["chrysanthemum", "菊", "flower3"],
        ["bambooflower", "竹", "flower4"],
    ]
    for i, words in enumerate(flower_words):
        add(34 + i, f"{i + 1}f", f"f{i + 1}", *words)

    # 我們自己的代碼一定要對得到
    for i, code in enumerate(CODES):
        add(i, code)
    return aliases


ALIASES: dict[str, int] = _build_aliases()


def read_names(yaml_path: Path) -> list[str]:
    """讀取 data.yaml 的 names（支援 list 或 {編號: 名稱} 兩種寫法）。"""
    data = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))
    names = data["names"]
    if isinstance(names, dict):
        return [str(names[k]) for k in sorted(names, key=int)]
    return [str(n) for n in names]


def check_target_yaml() -> None:
    """確認 data.yaml 的類別順序沒有被改動。"""
    names = read_names(DATASET_DIR / "data.yaml")
    if names != CODES:
        raise SystemExit("錯誤：data.yaml 的類別和 classes.py 的 CODES 不一致，請檢查是否被改過。")
