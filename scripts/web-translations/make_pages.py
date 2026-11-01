#!/usr/bin/env python3
"""Builds docs/<lang>/privacy.html and docs/<lang>/support.html from web_<code>.py.

Run it after editing the English docs/privacy.html or docs/help/support.html,
once the translations have been brought in line:

    python3 scripts/web-translations/make_pages.py

Each web_<code>.py defines D, a dict of the translated text. Button labels that
the app itself shows ({more}, {sync}, ...) are taken from Localizable.xcstrings
so the page says exactly what the screen says.
"""
import json, os, sys, importlib, re

S = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(S))
sys.path.insert(0, S)
BASE = "https://amouraux.github.io/DayHand"

# folder -> (hreflang, catalogue code, name in its own language)
LANGS = [
    ("de", "de", "de", "Deutsch"),
    ("es", "es", "es", "Español"),
    ("fr", "fr", "fr", "Français"),
    ("it", "it", "it", "Italiano"),
    ("nl", "nl", "nl", "Nederlands"),
    ("pt-pt", "pt-PT", "pt-PT", "Português (Portugal)"),
    ("pt-br", "pt-BR", "pt-BR", "Português (Brasil)"),
    ("ja", "ja", "ja", "日本語"),
    ("ko", "ko", "ko", "한국어"),
    ("sv", "sv", "sv", "Svenska"),
    ("da", "da", "da", "Dansk"),
    ("nb", "nb", "nb", "Norsk bokmål"),
    ("fi", "fi", "fi", "Suomi"),
    ("pl", "pl", "pl", "Polski"),
]
PAGES = ("privacy", "support")

cat = json.load(open(f"{ROOT}/DayHand/Localizable.xcstrings"))["strings"]
LABELS = {
    "more": "More", "sync": "Sync", "stop": "Stop Using This File", "tasks": "Tasks",
    "export": "Export as CSV…", "backups": "Backups", "timeline": "Timeline",
    "notes": "Notes", "merge": "Merge", "existing": "Use Existing Sync File…",
}


def labels(code):
    out = {}
    for k, key in LABELS.items():
        v = cat[key]["localizations"][code]["stringUnit"]["value"]
        out[k] = "<strong>" + v.rstrip("…").strip() + "</strong>"
    return out


def alternates(page):
    rows = [f'<link rel="alternate" hreflang="en" href="{BASE}/{"privacy" if page=="privacy" else "help/support"}.html">']
    for folder, hl, _, _ in LANGS:
        rows.append(f'<link rel="alternate" hreflang="{hl}" href="{BASE}/{folder}/{page}.html">')
    rows.append(f'<link rel="alternate" hreflang="x-default" href="{BASE}/{"privacy" if page=="privacy" else "help/support"}.html">')
    return "\n".join(rows)


def switcher(page, current, label, rel):
    """rel: path prefix from the page to docs/ ('../' for a translation, '' or '../' for English)."""
    items = []
    en_href = (rel + "privacy.html") if page == "privacy" else (rel + "help/support.html")
    items.append("English" if current == "en" else f'<a href="{en_href}" hreflang="en" lang="en">English</a>')
    for folder, hl, _, name in LANGS:
        if folder == current:
            items.append(name)
        else:
            items.append(f'<a href="{rel}{folder}/{page}.html" hreflang="{hl}" lang="{hl}">{name}</a>')
    return f'<nav class="langs" aria-label="{label}">' + " · ".join(items) + "</nav>"


def p(x):
    return f"<p>{x}</p>"


def privacy(code, D, tok):
    T = lambda s: s.format(**tok)
    P = D["P"]
    h2 = D["h2"]
    ids = ["overview", "storage", "sync", "imports", "notifications", "purchases", "choices", "support", "website"]
    nav = "".join(f'<a href="#{i}">{n}</a>' for i, n in zip(ids, D["nav"]))
    body = []
    def sec(i, title, blocks):
        body.append(f'<h2 id="{i}">{title}</h2>' if i else f"<h2>{title}</h2>")
        for b in blocks:
            body.append(b)
    sec("overview", h2[0], [p(T(P["O1"])), p(T(P["O2"]))])
    sec("storage", h2[1], [p(T(P["S1"])), p(T(P["S2"])), p(T(P["S3"]))])
    sec("sync", h2[2], [p(T(P["Y1"])), p(T(P["Y2"]).replace("<apple>", '<a href="https://www.apple.com/legal/privacy/">').replace("</apple>", "</a>"))])
    sec("imports", h2[3], [p(T(P["I1"])), p(T(P["I2"]))])
    sec("notifications", h2[4], [p(T(P["N1"]))])
    sec("purchases", h2[5], [p(T(P["P1"])), p(T(P["P2"]))])
    ul = "<ul>\n" + "\n".join(f"<li>{T(c)}</li>" for c in P["C"]) + "\n</ul>"
    sec("choices", h2[6], [ul, p(T(P["C7"])), p(T(P["C8"]))])
    sup = T(P["U1"]).replace("<s>", '<a href="../help/support.html#contact">').replace("</s>", "</a>")
    sec("support", h2[7], [p(sup), p(T(P["U2"])), p(T(P["U3"]))])
    web = (T(P["W1"]).replace("<g>", '<a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">').replace("</g>", "</a>")
           .replace("<apple>", '<a href="https://www.apple.com/legal/privacy/">').replace("</apple>", "</a>"))
    sec("website", h2[8], [p(web)])
    sec(None, h2[9], [p(T(P["CHG"]))])
    note = D["note"].replace("<en>", '<a href="../privacy.html" hreflang="en" lang="en">').replace("</en>", "</a>")
    f = D["footer"]
    return f'''<!doctype html>
<html lang="{D["html_lang"]}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{D["title"]}</title>
<meta name="description" content="{D["desc"]}">
<link rel="icon" href="../icon.png">
<link rel="stylesheet" href="../help/help.css">
<link rel="canonical" href="{BASE}/{code}/privacy.html">
{alternates("privacy")}
</head>
<body>
<a class="skip" href="#main">{D["skip"]}</a>
<header><a class="brand" href="../index.html"><img src="../icon.png" alt="" width="36" height="36">DayHand</a><a href="../help/" hreflang="en" lang="en">Help</a></header>
<div class="layout">
<nav aria-label="{D["nav_aria"]}">
{nav}
</nav>
<main id="main">
<p class="eyebrow">{D["eyebrow"]}</p>
<h1>{D["h1"]}</h1>
<p class="lead">{D["lead"]}</p>
{chr(10).join(body)}
<p>{note}</p>
{switcher("privacy", code, D["langs_label"], "../")}
<footer><a href="../help/" hreflang="en" lang="en">{f[0]}</a> · <a href="support.html">{f[1]}</a> · <a href="../index.html">{f[2]}</a></footer>
</main></div>
</body></html>
'''


def support(code, D, tok):
    T = lambda s: s.format(**tok)
    S_ = D["S"]
    en = D["en_mark"]
    def lk(href, text):
        return f'<a href="{href}" hreflang="en" lang="en">{text}</a> {en}'
    def fill(s):
        s = T(s)
        s = s.replace("<sync>", f'<a href="../help/sync.html#troubleshooting" hreflang="en" lang="en">').replace("</sync>", f'</a> {en}')
        s = s.replace("<col>", f'<a href="../help/tasks-and-dates.html#colours" hreflang="en" lang="en">').replace("</col>", f'</a> {en}')
        s = s.replace("<imp>", f'<a href="../help/data.html" hreflang="en" lang="en">').replace("</imp>", f'</a> {en}')
        s = s.replace("<new>", '<a href="https://github.com/amouraux/DayHand/issues/new">').replace("</new>", "</a>")
        s = s.replace("<all>", '<a href="https://github.com/amouraux/DayHand/issues">').replace("</all>", "</a>")
        return s
    ul1 = "<ul>\n" + "\n".join(f"<li>{fill(x)}</li>" for x in S_["N"]) + "\n</ul>"
    ul2 = "<ul>\n" + "\n".join(f"<li>{fill(x)}</li>" for x in S_["T"]) + "\n</ul>"
    nav = "".join(f'<a href="#{i}">{n}</a>' for i, n in zip(["missing-tasks", "notifications", "contact"], D["nav"]))
    nav += f'<a href="privacy.html">{D["nav_privacy"]}</a>'
    f = D["footer"]
    return f'''<!doctype html>
<html lang="{D["html_lang"]}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{D["title"]}</title>
<meta name="description" content="{D["desc"]}">
<link rel="icon" href="../icon.png">
<link rel="stylesheet" href="../help/help.css">
<link rel="canonical" href="{BASE}/{code}/support.html">
{alternates("support")}
</head>
<body>
<a class="skip" href="#main">{D["skip"]}</a>
<header><a class="brand" href="../index.html"><img src="../icon.png" alt="" width="36" height="36">DayHand</a><a href="../help/" hreflang="en" lang="en">Help</a></header>
<div class="layout">
<nav aria-label="{D["nav_aria"]}">{nav}</nav>
<main id="main">
<p class="eyebrow">{D["eyebrow"]}</p>
<h1>{D["h1"]}</h1>
<p class="lead">{D["lead"]}</p>
<h2 id="missing-tasks">{D["h2"][0]}</h2>
{p(fill(S_["M1"]))}
{p(fill(S_["M2"]))}
<h2 id="notifications">{D["h2"][1]}</h2>
{ul1}
{p(fill(S_["N_after"]))}
<h2>{D["h2"][2]}</h2>
{p(fill(S_["X1"]))}
<h2 id="contact">{D["h2"][3]}</h2>
{p(fill(S_["C1"]))}
{p(fill(S_["C2"]))}
{ul2}
<aside>{fill(S_["aside"])}</aside>
{p(fill(S_["C3"]))}
<p>{D["note"].replace("<en>", '<a href="../help/support.html" hreflang="en" lang="en">').replace("</en>", "</a>")}</p>
{switcher("support", code, D["langs_label"], "../")}
<footer>{D["footer_text"]}<br>
<a href="support.html">{f[0]}</a> · <a href="privacy.html">{f[1]}</a> · <a href="../index.html">{f[2]}</a></footer>
</main>
</div>
</body></html>
'''


def patch_english():
    """Adds the alternates and the language list to the English pages, once."""
    css = f"{ROOT}/docs/help/help.css"
    c = open(css).read()
    if ".langs" not in c:
        open(css, "a").write("\n.langs{font-size:.9rem;margin:1.6rem 0 .4rem;line-height:1.9}\n.langs a{white-space:nowrap}\n")
    for page, path, rel in (("privacy", f"{ROOT}/docs/privacy.html", ""), ("support", f"{ROOT}/docs/help/support.html", "../")):
        s = open(path).read()
        s = re.sub(r'<link rel="alternate"[^\n]*\n', "", s)
        s = re.sub(r'<nav class="langs".*?</nav>\n?', "", s, flags=re.S)
        s = s.replace("</head>", alternates(page) + "\n</head>", 1)
        s = s.replace("<footer>", switcher(page, "en", "Languages", rel) + "\n<footer>", 1)
        open(path, "w").write(s)


if __name__ == "__main__":
    only = sys.argv[1:]
    for folder, hl, ccode, name in LANGS:
        if only and folder not in only:
            continue
        mod = importlib.import_module("web_" + folder.replace("-", "_"))
        tok = labels(ccode)
        os.makedirs(f"{ROOT}/docs/{folder}", exist_ok=True)
        open(f"{ROOT}/docs/{folder}/privacy.html", "w").write(privacy(folder, mod.PRIVACY, tok))
        open(f"{ROOT}/docs/{folder}/support.html", "w").write(support(folder, mod.SUPPORT, tok))
        print("wrote", folder)
    if not only:
        patch_english()
        print("patched English")
