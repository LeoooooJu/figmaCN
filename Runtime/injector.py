import json
import os
import re
from datetime import datetime
from pathlib import Path

from mitmproxy import ctx, http


BASE_DIR = Path(__file__).resolve().parent
LANG_DIR = BASE_DIR / "lang"
LANG_FILE = Path(os.environ.get("FigmaCN_LANG_FILE", LANG_DIR / "zh.json"))
REMOTE_LANG_URL = os.environ.get("FigmaCN_LANG_URL", "").strip()
CAPTURE_FILE = Path(os.environ.get("FigmaCN_CAPTURE_FILE", BASE_DIR / "latest" / "captured_language_urls.txt"))

FIGMA_LANG_PATTERN = re.compile(
    r"^/webpack-artifacts/assets/"
    r"figma_app(?:_beta|__react_profile)?(?:__rspack)?-[a-f0-9]+\.min\.en\.json(?:\.br)?$"
)

ANY_FIGMA_EN_JSON_PATTERN = re.compile(
    r"^/webpack-artifacts/assets/[^/?#]+\.en\.json(?:\.br)?$"
)

LANG_RULES = [
    {
        "label": "main",
        "pattern": FIGMA_LANG_PATTERN,
        "file": LANG_FILE,
        "remote_url": REMOTE_LANG_URL,
    },
    {
        "label": "auth",
        "pattern": re.compile(
            r"^/webpack-artifacts/assets/"
            r"auth(?:_iframe)?(?:__rspack)?-[a-f0-9]+\.min\.en\.json(?:\.br)?$"
        ),
        "file": Path(os.environ.get("FigmaCN_AUTH_LANG_FILE", LANG_DIR / "auth-zh.json")),
        "remote_url": os.environ.get("FigmaCN_AUTH_LANG_URL", "").strip(),
    },
    {
        "label": "prototype",
        "pattern": re.compile(
            r"^/webpack-artifacts/assets/"
            r"prototype_app(?:_beta)?(?:__rspack)?-[a-f0-9]+\.min\.en\.json(?:\.br)?$"
        ),
        "file": Path(os.environ.get("FigmaCN_PROTOTYPE_LANG_FILE", LANG_DIR / "prototype_app_beta-zh.json")),
        "remote_url": os.environ.get("FigmaCN_PROTOTYPE_LANG_URL", "").strip(),
    },
    {
        "label": "community",
        "pattern": re.compile(
            r"^/webpack-artifacts/assets/"
            r"community(?:__rspack)?-[a-f0-9]+\.min\.en\.json(?:\.br)?$"
        ),
        "file": Path(os.environ.get("FigmaCN_COMMUNITY_LANG_FILE", LANG_DIR / "community-zh.json")),
        "remote_url": os.environ.get("FigmaCN_COMMUNITY_LANG_URL", "").strip(),
    },
]


def _is_enabled() -> bool:
    raw = os.environ.get("FigmaCN_ENABLE_LOCALIZATION", "1").strip().lower()
    return raw not in {"0", "false", "no", "off"}


def _load_lang_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    json.loads(data.decode("utf-8"))
    return data


def _capture_url(flow: http.HTTPFlow, label: str) -> None:
    try:
        CAPTURE_FILE.parent.mkdir(parents=True, exist_ok=True)
        line = (
            f"{datetime.now().isoformat(timespec='seconds')}\t"
            f"{label}\t{flow.request.pretty_url}\n"
        )
        with CAPTURE_FILE.open("a", encoding="utf-8") as f:
            f.write(line)
    except Exception as exc:
        ctx.log.error(f"[Runtime] 写入语言包 URL 捕获文件失败: {exc}")


class LocalFigmaLanguagePack:
    def __init__(self):
        self.lang_bytes = {}
        self.enabled = _is_enabled()

    def load(self, loader):
        if not self.enabled:
            ctx.log.info("[Runtime] 中文包替换已禁用: FigmaCN_ENABLE_LOCALIZATION=0")
            return

        for rule in LANG_RULES:
            if rule["remote_url"]:
                ctx.log.info(f"[Runtime] {rule['label']} 远程中文包模式已启用: {rule['remote_url']}")
                continue
            path = rule["file"]
            if not path.exists():
                continue
            try:
                self.lang_bytes[rule["label"]] = _load_lang_bytes(path)
                ctx.log.info(f"[Runtime] {rule['label']} 中文包已加载: {path} ({len(self.lang_bytes[rule['label']])} bytes)")
            except Exception as exc:
                ctx.log.error(f"[Runtime] {rule['label']} 中文包加载失败: {path}: {exc}")

    def _match_rule(self, path: str):
        for rule in LANG_RULES:
            if rule["pattern"].match(path):
                return rule
        return None

    def request(self, flow: http.HTTPFlow) -> None:
        if not self.enabled:
            return

        host = (flow.request.host or "").lower()
        path = (flow.request.path or "").split("?", 1)[0]

        if host != "www.figma.com":
            return

        rule = self._match_rule(path)

        if ANY_FIGMA_EN_JSON_PATTERN.search(path):
            label = rule["label"] if rule else "other"
            _capture_url(flow, label)
            ctx.log.info(f"[Runtime] 捕获 Figma 英文语言包 URL ({label}): {flow.request.pretty_url}")

        if not rule:
            return

        if rule["remote_url"]:
            old_url = flow.request.pretty_url
            flow.request.url = rule["remote_url"]
            ctx.log.info(f"[Runtime] 已改写 Figma {rule['label']} 语言包请求: {old_url} -> {rule['remote_url']}")
            return

        label = rule["label"]
        if label not in self.lang_bytes:
            try:
                self.lang_bytes[label] = _load_lang_bytes(rule["file"])
            except Exception as exc:
                ctx.log.error(f"[Runtime] 命中 {label} 语言包请求，但中文包不可用: {exc}")
                return

        flow.response = http.Response.make(
            200,
            self.lang_bytes[label],
            {
                "content-type": "application/json; charset=utf-8",
                "cache-control": "no-store",
                "access-control-allow-origin": "*",
            },
        )
        ctx.log.info(f"[Runtime] 已替换 Figma {label} 语言包: {flow.request.pretty_url}")


addons = [LocalFigmaLanguagePack()]
