# DayHand

A to-do app for iPhone, iPad and Mac, built in SwiftUI — for work that takes
longer than a day.

**<https://amouraux.github.io/DayHand/>** · [join the TestFlight beta](https://testflight.apple.com/join/37FbdQp6)

## A task is not a date

Most real tasks aren't things you start and finish on a single day. They stay
with you for several days — sometimes weeks — and conventional task managers
often force you to keep rescheduling them, or breaking them into unnecessary
subtasks, just to reflect that reality.

DayHand takes a simpler approach. Put what you're actively working on in
**Now**, what you want to tackle next in **Next**, and everything else in
**Later**. If progress depends on someone or something else, move it to
**Waiting** until you can act again.

Dates are used only when they actually mean something. A **reminder** tells you
when a task should come back to your attention; a **deadline** tells you when it
really needs to be finished. Neither changes where the task belongs. Nothing
gets automatically pushed around just because another day has passed. Your tasks
stay where you put them, so DayHand remains a calm picture of what you're doing,
what comes next, and what you're waiting for.

## Intention. Attention. Obligation.

DayHand keeps them separate — because they are different things.

| | |
| --- | --- |
| **Stacks** express intention | **Now** is what you are working on, **Next** what you mean to pick up after it, **Later** what you are keeping but consciously not doing yet. New cards land in **Inbox** until you decide. A card can sit in Now for a week; nothing says otherwise. |
| **Waiting** holds what isn't yours | Sent for review, a quote not yet received, a reply owed to you. Still live, but you cannot advance it. It moves out of the way without being forgotten. |
| **Reminders** ask for attention | *When should I think about this again?* A notification on the day you asked, and a coloured edge: orange within three days, red on the day and after. It decides nothing and moves nothing. |
| **Deadlines** mark obligation | *When must this actually be finished?* Offered once a reminder exists, and shown on the card. Because it is only ever a real one, it means something. |

**Nothing moves behind your back.** Tomorrow arriving does not change what you
intended to work on, and a reminder coming due tells you rather than files
anything. *Later* does not mean forgotten, it means not yet. *Waiting* does not
mean dropped, it means not mine right now. And when something is genuinely
overdue, that word still means something.

## How DayHand fits real work

- **Architect** — drawings in progress in Now, the next revision in Next, future
  ideas in Later. A set sent to the client for approval goes to Waiting, with a
  reminder to follow up and a deadline only on the actual submission date.
- **Plumber** — today's jobs in Now, this week's in Next, the rest in Later. A
  job held up by a part on order or a customer who hasn't confirmed goes to
  Waiting, with a reminder to chase — without pretending it was due today.
- **Student** — "write the thesis" is not a Tuesday task. The chapter you're
  writing stays in Now for as long as it takes; it goes to Waiting while your
  supervisor has it. Deadlines are the real submission dates, and only those.
- **Researcher** — an analysis or manuscript stays in Now while it is actually
  moving. Manuscripts with co-authors, equipment on order and experiments
  awaiting data go to Waiting. Grant and journal dates are genuine deadlines.
- **Web developer** — the feature you're building in Now, the backlog in Later.
  Blocked on an API key, client feedback or someone else's review, it goes to
  Waiting. The reminder says when to follow up; the deadline says when the
  release has to ship.

### One task, one week

| | | |
| --- | --- | --- |
| **Monday** | You start on the conference talk | → Now |
| **Wednesday** | Draft sent to a colleague | → Waiting |
| **Thursday** | They reply | → Now |
| **Friday, 17:00** | You give the talk | Deadline |

One card the whole week. The Friday deadline never changed, and the task was
never recreated, split up or pushed to a new day.

## The rest of it

**Projects.** A card can carry one project — a course code, a study, a trip —
typed as `#ABC1234`. It shows as a coloured prefix on the card, fills in the
card's category, and can be renamed, merged or archived in one edit. Projects
gather into groups such as Grants and Ongoing, all from the Filter.

**What you finished.** Alongside the list of what you owe, DayHand shows what
you got done — this week and last, grouped by the day you finished it.

**Your cards stay yours.** Everything is kept on your own device. No account,
no server, nothing to sign up for.

## Install it

- **iPhone and iPad** — [join the TestFlight beta](https://testflight.apple.com/join/37FbdQp6), iOS 17 or later.
- **Mac** — [the same TestFlight link](https://testflight.apple.com/join/37FbdQp6),
  macOS 14 or later. TestFlight for the Mac is a separate app from the iPhone
  one, from the Mac App Store, signed in to the same Apple Account.

The TestFlight Mac build is sandboxed, so it keeps its data somewhere other
than a build made in Xcode did: anyone moving across opens it to an empty list.
Nothing is lost — the old file is where it always was, and re-picking the sync
file in **More** brings it back.

A public `.dmg` is a separate, later channel. `scripts/release-mac.sh` builds a
signed and notarised one — see the comment at the top of that script for the two
one-time steps — but it needs a **Developer ID Application** certificate, which
TestFlight does not.

## Building it

Requires **Xcode 26 or newer**: the floating buttons use iOS 26's glass APIs
behind an availability check, so the SDK has to know them even though the app
still runs on iOS 17. No third-party dependencies.

```sh
open DayHand.xcodeproj
```

Press ⌘R with an iPhone, a simulator, or **My Mac** selected. The same target
runs on macOS through Mac Catalyst.

From the command line:

```sh
xcodebuild -project DayHand.xcodeproj -scheme DayHand \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project DayHand.xcodeproj -scheme DayHand \
  -destination 'platform=macOS,variant=Mac Catalyst' build
```

Set `DEVELOPMENT_TEAM` to your own team before running on a device.

## Tests

The model layer — the date rules, the document format, merging two devices,
CSV, projects and groups — is tested without Xcode, a simulator or any app
data:

```sh
Tests/run.sh
```

It compiles `DayHand/Models.swift` and `DayHand/Sync.swift` with
`Tests/main.swift` and runs them, in about a second. All fixtures are invented;
nothing reads your own cards. To check that a real file still decodes, pass it
in:

```sh
Tests/run.sh path/to/cards.json
```

## How the code is laid out

| File | What lives there |
| --- | --- |
| `DayHand/Models.swift` | Cards, stacks, categories, projects, groups, the date rules. Foundation only — no UI, which is why it is testable on its own. |
| `DayHand/Sync.swift` | The document format, merging two copies, the shared file, backups, CSV. Foundation only, for the same reason. |
| `DayHand/TodoStore.swift` | The observable store: every change to the data goes through here. |
| `DayHand/DayHandApp.swift` | The app entry point. |
| `DayHand/ContentView.swift` | The stacks, filtering, search and the floating buttons. |
| `DayHand/CardRow.swift` | One card: its colours, swipes and context menu. |
| `DayHand/AddCardView.swift` | New Task sheet and the card editor, including the project field they share. |
| `DayHand/FilterView.swift` | The filter: categories, groups and projects, as a sheet or a sidebar. |
| `DayHand/ProjectEditor.swift` | One project — rename, category, group, archive, merge, delete — and the one-time conversion of title prefixes. |
| `DayHand/ReminderScheduler.swift` | The only place that talks to the notification centre. |
| `DayHand/ReviewView.swift` | What you finished in a week, grouped by day. |
| `DayHand/SettingsView.swift` | Categories, sync, CSV, backups. |
| `docs/PROMPT.md` | The full specification: enough to rebuild the app from nothing. |

## Where the data lives

One JSON file holding cards, categories, projects and tombstones, in the app's
Application Support directory. On a sandboxed Mac build that is inside the app's
container rather than `~/Library/Application Support`.

**Syncing** is a file you pick yourself, typically in iCloud Drive, so no iCloud
entitlement and no paid developer account are needed — access comes from your
choosing the file. Every device reads and writes that one file, and edits are
merged per card by their edit time, with deletions recorded as tombstones so a
delete on one device is not undone by another. Settings says **Not syncing**
when no file is chosen.

**Backups** are kept as separate files, each named for what it is and which
device wrote it: three taken automatically — yesterday, the day before, and one
from about a week ago — plus any you take by hand, under their date. All of them
can be restored or shared from Settings.

**CSV** import and export cover cards, categories, projects and groups.
