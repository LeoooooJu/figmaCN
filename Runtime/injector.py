import json
import os
import re
from datetime import datetime
from pathlib import Path

from mitmproxy import ctx, http


BASE_DIR = Path(__file__).resolve().parent
LANG_FILE = Path(os.environ.get("FigmaCN_LANG_FILE", BASE_DIR / "lang" / "zh.json"))
REMOTE_LANG_URL = os.environ.get("FigmaCN_LANG_URL", "").strip()
CAPTURE_FILE = BASE_DIR / "latest" / "captured_language_urls.txt"

FIGMA_LANG_PATTERN = re.compile(
    r"^/webpack-artifacts/assets/"
    r"figma_app(?:_beta|__react_profile)?(?:__rspack)?-[a-f0-9]+\.min\.en\.json(?:\.br)?$"
)

ANY_FIGMA_EN_JSON_PATTERN = re.compile(
    r"/webpack-artifacts/assets/[^/?#]+\.min\.en\.json(?:\.br)?$"
)


def _is_enabled() -> bool:
    raw = os.environ.get("FigmaCN_ENABLE_LOCALIZATION", "1").strip().lower()
    return raw not in {"0", "false", "no", "off"}


def _load_lang_bytes() -> bytes:
    data = LANG_FILE.read_bytes()
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
        self.lang_bytes = None
        self.enabled = _is_enabled()

    def load(self, loader):
        if not self.enabled:
            ctx.log.info("[Runtime] 中文包替换已禁用: FigmaCN_ENABLE_LOCALIZATION=0")
            return

        if REMOTE_LANG_URL:
            ctx.log.info(f"[Runtime] 远程中文包模式已启用: {REMOTE_LANG_URL}")
            return

        try:
            self.lang_bytes = _load_lang_bytes()
            ctx.log.info(f"[Runtime] 中文包已加载: {LANG_FILE} ({len(self.lang_bytes)} bytes)")
        except Exception as exc:
            ctx.log.error(f"[Runtime] 中文包加载失败: {LANG_FILE}: {exc}")

    def request(self, flow: http.HTTPFlow) -> None:
        if not self.enabled:
            return

        host = (flow.request.host or "").lower()
        path = flow.request.path or ""

        if host != "www.figma.com":
            return

        if ANY_FIGMA_EN_JSON_PATTERN.search(path):
            label = "main" if FIGMA_LANG_PATTERN.match(path) else "other"
            _capture_url(flow, label)
            ctx.log.info(f"[Runtime] 捕获 Figma 英文语言包 URL ({label}): {flow.request.pretty_url}")

        if not FIGMA_LANG_PATTERN.match(path):
            return

        if REMOTE_LANG_URL:
            old_url = flow.request.pretty_url
            flow.request.url = REMOTE_LANG_URL
            ctx.log.info(f"[Runtime] 已改写 Figma 语言包请求: {old_url} -> {REMOTE_LANG_URL}")
            return

        if self.lang_bytes is None:
            try:
                self.lang_bytes = _load_lang_bytes()
            except Exception as exc:
                ctx.log.error(f"[Runtime] 命中语言包请求，但中文包不可用: {exc}")
                return

        flow.response = http.Response.make(
            200,
            self.lang_bytes,
            {
                "content-type": "application/json; charset=utf-8",
                "cache-control": "no-store",
                "access-control-allow-origin": "*",
            },
        )
        ctx.log.info(f"[Runtime] 已替换 Figma 语言包: {flow.request.pretty_url}")


addons = [LocalFigmaLanguagePack()]
