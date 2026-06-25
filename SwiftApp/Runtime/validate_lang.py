import json
import sys
from pathlib import Path


DEFAULT_LANG_FILE = Path(__file__).resolve().parent / "lang" / "zh.json"


def main() -> int:
    lang_file = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_LANG_FILE

    if not lang_file.exists():
        print(f"FAIL: language pack not found: {lang_file}")
        return 1

    try:
        data = json.loads(lang_file.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"FAIL: invalid JSON: {exc}")
        return 1

    if not isinstance(data, dict):
        print("FAIL: language pack root must be a JSON object")
        return 1

    bad = []
    for key, value in data.items():
        if not isinstance(value, dict) or not isinstance(value.get("string"), str):
            bad.append(key)
            if len(bad) >= 10:
                break

    print(f"OK: {lang_file}")
    print(f"keys: {len(data)}")

    if bad:
        print("WARN: some entries do not look like {'string': '...'}")
        for key in bad:
            print(f"  - {key}")

    if len(data) < 1000:
        print("WARN: key count is lower than expected for Figma's main language pack")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
