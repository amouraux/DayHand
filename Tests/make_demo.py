#!/usr/bin/env python3
"""Writes a believable cards.json for screenshots: a freelance web designer.

Every date is relative to the day it is run, so reminders are red or orange as
intended and the completed history spans the last two months. Run it again
on the day of the screenshots.

    python3 Tests/make_demo.py [output.json]      # default docs/screenshots/demo-cards.json
    Tests/run.sh docs/screenshots/demo-cards.json  # check that the app will accept it

Load it into the SIMULATOR only (never the Mac app, which shares the live
file). The ids are random per run, so loading it twice never collides.
"""
import json
import sys
import uuid
from datetime import datetime, timedelta, timezone

NOW = datetime.now(timezone.utc).replace(microsecond=0)
LOCAL_MIDNIGHT = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)


def ts(dt):
    # Exactly three fractional digits, or the app's decoder throws.
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def at_nine(days):
    """9am local, `days` from today (negative = past)."""
    return (LOCAL_MIDNIGHT + timedelta(days=days, hours=9)).astimezone(timezone.utc)


def ago(days, hour=None):
    dt = NOW - timedelta(days=days)
    if hour is not None:
        dt = (LOCAL_MIDNIGHT - timedelta(days=days)).replace(hour=hour)
    return dt


def uid():
    return str(uuid.uuid4()).upper()


CAT_CLIENT, CAT_STUDIO, CAT_HOME = uid(), uid(), uid()
categories = [
    {"id": CAT_CLIENT, "label": "Client work", "symbolName": "briefcase", "color": "indigo"},
    {"id": CAT_STUDIO, "label": "Studio", "symbolName": "paintbrush", "color": "pink"},
    {"id": CAT_HOME, "label": "Home", "symbolName": "house", "color": "teal"},
]
for c in categories:
    c["modifiedAt"] = ts(NOW - timedelta(days=60))

# name, category, group, archived
PROJECTS = {}
project_rows = [
    ("HARBOR", CAT_CLIENT, "Active clients", False),   # Harbor Coffee – new site
    ("NORTH", CAT_CLIENT, "Active clients", False),    # Northwind – rebrand
    ("LUMEN", CAT_CLIENT, "Active clients", False),    # Lumen Dental – redesign
    ("FERN", CAT_CLIENT, "Retainers", False),          # Fernhill – monthly care plan
    ("OAKLEY", CAT_CLIENT, "Retainers", True),         # finished last month
    ("FOLIO", CAT_STUDIO, "Business", False),          # portfolio refresh
    ("BOOKS", CAT_STUDIO, "Business", False),          # invoices, taxes
    ("MOTION", CAT_STUDIO, "Learning", False),         # learning motion design
    ("FLAT", CAT_HOME, None, False),                   # flat renovation
]
projects = []
for name, cat, group, archived in project_rows:
    PROJECTS[name] = uid()
    p = {"id": PROJECTS[name], "name": name, "categoryID": cat, "isArchived": archived,
         "modifiedAt": ts(NOW - timedelta(days=40))}
    if group:
        p["group"] = group
    projects.append(p)

CAT_OF = {name: cat for name, cat, _, _ in project_rows}
cards = []


def card(title, bucket, project=None, notes="", remind=None, deadline=None,
         entered=None, completed_days_ago=None, before="today", category=None):
    """remind / deadline are day offsets from today; entered is days ago."""
    entered_at = ago(entered if entered is not None else 3)
    c = {
        "id": uid(), "title": title, "notes": notes, "bucket": bucket,
        "isSample": False, "dateSemanticsVersion": 1,
        "createdAt": ts(entered_at - timedelta(days=5)),
        "enteredStackAt": ts(entered_at),
        "modifiedAt": ts(entered_at),
    }
    cat = CAT_OF[project] if project else category
    if cat:
        c["categoryID"] = cat
    if project:
        c["projectID"] = PROJECTS[project]
    if remind is not None:
        c["remindAt"] = ts(at_nine(remind))
    if deadline is not None:
        c["deadline"] = ts(at_nine(deadline))
    if bucket == "completed":
        done = ago(completed_days_ago, hour=15)
        c["completedAt"] = ts(done)
        c["bucketBeforeCompletion"] = before
        c["modifiedAt"] = ts(done)
        c["enteredStackAt"] = ts(done - timedelta(days=4))
    cards.append(c)


# Inbox — captured, not yet decided
card("Ask Harbor about opening hours for the footer", "inbox", category=CAT_CLIENT, entered=0)
card("Look at the new variable fonts from Fontshare", "inbox", category=CAT_STUDIO, entered=0)
card("Check the screen reader order on the Lumen booking form", "inbox", "LUMEN", entered=1)
card("Birthday present for Marta", "inbox", category=CAT_HOME, entered=1)
card("Idea: case study page template for the portfolio", "inbox", "FOLIO", entered=2)

# Now — in progress, for as long as it takes
card("Design the homepage hero for Harbor Coffee", "today", "HARBOR", entered=4,
     notes="Three options: full-bleed photo, split layout, or illustrated.\nClient likes warm tones. Logo must stay legible on the photo.",
     remind=-1, deadline=6)
card("Build the product grid component", "today", "HARBOR", entered=6, deadline=12)
card("Send revised logo lockups to Northwind", "today", "NORTH", entered=2, remind=0)
card("Write the Lumen sitemap and page hierarchy", "today", "LUMEN", entered=5, remind=2)
card("Update plugins and run the backup on Fernhill", "today", "FERN", entered=1, remind=1)
card("Sketch the studio wall shelves", "today", "FLAT", entered=3)
card("Prepare invoice for October", "today", "BOOKS", entered=1, remind=-2)

# Next — what comes after
card("Mobile layout for the Harbor menu page", "tomorrow", "HARBOR", entered=3)
card("Northwind colour palette: accessibility check", "tomorrow", "NORTH", entered=4,
     notes="Contrast ratios for the secondary teal on white fail AA at small sizes.")
card("Lumen: first round of wireframes", "tomorrow", "LUMEN", entered=7, deadline=18)
card("Quarterly accessibility audit on Fernhill", "tomorrow", "FERN", entered=6, remind=3)
card("Refresh the portfolio homepage", "tomorrow", "FOLIO", entered=9)
card("Choose paint colours", "tomorrow", "FLAT", entered=8)

# Later — kept for the future
card("Animated logo reveal for Northwind", "later", "NORTH", entered=14)
card("Record a short walkthrough video for Harbor", "later", "HARBOR", entered=12)
card("Learn Rive for interactive illustrations", "later", "MOTION", entered=20)
card("Write up the Oakley case study", "later", "FOLIO", entered=25)
card("Replace the hallway lights", "later", "FLAT", entered=30)

# Waiting — blocked on somebody else
card("Harbor: final product photos", "waiting", "HARBOR", entered=5, remind=-1,
     notes="Promised by Elena (photographer) at the end of last week.")
card("Northwind: feedback on logo round 2", "waiting", "NORTH", entered=3, remind=2)
card("Lumen: copy for the services pages", "waiting", "LUMEN", entered=8, remind=4)
card("Quote from the electrician", "waiting", "FLAT", entered=10, remind=-3)
card("Accountant: VAT questions", "waiting", "BOOKS", entered=6)

# Completed — spread across two months, so the timeline has months and days
done = [
    ("Kick-off call with Harbor Coffee", "HARBOR", 1, "today"),
    ("Collect brand assets from Northwind", "NORTH", 1, "today"),
    ("Moodboard for the Harbor site", "HARBOR", 3, "today"),
    ("Send Northwind the logo shortlist", "NORTH", 4, "waiting"),
    ("Sign the Lumen contract", "LUMEN", 6, "waiting"),
    ("Set up staging for Fernhill", "FERN", 8, "tomorrow"),
    ("Invoice September", "BOOKS", 9, "today"),
    ("Hand over the Oakley site", "OAKLEY", 13, "today"),
    ("Final QA pass on Oakley", "OAKLEY", 16, "today"),
    ("Fix the contact form on Fernhill", "FERN", 20, "today"),
    ("Order the desk", "FLAT", 24, "tomorrow"),
    ("Update portfolio case studies", "FOLIO", 31, "today"),
    ("Take the motion basics course", "MOTION", 38, "today"),
    ("Oakley: homepage design approved", "OAKLEY", 44, "waiting"),
    ("Register the business address", "BOOKS", 52, "today"),
    ("Oakley: gather content from client", "OAKLEY", 58, "waiting"),
]
for title, proj, days, before in done:
    card(title, "completed", proj, completed_days_ago=days, before=before)

document = {
    "cards": cards,
    "categories": categories,
    "projects": projects,
    "defaultCategoryChangedAt": "0001-01-01T00:00:00.000Z",
    "deletedCards": {}, "deletedCategories": {}, "deletedProjects": {},
    "importedReminderIDs": [], "importedTodoistIDs": [],
}

out = sys.argv[1] if len(sys.argv) > 1 else "docs/screenshots/demo-cards.json"
with open(out, "w", encoding="utf-8") as f:
    json.dump(document, f, indent=2, ensure_ascii=False, sort_keys=True)
    f.write("\n")
print(f"{len(cards)} tasks, {len(projects)} projects, {len(categories)} categories -> {out}")
