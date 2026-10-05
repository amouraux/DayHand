#!/usr/bin/env python3
"""Write a document of invented cards, for taking screenshots.

    python3 scripts/demo-seed.py <path to cards.json>

Screenshots on the site come from this and never from real cards. The content
is chosen to show the model in one frame: a multi-day job in Now carrying both
a reminder and a deadline, something orange in Next, something far off in
Later, and two in Waiting — one being chased today, one simply parked.

**Never point this at a file an app is syncing.** On a Mac, turn sync off in
More → Stop Using This File first, or the invented cards merge into the real
sync file and reach every other device.
"""
import json, sys, uuid
from datetime import datetime, timedelta, timezone
now = datetime.now(timezone.utc)
def st(d): return d.strftime('%Y-%m-%dT%H:%M:%S.') + f'{d.microsecond//1000:03d}Z'
def day(n, h=9): return (now + timedelta(days=n)).replace(hour=h, minute=0, second=0, microsecond=0)
past = "0001-01-01T00:00:00.000Z"

research = {"id": str(uuid.uuid4()), "label": "Research", "color": "indigo",
            "symbolName": "flask", "modifiedAt": past}
teaching = {"id": str(uuid.uuid4()), "label": "Teaching", "color": "purple",
            "symbolName": "graduationcap", "modifiedAt": past}
home     = {"id": str(uuid.uuid4()), "label": "Home", "color": "teal",
            "symbolName": "house", "modifiedAt": past}
cats = [research, teaching, home]

def proj(name, cat, group=None):
    p = {"id": str(uuid.uuid4()), "name": name, "categoryID": cat["id"], "modifiedAt": st(now)}
    if group: p["group"] = group
    return p
grant = proj("GRANT", research, "Grants")
paper = proj("PAPER", research, "Manuscripts")
course = proj("BIO2140", teaching, "Courses")
projects = [grant, paper, course]

def card(title, bucket, cat, project=None, remind=None, deadline=None, origin=None):
    c = {"id": str(uuid.uuid4()), "title": title, "bucket": bucket,
         "categoryID": cat["id"], "createdAt": st(now - timedelta(days=12)),
         "modifiedAt": st(now)}
    if project: c["projectID"] = project["id"]
    if remind is not None:  c["remindAt"] = st(remind)
    if deadline is not None: c["deadline"] = st(deadline)
    if origin:
        c["bucketBeforeCompletion"] = origin
        c["completedAt"] = st(now - timedelta(hours=5))
    return c

cards = [
    card("reply to the department", "inbox", home),

    # A multi-day job: started days ago, due at the end of the month.
    card("write the case for support", "today", research, grant,
         remind=day(-3), deadline=day(19)),
    card("mark the problem sets", "inbox", teaching, course),

    card("rework the methods", "tomorrow", research, paper, remind=day(1)),

    card("plan the spring fieldwork", "later", research, remind=day(26)),

    # Waiting: one being chased today, one simply parked.
    card("co-author feedback", "waiting", research, paper, remind=day(0)),
    card("quote for the service", "waiting", home),

    card("submit the ethics amendment", "completed", research, grant, origin="today"),
]
doc = {"cards": cards, "categories": cats, "projects": projects, "groups": [],
       "deletedCards": {}, "deletedCategories": {}, "deletedProjects": {}, "deletedGroups": {}}
json.dump(doc, open(sys.argv[1], "w"), indent=1)
print(f"seeded {len(cards)} cards, {len(projects)} projects, {len(cats)} categories")
