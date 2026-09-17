"""Retry Supabase uploads for filenames with non-ASCII / special characters."""
from __future__ import annotations

import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / ".env"
ASSETS = ROOT / "assets"
EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}


def read_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip().strip('"').strip("'")
    return out


def main() -> None:
    env = read_env(ENV_PATH)
    base = env["SUPABASE_URL"].rstrip("/")
    key = env["SUPABASE_SERVICE_ROLE_KEY"]
    bucket = env.get("SUPABASE_BUCKET", "tourist-images")

    special: list[Path] = []
    for path in ASSETS.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in EXTS:
            continue
        rel = path.relative_to(ASSETS).as_posix()
        if any(ord(ch) > 127 for ch in rel) or "Zipline" in rel:
            special.append(path)

    print(f"Retrying {len(special)} special-character files...")
    ok = 0
    fail = 0
    for path in special:
        rel = path.relative_to(ASSETS).as_posix()
        encoded = "/".join(urllib.parse.quote(seg, safe="") for seg in rel.split("/"))
        endpoint = f"{base}/storage/v1/object/{bucket}/{encoded}"
        data = path.read_bytes()
        ext = path.suffix.lower().lstrip(".")
        content_type = {
            "png": "image/png",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "webp": "image/webp",
            "gif": "image/gif",
            "bmp": "image/bmp",
        }.get(ext, "application/octet-stream")
        req = urllib.request.Request(
            endpoint,
            data=data,
            method="POST",
            headers={
                "Authorization": f"Bearer {key}",
                "apikey": key,
                "x-upsert": "true",
                "Content-Type": content_type,
            },
        )
        try:
            with urllib.request.urlopen(req) as resp:
                resp.read()
            ok += 1
            print(f"OK {rel}")
        except urllib.error.HTTPError as exc:
            fail += 1
            body = exc.read().decode("utf-8", "replace")
            print(f"FAIL {rel} HTTP {exc.code}: {body[:400]}")
        except Exception as exc:  # noqa: BLE001
            fail += 1
            print(f"FAIL {rel}: {exc}")

    print(f"done ok={ok} fail={fail}")


if __name__ == "__main__":
    main()
