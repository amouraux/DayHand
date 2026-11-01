#!/usr/bin/env python3
"""Builds docs/<lang>/index.html, the homepage in every app language.

docs/index.html stays the one source of structure and styling. Its text is cut
into the units listed in home_units.py, each replaced by a placeholder and
filled from home_<code>.py. Stack names ("Inbox", "Now", ...) and the labels of
buttons the app shows come from Localizable.xcstrings, so the page says what
the screen says.

    python3 scripts/web-translations/make_home.py

It also keeps the language menu, the hreflang links and the banner script on
the English page current. If the English text no longer matches a unit, it
stops and names the unit.
"""
import json, os, re, sys, importlib

S = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(S))
sys.path.insert(0, S)
from make_pages import LANGS, BASE  # noqa: E402
from home_units import UNITS, STACKS  # noqa: E402

INDEX = f"{ROOT}/docs/index.html"
cat = json.load(open(f"{ROOT}/DayHand/Localizable.xcstrings"))["strings"]

CSS = """/*langmenu*/
  .langmenu { position: absolute; top: 14px; right: 16px; z-index: 5; font-size: 14px; text-align: left; }
  .langmenu summary { list-style: none; cursor: pointer; background: var(--panel); color: var(--ink-soft);
    border: 1px solid var(--line); border-radius: 999px; padding: 6px 14px; box-shadow: var(--shadow); }
  .langmenu summary::-webkit-details-marker { display: none; }
  .langmenu summary::after { content: " \\25BE"; }
  .langmenu[open] summary::after { content: " \\25B4"; }
  .langmenu .langlist { position: absolute; right: 0; margin-top: 8px; min-width: 210px; max-height: 70vh; overflow-y: auto;
    background: var(--panel); border: 1px solid var(--line); border-radius: 14px; box-shadow: var(--shadow); padding: 6px; }
  .langmenu .langlist a, .langmenu .langlist span { display: block; padding: 7px 12px; border-radius: 9px; text-decoration: none; color: var(--ink); }
  .langmenu .langlist a:hover { background: var(--bg); }
  .langmenu .langlist span[aria-current] { background: var(--bg); font-weight: 650; }
  body > .langbar { display: flex; gap: 14px; align-items: center; justify-content: space-between; max-width: 720px;
    margin: 14px auto 0; padding: 12px 16px; background: var(--panel); border: 1px solid var(--line);
    border-radius: 12px; box-shadow: var(--shadow); font-size: 15px; }
  body > .langbar p { margin: 0; }
  body > .langbar button { flex: none; background: none; border: 0; color: var(--ink-soft); font: inherit; font-size: 22px;
    line-height: 1; padding: 4px 8px; cursor: pointer; }
  /*/langmenu*/"""


def catalog(code, key):
    return cat[key]["localizations"][code]["stringUnit"]["value"]


def collapse(s):
    return re.sub(r"\s+", " ", s).strip()


def pattern(eng):
    words = collapse(eng).split(" ")
    return r"(?<=>)\s*" + r"\s+".join(re.escape(w) for w in words) + r"\s*(?=<)"


def menu(current, rel):
    items = []
    en = "index.html" if rel == "" else rel + "index.html"
    items.append('<span aria-current="page" lang="en">English</span>' if current == "en" else f'<a href="{en}" hreflang="en" lang="en">English</a>')
    for folder, hl, _, name in LANGS:
        if folder == current:
            items.append(f'<span aria-current="page" lang="{hl}">{name}</span>')
        else:
            items.append(f'<a href="{rel}{folder}/index.html" hreflang="{hl}" lang="{hl}">{name}</a>')
    return "<!--langmenu--><details class=\"langmenu\"><summary>{label}</summary><div class=\"langlist\">" + "".join(items) + "</div></details><!--/langmenu-->"


def alternates():
    rows = [f'<link rel="alternate" hreflang="en" href="{BASE}/">']
    for folder, hl, _, _ in LANGS:
        rows.append(f'<link rel="alternate" hreflang="{hl}" href="{BASE}/{folder}/">')
    rows.append(f'<link rel="alternate" hreflang="x-default" href="{BASE}/">')
    return "<!--alt-->\n" + "\n".join(rows) + "\n<!--/alt-->"


def privacy_line(label, rel, current):
    links = []
    en = "privacy.html" if rel == "" else rel + "privacy.html"
    links.append(f'<a href="{en}" hreflang="en" lang="en">English</a>')
    for folder, hl, _, name in LANGS:
        links.append(f'<a href="{rel}{folder}/privacy.html" hreflang="{hl}" lang="{hl}">{name}</a>')
    return f"<!--privacy--><p>{label}: " + " · ".join(links) + "</p><!--/privacy-->"


def strip_generated(html):
    html = re.sub(r"<!--langmenu-->.*?<!--/langmenu-->", "", html, flags=re.S)
    html = re.sub(r"/\*langmenu\*/.*?/\*/langmenu\*/", "", html, flags=re.S)
    html = re.sub(r"<!--alt-->.*?<!--/alt-->\n?", "", html, flags=re.S)
    html = re.sub(r"<!--privacy-->.*?<!--/privacy-->", "@@privacy@@", html, flags=re.S)
    html = re.sub(r"<p>Privacy policy: .*?</p>", "@@privacy@@", html, flags=re.S)
    html = re.sub(r'<script src="lang\.js"[^>]*></script>\n?', "", html)
    return html


def patch_english():
    html = strip_generated(open(INDEX).read())
    html = html.replace("</style>", "  " + CSS + "\n</style>", 1)
    html = html.replace("</head>", alternates() + "\n</head>", 1)
    html = html.replace('<header class="wrap">', '<header class="wrap">\n  ' + menu("en", "").format(label="Languages"), 1)
    html = html.replace("@@privacy@@", privacy_line("Privacy policy", "", "en"))
    html = html.replace("</body>", '<script src="lang.js" data-page="home" defer></script>\n</body>', 1)
    open(INDEX, "w").write(html)


def template():
    html = strip_generated(open(INDEX).read())
    for eng, key in STACKS:
        html, n = re.subn(pattern(eng), f"@@{key}@@", html)
        if not n:
            sys.exit(f"stack name {eng!r} no longer appears in docs/index.html")
    for key, eng in UNITS:
        html, n = re.subn(pattern(eng), f"@@{key}@@", html)
        if not n:
            sys.exit(f"unit {key!r} no longer matches docs/index.html:\n  {eng[:90]}")
    # Whatever English is left over is a unit nobody wrote down.
    body = re.sub(r"<(style|script)\b.*?</\1>", "", html, flags=re.S | re.I)
    body = body[body.index("<body"):]
    for t in re.findall(r">([^<>]+)<", body):
        t = t.strip()
        if re.search(r"[A-Za-z]{2,}", t) and not t.startswith("@@") and t != "DayHand":
            sys.exit(f"untranslated text left in docs/index.html: {t[:90]!r}")
    return html


def build(folder, hl, ccode, name, tmpl):
    mod = importlib.import_module("home_" + folder.replace("-", "_"))
    H, M = mod.H, mod.META
    tok = {k: catalog(ccode, e) for e, k in STACKS}
    tok["more"] = catalog(ccode, "More")
    tok["existing"] = catalog(ccode, "Use Existing Sync File…").rstrip("…").strip()
    html = tmpl
    missing = [k for k, _ in UNITS if k not in H]
    if missing:
        sys.exit(f"{folder}: missing units {missing[:5]}")
    for _, k in STACKS:
        html = html.replace(f"@@{k}@@", tok[k])
    for k, _ in UNITS:
        html = html.replace(f"@@{k}@@", H[k].format(**tok))
    # head
    html = html.replace('<html lang="en">', f'<html lang="{M["html_lang"]}">', 1)
    html = re.sub(r"<title>.*?</title>", f"<title>{M['title']}</title>", html, count=1, flags=re.S)
    html = re.sub(r'(<meta name="description" content=")[^"]*"', lambda m: m.group(1) + M["desc"] + '"', html, count=1)
    html = re.sub(r'(<meta property="og:title" content=")[^"]*"', lambda m: m.group(1) + M["title"] + '"', html, count=1)
    html = re.sub(r'(<meta property="og:description" content=")[^"]*"', lambda m: m.group(1) + M["og_desc"] + '"', html, count=1)
    html = html.replace('content="https://amouraux.github.io/DayHand/"', f'content="{BASE}/{folder}/"')
    html = html.replace('<link rel="canonical" href="https://amouraux.github.io/DayHand/">', f'<link rel="canonical" href="{BASE}/{folder}/">')
    html = re.sub(r'(<img src="screenshots/iphone\.png" alt=")[^"]*"', lambda m: m.group(1) + M["alt_iphone"] + '"', html)
    html = re.sub(r'(<img src="screenshots/ipad\.png" alt=")[^"]*"', lambda m: m.group(1) + M["alt_ipad"] + '"', html)
    # paths: the page lives one folder down; help becomes the translated support page
    html = html.replace('href="help/"', 'href="support.html"')
    html = html.replace('href="icon.png"', 'href="../icon.png"').replace('src="icon.png"', 'src="../icon.png"')
    html = html.replace('src="screenshots/', 'src="../screenshots/')
    # generated pieces
    html = html.replace("</style>", "  " + CSS + "\n</style>", 1)
    html = html.replace("</head>", alternates() + "\n</head>", 1)
    html = html.replace('<header class="wrap">', '<header class="wrap">\n  ' + menu(folder, "../").format(label=M["langs_label"]), 1)
    html = html.replace("@@privacy@@", privacy_line(M["privacy_label"], "../", folder))
    return html


def main():
    patch_english()
    tmpl = template()
    only = sys.argv[1:]
    for folder, hl, ccode, name in LANGS:
        if only and folder not in only:
            continue
        out = build(folder, hl, ccode, name, tmpl)
        os.makedirs(f"{ROOT}/docs/{folder}", exist_ok=True)
        open(f"{ROOT}/docs/{folder}/index.html", "w").write(out)
        print("wrote", folder)


if __name__ == "__main__":
    main()
