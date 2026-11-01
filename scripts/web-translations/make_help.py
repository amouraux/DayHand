"""The translated Help and support pages: guides, troubleshooting and contact.

docs/help/index.html is the one source of structure and of the English text. Its
guide sections (everything but Troubleshooting and Contact) are cut into units —
every heading, paragraph, list item, aside and definition — in document order,
and each language's guide_<code>.py supplies the same units in the same order.
Troubleshooting and Contact come from web_<code>.py (the SUPPORT dict).

Names of buttons and screens are written as {tokens} and filled from
Localizable.xcstrings, so the page says what the app's screen says. If the
English guides gain or lose a block, the count no longer matches and the
generator stops rather than shipping a shifted page.
"""
import re, importlib

UNIT = re.compile(r'<(h2|h3|h4|p|li|aside|dt|dd)(?: [^>]*)?>(.*?)</\1>', re.S)
GUIDE_IDS = ["getting-started", "stacks-and-dates", "reviews", "sync", "data", "free-and-paid"]

# token -> catalogue key. Values are used as the app shows them, ellipsis and all,
# except `edit_plain`, which drops it.
UI = {
    "more": "More", "appearance": "Appearance", "timeline": "Timeline", "review": "Review",
    "sync": "Sync", "create_sync": "Create Sync File…", "use_existing": "Use Existing Sync File…",
    "tasks": "Tasks", "import_reminders": "Import from Apple Reminders…",
    "import_todoist": "Import from Todoist…", "export_csv": "Export as CSV…",
    "import_csv": "Import from CSV…", "backups": "Backups", "backup_now": "Back Up Now",
    "share": "Share", "merge_with": "Merge With This Device", "add_existing": "Add to Existing Tasks",
    "replace_all": "Replace All Tasks", "replace_device": "Replace Tasks on This Device",
    "restore_file": "Restore From File…", "stop_using": "Stop Using This File", "sync_now": "Sync Now",
    "remind_me": "Remind me…", "change_reminder": "Change reminder…", "clear_reminder": "Clear the reminder",
    "keep_here": "Keep here", "edit_plain": "Edit…", "review_projects": "Review projects",
    "add_task": "Add a task", "looks_right": "Looks right — next project", "edit_project": "Edit project",
    "review_these": "Review these tasks", "keep_in_now": "Keep in Now", "not_syncing": "Not syncing",
    "inbox": "Inbox", "now": "Now", "next": "Next", "later": "Later", "waiting": "Waiting",
    "rv_inbox": "Review Inbox", "rv_now": "Review Now", "rv_waiting": "Review Waiting",
    "rv_next_later": "Review Next and Later", "rv_all": "Review all tasks",
}


def english_units(html):
    """(section id, tag, inner html) for every unit of the guide sections, in order."""
    out = []
    for sid, body in re.findall(r'<section id="([^"]+)">(.*?)</section>', html, re.S):
        if sid in GUIDE_IDS:
            for m in UNIT.finditer(body):
                out.append((sid, m.group(1), m.group(2).strip()))
    return out


def shape(h):
    """What a unit's markup must keep: its tags and link targets, as a sorted list."""
    return sorted(re.findall(r'</?[a-z]+|href="[^"]*"', h))


def guide_sections(html, G, tok):
    """The English guide sections with every unit replaced by its translation."""
    n = [0]
    def put(m):
        i = n[0]; n[0] += 1
        t = m.group(0); a = m.start(2) - m.start(0); b = m.end(2) - m.start(0)
        return t[:a] + G[i].format(**tok) + t[b:]
    out = []
    for sid, body in re.findall(r'<section id="([^"]+)">(.*?)</section>', html, re.S):
        if sid in GUIDE_IDS:
            out.append(f'<section id="{sid}">\n' + UNIT.sub(put, body).strip("\n") + "\n</section>")
    assert n[0] == len(G), f"{n[0]} units in the English guides, {len(G)} translated"
    return "\n".join(out)


def check(code, G, English):
    """Every translated unit keeps its English unit's tags and link targets."""
    problems = []
    if len(G) != len(English):
        return [f"{code}: {len(G)} units, English has {len(English)}"]
    for i, ((sid, tag, eng), t) in enumerate(zip(English, G)):
        if shape(t) != shape(eng):
            problems.append(f"{code} unit {i} ({tag}): markup differs\n   EN {shape(eng)}\n   TR {shape(t)}")
        for tokname in re.findall(r"\{([a-z_]+)\}", t):
            if tokname not in UI:
                problems.append(f"{code} unit {i}: unknown token {{{tokname}}}")
    return problems
