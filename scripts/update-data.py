#!/usr/bin/env python3
"""Rebuild the bundled catalog from pinned Omarchy and Unicode CLDR data."""
import json
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent.parent
OMARCHY = "https://raw.githubusercontent.com/omacom/omarchy/v4.5.0/"
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr-json/48.0.0/"


def download(url):
    with urlopen(url, timeout=30) as response:
        return response.read(5_000_001).decode()


def main():
    source = json.loads(download(OMARCHY + "shell/plugins/emojis/emojis.json"))
    annotations = {}
    for kind in ["annotations", "annotationsDerived"]:
        package = "cldr-annotations-derived-full" if kind == "annotationsDerived" else "cldr-annotations-full"
        data = json.loads(download(CLDR + f"cldr-json/{package}/{kind}/en/annotations.json"))
        annotations.update(data[kind]["annotations"])
    # CLDR omits the optional emoji presentation selector in its lookup keys.
    names = {key.replace("\ufe0f", ""): value for key, value in annotations.items()}
    catalog = []
    for item in source:
        annotation = names.get(item["e"].replace("\ufe0f", ""), {})
        name = annotation.get("tts", [item["k"].replace("_", " ")])[0]
        keywords = " ".join(dict.fromkeys([item["k"], *annotation.get("default", [])]))
        catalog.append({"e": item["e"], "n": name, "k": keywords})
    (ROOT / "emojis.json").write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")) + "\n")
    (ROOT / "LICENSE-OMARCHY").write_text(download(OMARCHY + "LICENSE"))
    (ROOT / "LICENSE-UNICODE").write_text(download(CLDR + "LICENSE"))
    print(f"Wrote {len(catalog)} emoji")


if __name__ == "__main__":
    main()
