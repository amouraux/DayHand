#!/usr/bin/env python3
"""Builds the translated privacy policies and help pages, and keeps the English
ones in step: docs/<lang>/privacy.html, docs/<lang>/help.html.

The site has three pages — the homepage, Help and Privacy — and each carries the
same language menu in its top right corner. The English privacy page is
docs/privacy.html and the English help page is docs/help/index.html (one page:
how to use the app, troubleshooting, contact); both are written by hand. Run
this after editing either of them, once the translations have been brought in
line:

    python3 scripts/web-translations/make_pages.py

Each web_<code>.py defines PRIVACY and SUPPORT, dicts of the translated text
(SUPPORT is the translated troubleshooting and contact; the how-to guides are
English only, and the translated help page says so). Button labels that the app
itself shows ({more}, {sync}, ...) are taken from Localizable.xcstrings, so the
page says exactly what the screen says.
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

cat = json.load(open(f"{ROOT}/DayHand/Localizable.xcstrings"))["strings"]
LABELS = {
    "more": "More", "sync": "Sync", "stop": "Stop Using This File", "tasks": "Tasks",
    "export": "Export as CSV…", "backups": "Backups", "timeline": "Timeline",
    "notes": "Notes", "merge": "Merge", "existing": "Use Existing Sync File…",
}

# The translated help page has no how-to guides of its own; it points at the
# English ones. (nav label, note with <g>link</g>)
GUIDES = {
    "de": ("Anleitungen (Englisch)", "Die Anleitungen zur Nutzung von DayHand – erste Schritte, Stapel und Termine, Durchsichten, Sync, Importe und Backups, Gratis und Bezahlt – gibt es nur auf Englisch: <g>Anleitungen öffnen</g>."),
    "es": ("Guías (en inglés)", "Las guías para usar DayHand —primeros pasos, pilas y fechas, revisiones, sincronización, importaciones y copias de seguridad, gratis y de pago— solo están en inglés: <g>abrir las guías</g>."),
    "fr": ("Guides (en anglais)", "Les guides d’utilisation de DayHand — premiers pas, piles et dates, revues, synchronisation, importations et sauvegardes, gratuit et payant — n’existent qu’en anglais : <g>ouvrir les guides</g>."),
    "it": ("Guide (in inglese)", "Le guide per usare DayHand — primi passi, stack e date, revisioni, sincronizzazione, importazioni e backup, gratuito e a pagamento — sono disponibili solo in inglese: <g>apri le guide</g>."),
    "nl": ("Gidsen (Engels)", "De gidsen over het gebruik van DayHand — aan de slag, stapels en data, reviews, synchronisatie, imports en back-ups, gratis en betaald — zijn alleen in het Engels beschikbaar: <g>open de gidsen</g>."),
    "pt-pt": ("Guias (em inglês)", "Os guias de utilização do DayHand — primeiros passos, pilhas e datas, revisões, sincronização, importações e cópias de segurança, gratuito e pago — só existem em inglês: <g>abrir os guias</g>."),
    "pt-br": ("Guias (em inglês)", "Os guias de uso do DayHand — primeiros passos, pilhas e datas, revisões, sincronização, importações e backups, grátis e pago — só existem em inglês: <g>abrir os guias</g>."),
    "ja": ("ガイド（英語）", "DayHandの使い方のガイド（はじめに、スタックと日付、レビュー、同期、読み込みとバックアップ、無料と有料）は英語のみです: <g>ガイドを開く</g>。"),
    "ko": ("안내서(영어)", "DayHand 사용 안내서(시작하기, 스택과 날짜, 검토, 동기화, 가져오기와 백업, 무료와 유료)는 영어로만 제공됩니다: <g>안내서 열기</g>."),
    "sv": ("Guider (på engelska)", "Guiderna för hur du använder DayHand – komma igång, högar och datum, granskningar, synkronisering, importer och säkerhetskopior, gratis och betalt – finns bara på engelska: <g>öppna guiderna</g>."),
    "da": ("Vejledninger (på engelsk)", "Vejledningerne til at bruge DayHand – kom i gang, bunker og datoer, gennemgange, synkronisering, importer og backups, gratis og betalt – findes kun på engelsk: <g>åbn vejledningerne</g>."),
    "nb": ("Veiledninger (på engelsk)", "Veiledningene for å bruke DayHand – komme i gang, bunker og datoer, gjennomganger, synkronisering, importer og sikkerhetskopier, gratis og betalt – finnes bare på engelsk: <g>åpne veiledningene</g>."),
    "fi": ("Oppaat (englanniksi)", "DayHandin käyttöoppaat – alkuun pääseminen, pinot ja päivämäärät, läpikäynnit, synkronointi, tuonnit ja varmuuskopiot, ilmainen ja maksullinen – ovat saatavilla vain englanniksi: <g>avaa oppaat</g>."),
    "pl": ("Przewodniki (po angielsku)", "Przewodniki po korzystaniu z DayHand — pierwsze kroki, stosy i daty, przeglądy, synchronizacja, importy i kopie zapasowe, wersja darmowa i płatna — są dostępne tylko po angielsku: <g>otwórz przewodniki</g>."),
}


def labels(code):
    out = {}
    for k, key in LABELS.items():
        v = cat[key]["localizations"][code]["stringUnit"]["value"]
        out[k] = "<strong>" + v.rstrip("…").strip() + "</strong>"
    return out


def word(code, key):
    return cat[key]["localizations"][code]["stringUnit"]["value"].rstrip("…").strip()


def url(page, folder, rel):
    """Address of `page` ("privacy" or "help") in a language, from a page `rel` away from docs/."""
    if folder == "en":
        return rel + ("privacy.html" if page == "privacy" else "help/")
    return f"{rel}{folder}/{page}.html"


def alternates(page):
    rows = [f'<link rel="alternate" hreflang="en" href="{BASE}/{"privacy.html" if page == "privacy" else "help/"}">']
    for folder, hl, _, _ in LANGS:
        rows.append(f'<link rel="alternate" hreflang="{hl}" href="{BASE}/{folder}/{page}.html">')
    rows.append(f'<link rel="alternate" hreflang="x-default" href="{BASE}/{"privacy.html" if page == "privacy" else "help/"}">')
    return "\n".join(rows)


def langmenu(page, current, rel, label):
    """The language menu in a page's top right: the same one the homepage has."""
    items = ['<span aria-current="page" lang="en">English</span>' if current == "en"
             else f'<a href="{url(page, "en", rel)}" hreflang="en" lang="en">English</a>']
    for folder, hl, _, name in LANGS:
        if folder == current:
            items.append(f'<span aria-current="page" lang="{hl}">{name}</span>')
        else:
            items.append(f'<a href="{url(page, folder, rel)}" hreflang="{hl}" lang="{hl}">{name}</a>')
    return f'<details class="langmenu"><summary>{label}</summary><div class="langlist">' + "".join(items) + "</div></details>"


def header(page, current, rel, help_label, privacy_label, langs_label):
    """Brand on the left; Help, Privacy and the language menu on the right."""
    help_href = url("help", current, rel)
    privacy_href = url("privacy", current, rel)
    hl = ' aria-current="page"' if page == "help" else ""
    pl = ' aria-current="page"' if page == "privacy" else ""
    return (f'<header><a class="brand" href="{rel}index.html"><img src="{rel}icon.png" alt="" width="36" height="36">DayHand</a>'
            f'<div class="hright"><a href="{help_href}"{hl}>{help_label}</a><a href="{privacy_href}"{pl}>{privacy_label}</a>'
            f'{langmenu(page, current, rel, langs_label)}</div></header>')


def p(x):
    return f"<p>{x}</p>"


def privacy(code, D, tok, ccode):
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
    sup = T(P["U1"]).replace("<s>", '<a href="help.html#contact">').replace("</s>", "</a>")
    sec("support", h2[7], [p(sup), p(T(P["U2"])), p(T(P["U3"]))])
    web = (T(P["W1"]).replace("<g>", '<a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">').replace("</g>", "</a>")
           .replace("<apple>", '<a href="https://www.apple.com/legal/privacy/">').replace("</apple>", "</a>"))
    sec("website", h2[8], [p(web)])
    sec(None, h2[9], [p(T(P["CHG"]))])
    note = D["note"].replace("<en>", '<a href="../privacy.html" hreflang="en" lang="en">').replace("</en>", "</a>")
    f = D["footer"]
    hdr = header("privacy", code, "../", word(ccode, "Help"), word(ccode, "Privacy policy"), D["langs_label"])
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
{hdr}
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
<footer><a href="help.html">{f[1]}</a> · <a href="../index.html">{f[2]}</a></footer>
</main></div>
</body></html>
'''


def help_page(code, D, tok, ccode):
    T = lambda s: s.format(**tok)
    S_ = D["S"]
    en = D["en_mark"]
    def fill(s):
        s = T(s)
        s = s.replace("<sync>", '<a href="../help/#sync-troubleshooting" hreflang="en" lang="en">').replace("</sync>", f'</a> {en}')
        s = s.replace("<col>", '<a href="../help/#colours" hreflang="en" lang="en">').replace("</col>", f'</a> {en}')
        s = s.replace("<imp>", '<a href="../help/#data" hreflang="en" lang="en">').replace("</imp>", f'</a> {en}')
        s = s.replace("<new>", '<a href="https://github.com/amouraux/DayHand/issues/new">').replace("</new>", "</a>")
        s = s.replace("<all>", '<a href="https://github.com/amouraux/DayHand/issues">').replace("</all>", "</a>")
        return s
    ul1 = "<ul>\n" + "\n".join(f"<li>{fill(x)}</li>" for x in S_["N"]) + "\n</ul>"
    ul2 = "<ul>\n" + "\n".join(f"<li>{fill(x)}</li>" for x in S_["T"]) + "\n</ul>"
    try:
        gm = importlib.import_module("guide_" + code.replace("-", "_"))
    except ImportError:
        gm = None
    if gm:
        return help_page_full(code, D, tok, ccode, gm)
    glabel, gnote = GUIDES[code]
    nav = "".join(f'<a href="#{i}">{n}</a>' for i, n in zip(["missing-tasks", "notifications", "contact"], D["nav"]))
    nav += f'<a href="../help/" hreflang="en" lang="en">{glabel}</a>'
    gnote = gnote.replace("<g>", '<a href="../help/" hreflang="en" lang="en">').replace("</g>", "</a>")
    title = word(ccode, "Help and support")
    f = D["footer"]
    hdr = header("help", code, "../", word(ccode, "Help"), word(ccode, "Privacy policy"), D["langs_label"])
    return f'''<!doctype html>
<html lang="{D["html_lang"]}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — DayHand</title>
<meta name="description" content="{D["desc"]}">
<link rel="icon" href="../icon.png">
<link rel="stylesheet" href="../help/help.css">
<link rel="canonical" href="{BASE}/{code}/help.html">
{alternates("help")}
</head>
<body>
<a class="skip" href="#main">{D["skip"]}</a>
{hdr}
<div class="layout">
<nav aria-label="{D["nav_aria"]}">{nav}</nav>
<main id="main">
<p class="eyebrow">{D["eyebrow"]}</p>
<h1>{title}</h1>
<p class="lead">{D["lead"]}</p>
<aside>{gnote}</aside>
<h2 id="missing-tasks">{D["h2"][0]}</h2>
{p(fill(S_["M1"]))}
<h2 id="notifications">{D["h2"][1]}</h2>
{ul1}
{p(fill(S_["N_after"]))}
<h2 id="imports-differ">{D["h2"][2]}</h2>
{p(fill(S_["X1"]))}
<h2 id="contact">{D["h2"][3]}</h2>
{p(fill(S_["C1"]))}
{p(fill(S_["C2"]))}
{ul2}
<aside>{fill(S_["aside"])}</aside>
{p(fill(S_["C3"]))}
<p>{D["note"].replace("<en>", '<a href="../help/" hreflang="en" lang="en">').replace("</en>", "</a>")}</p>
<footer>{D["footer_text"]}<br>
<a href="privacy.html">{f[1]}</a> · <a href="../index.html">{f[2]}</a></footer>
</main>
</div>
</body></html>
'''


def help_page_full(code, D, tok, ccode, gm):
    """The whole Help page in one language: the guides, then troubleshooting and contact."""
    import html as htmllib
    import make_help
    english = open(f"{ROOT}/docs/help/index.html").read()
    units = make_help.english_units(english)
    problems = make_help.check(code, [gm.G[i] for i in sorted(gm.G)], units)
    if problems:
        raise SystemExit("\n".join(problems[:8]))
    ui = {}
    for name, key in make_help.UI.items():
        v = word(ccode, key) if name == "edit_plain" else cat[key]["localizations"][ccode]["stringUnit"]["value"]
        ui[name] = htmllib.escape(v, quote=False)
    guides = make_help.guide_sections(english, [gm.G[i] for i in sorted(gm.G)], ui)
    T = lambda s: s.format(**tok)
    S_ = D["S"]
    def fill(s):
        s = T(s)
        s = s.replace("<sync>", '<a href="#sync-troubleshooting">').replace("</sync>", "</a>")
        s = s.replace("<col>", '<a href="#colours">').replace("</col>", "</a>")
        s = s.replace("<imp>", '<a href="#data">').replace("</imp>", "</a>")
        s = s.replace("<new>", '<a href="https://github.com/amouraux/DayHand/issues/new">').replace("</new>", "</a>")
        s = s.replace("<all>", '<a href="https://github.com/amouraux/DayHand/issues">').replace("</all>", "</a>")
        return s
    ul1 = "<ul>\n" + "\n".join(f"<li>{fill(x)}</li>" for x in S_["N"]) + "\n</ul>"
    ul2 = "<ul>\n" + "\n".join(f"<li>{fill(x)}</li>" for x in S_["T"]) + "\n</ul>"
    ids = ["getting-started", "stacks-and-dates", "reviews", "sync", "data", "free-and-paid", "troubleshooting", "contact"]
    nav = "".join(f'<a href="#{i}">{n}</a>' for i, n in zip(ids, gm.NAV))
    intro = gm.INTRO.replace("<t>", '<a href="#troubleshooting">').replace("</t>", "</a>").replace("<c>", '<a href="#contact">').replace("</c>", "</a>")
    note = gm.NOTE.replace("<en>", '<a href="../help/" hreflang="en" lang="en">').replace("</en>", "</a>")
    title = word(ccode, "Help and support")
    f = D["footer"]
    hdr = header("help", code, "../", word(ccode, "Help"), word(ccode, "Privacy policy"), D["langs_label"])
    return f'''<!doctype html>
<html lang="{D["html_lang"]}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — DayHand</title>
<meta name="description" content="{D["desc"]}">
<link rel="icon" href="../icon.png">
<link rel="stylesheet" href="../help/help.css">
<link rel="canonical" href="{BASE}/{code}/help.html">
{alternates("help")}
</head>
<body>
<a class="skip" href="#main">{D["skip"]}</a>
{hdr}
<div class="layout">
<nav aria-label="{D["nav_aria"]}">{nav}</nav>
<main id="main">
<p class="eyebrow">{D["eyebrow"]}</p>
<h1>{title}</h1>
<p class="lead">{intro}</p>
{guides}
<section id="troubleshooting">
<h2>{gm.TRB}</h2>
<p class="lead">{D["lead"]}</p>
<h3 id="missing-tasks">{D["h2"][0]}</h3>
{p(fill(S_["M1"]))}
<h3 id="notifications">{D["h2"][1]}</h3>
{ul1}
{p(fill(S_["N_after"]))}
<h3 id="imports-differ">{D["h2"][2]}</h3>
{p(fill(S_["X1"]))}
</section>
<section id="contact">
<h2>{gm.CONTACT}</h2>
{p(fill(S_["C1"]))}
{p(fill(S_["C2"]))}
{ul2}
<aside>{fill(S_["aside"])}</aside>
{p(fill(S_["C3"]))}
</section>
<p>{note}</p>
<footer>{D["footer_text"]}<br>
<a href="privacy.html">{f[1]}</a> · <a href="../index.html">{f[2]}</a></footer>
</main>
</div>
</body></html>
'''


def redirect(path, target, hash_map=None):
    """A page that has moved: the guides and the support page are one Help page now."""
    mapping = json.dumps(hash_map or {})
    html = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Moved — DayHand</title>
<meta http-equiv="refresh" content="0; url={target}">
<link rel="canonical" href="{BASE}/{os.path.relpath(os.path.normpath(os.path.join(os.path.dirname(path), target.split("#")[0])), f"{ROOT}/docs")}">
<script>
  var map = {mapping};
  var h = location.hash;
  location.replace("{target.split("#")[0]}" + (map[h] || h || "#{target.split("#")[1] if "#" in target else ""}"));
</script>
</head>
<body><p>This page has moved: <a href="{target}">DayHand Help and support</a>.</p></body>
</html>
'''
    open(path, "w").write(html)


GUIDE_REDIRECTS = {
    "getting-started": "#getting-started", "tasks-and-dates": "#stacks-and-dates", "reviews": "#reviews",
    "sync": "#sync", "data": "#data", "free-and-paid": "#free-and-paid", "support": "#troubleshooting",
}
OLD_HASHES = {"#troubleshooting": "#sync-troubleshooting"}   # the sync guide's own anchor


def patch_english():
    """Puts the shared header and the banner script on the English privacy and help pages, once."""
    for page, path, rel in (("privacy", f"{ROOT}/docs/privacy.html", ""), ("help", f"{ROOT}/docs/help/index.html", "../")):
        s = open(path).read()
        s = re.sub(r'<link rel="alternate"[^\n]*\n', "", s)
        s = re.sub(r'<header>.*?</header>', header(page, "en", rel, "Help", "Privacy", "Languages"), s, count=1, flags=re.S)
        s = re.sub(r'<nav class="langs".*?</nav>\n?', "", s, flags=re.S)
        s = re.sub(r'<details class="langs".*?</details>\n?', "", s, flags=re.S)
        s = re.sub(r'<script src="[^"]*lang\.js"[^>]*></script>\n?', "", s)
        s = s.replace("</head>", alternates(page) + "\n</head>", 1)
        s = s.replace("</body>", f'<script src="{rel}lang.js" data-page="{page}" defer></script>\n</body>', 1)
        s = s.replace('href="help/support.html#contact"', 'href="help/#contact"')
        open(path, "w").write(s)


def write_redirects():
    for name, anchor in GUIDE_REDIRECTS.items():
        redirect(f"{ROOT}/docs/help/{name}.html", f"index.html{anchor}",
                 OLD_HASHES if name == "sync" else None)
    for folder, *_ in LANGS:
        redirect(f"{ROOT}/docs/{folder}/support.html", "help.html#missing-tasks")


if __name__ == "__main__":
    only = sys.argv[1:]
    for folder, hl, ccode, name in LANGS:
        if only and folder not in only:
            continue
        mod = importlib.import_module("web_" + folder.replace("-", "_"))
        tok = labels(ccode)
        os.makedirs(f"{ROOT}/docs/{folder}", exist_ok=True)
        open(f"{ROOT}/docs/{folder}/privacy.html", "w").write(privacy(folder, mod.PRIVACY, tok, ccode))
        open(f"{ROOT}/docs/{folder}/help.html", "w").write(help_page(folder, mod.SUPPORT, tok, ccode))
        print("wrote", folder)
    if not only:
        patch_english()
        write_redirects()
        print("patched English, wrote redirects")
