#!/usr/bin/env python3
"""
Export the DQD Shiny dashboard as a single self-contained HTML file.

Usage:
    python3 scripts/export_dashboard.py
    python3 scripts/export_dashboard.py --json dqd_results/dqd_results.json --out dashboard.html
"""

import argparse
import base64
import json
import re
import urllib.request
from pathlib import Path

# ── Defaults ────────────────────────────────────────────────────────────────
DEFAULT_JSON   = Path("dqd_results/dqd_results.json")
DEFAULT_OUT    = Path("dqd_results/dqd_dashboard.html")
JQUERY_URL     = "https://code.jquery.com/jquery-3.6.0.min.js"

def find_www() -> Path:
    """Locate the DQD Shiny www directory from the installed R package."""
    import subprocess
    result = subprocess.run(
        ["Rscript", "-e",
         "cat(system.file('shinyApps/www', package='DataQualityDashboard'))"],
        capture_output=True, text=True
    )
    path = result.stdout.strip()
    if not path or not Path(path).exists():
        raise RuntimeError(
            "Could not find DataQualityDashboard www directory. "
            "Is the package installed? Run: remotes::install_github('OHDSI/DataQualityDashboard')"
        )
    return Path(path)


def read(path: Path) -> str:
    return path.read_bytes().decode("utf-8", errors="replace")


def build(json_path: Path, out_path: Path) -> None:
    www = find_www()
    print(f"DQD www: {www}")
    print(f"JSON:    {json_path}")
    print(f"Output:  {out_path}")
    print()

    # Download jQuery
    print("Downloading jQuery...")
    with urllib.request.urlopen(JQUERY_URL) as r:
        jquery_js = r.read().decode("utf-8", errors="replace")

    html = read(www / "index.html")

    # Inject jQuery first so all subsequent scripts can use $
    html = html.replace("<head>", f"<head>\n<script>{jquery_js}</script>")

    # Remove loadResults.js from <head> — we add it last after all deps
    loadresults = read(www / "js/loadResults.js")
    html = html.replace('<script src="js/loadResults.js"></script>', "")

    # Inline all <script src> tags
    for match in re.findall(r'<script(?:\s+type="text/javascript")?\s+src="([^"]+)"></script>', html):
        try:
            content = read(www / match)
            for tag in [
                f'<script src="{match}"></script>',
                f'<script type="text/javascript" src="{match}"></script>',
            ]:
                if tag in html:
                    html = html.replace(tag, f"<script>{content}</script>", 1)
                    break
            print(f"  JS : {match}")
        except Exception as e:
            print(f"  JS (skip): {match} — {e}")

    # Inline all <link> CSS
    for match in re.findall(r'<link[^>]+href="([^"]+\.css)"[^>]*/?>',  html):
        try:
            content = read(www / match)
            html = re.sub(
                r'<link[^>]+href="' + re.escape(match) + r'"[^>]*/?>',
                f"<style>{content}</style>",
                html,
            )
            print(f"  CSS: {match}")
        except Exception as e:
            print(f"  CSS (skip): {match} — {e}")

    # Inline images as base64 data URIs
    for match in re.findall(r'src="(img/[^"]+)"', html):
        try:
            data = (www / match).read_bytes()
            ext  = match.rsplit(".", 1)[-1]
            b64  = base64.b64encode(data).decode()
            html = html.replace(f'src="{match}"', f'src="data:image/{ext};base64,{b64}"')
            print(f"  IMG: {match}")
        except Exception as e:
            print(f"  IMG (skip): {match} — {e}")

    # Remove the Shiny ajax loader block (only runs under a server)
    html = re.sub(r"if \(location\.port.*?}\s*\}", "", html, flags=re.DOTALL)

    # Inject loadResults + JSON data just before </body>
    json_data = read(json_path)
    injection = (
        f"\n<script>{loadresults}</script>\n"
        f"<script>\n"
        f"  var defined_results = {json_data};\n"
        f"  $(document).ready(function() {{\n"
        f"    loadResults(defined_results);\n"
        f"  }});\n"
        f"</script>\n"
    )
    html = html.replace("</body>", injection + "</body>")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")
    size_mb = len(html) / 1_000_000
    print(f"\n✅  Done — {out_path}  ({size_mb:.1f} MB)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export DQD dashboard as standalone HTML.")
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON,
                        help=f"Path to DQD results JSON (default: {DEFAULT_JSON})")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"Output HTML path (default: {DEFAULT_OUT})")
    args = parser.parse_args()

    if not args.json.exists():
        raise FileNotFoundError(f"JSON not found: {args.json}")

    build(args.json, args.out)
