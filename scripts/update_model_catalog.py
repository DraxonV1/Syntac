"""Refresh offline model metadata; live provider discovery remains authoritative."""
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

SOURCE = "https://models.dev/api.json"
ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "assets/models/models.dev.api.json"
PROVENANCE = ROOT / "assets/models/catalog-source.json"


def main():
    request = Request(SOURCE, headers={"User-Agent": "Mozilla/5.0 Syntac-Catalog/1.0"})
    with urlopen(request, timeout=60) as response:
        raw = response.read(32 * 1024 * 1024 + 1)
    if len(raw) > 32 * 1024 * 1024:
        raise ValueError("Catalog exceeds download limit")
    data = json.loads(raw)
    for provider in ("openai", "google", "anthropic", "deepseek", "openrouter", "xai"):
        if not isinstance(data.get(provider, {}).get("models"), dict):
            raise ValueError(f"Missing provider models: {provider}")
    # Keep upstream snapshot verbatim. Compatibility patches live in Dart policy.
    temporary = TARGET.with_suffix(".tmp")
    temporary.write_bytes(raw)
    temporary.replace(TARGET)
    provenance = {
        "source": SOURCE,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
        "ompReference": "e24466515dae616f4027170027245c6222f28ab2",
        "deepSeekPolicySource": "https://api-docs.deepseek.com/guides/thinking_mode",
    }
    PROVENANCE.write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(provenance))


if __name__ == "__main__":
    main()
