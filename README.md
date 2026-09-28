# DayHand

A to-do app for iPhone and Mac, built in SwiftUI. Cards live in stacks you file
them into — **Inbox, Today, Tomorrow, Later, Completed** — and nothing rolls
over on its own.

## Install it

- **iPhone and iPad** — [join the TestFlight beta](https://testflight.apple.com/join/37FbdQp6), iOS 17 or later.
- **Mac** — [the same TestFlight link](https://testflight.apple.com/join/37FbdQp6),
  macOS 14 or later. TestFlight for the Mac is a separate app from the iPhone
  one, from the Mac App Store, signed in to the same Apple Account.

The TestFlight Mac build is sandboxed, so it keeps its data somewhere other
than a build made in Xcode did: anyone moving across opens it to an empty list.
Nothing is lost — the old file is where it always was, and re-picking the sync
file in **More** brings it back.

A public `.dmg` is a separate, later channel: `scripts/release-mac.sh` builds a
signed and notarised one, but it needs a **Developer ID Application**
certificate, which TestFlight does not.

Both, with screenshots, are on the site: **<https://amouraux.github.io/DayHand/>**
(served from `docs/`). The Mac disk image is built by `scripts/release-mac.sh`,
which signs and notarises it — see the comment at the top of that script for
the two one-time steps.

## The idea

**An undated card stays where you put it.** A card in Tomorrow is still in
Tomorrow next week. Time passing never moves it; only you do.

**A card stays where you put it, full stop.** Nothing files a card, ever. A
card in Tomorrow is still in Tomorrow next week, and moving one by hand keeps
its dates.

**A reminder says when to start; a deadline says when to finish.** The reminder
is the card's one date: it fires a notification and colours the card's edge —
orange within three days, red on the day itself and after. Once a reminder is
set you can add an optional deadline, which is shown on the card and does
nothing else. Answering a reminder is something you do to the card: moving,
completing or deleting it all count, and Snooze and Clear sit in the card's own
menu.

**Tags for subprojects.** A card can carry one project — a course code, a study
— typed as `#ABC1234`. It shows as a coloured prefix on the card, fills in the
card's category, and can be renamed or merged in one edit. Tags can be gathered
into groups such as Grants and Ongoing, all from the Filter.

## Building it

Requires Xcode 16 or newer. No third-party dependencies.

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

The model layer — dates and filing, the document format, merging two devices,
CSV, tags and groups — is tested without Xcode, a simulator or any app data:

```sh
Tests/run.sh
```

It compiles `DayHand/Models.swift` and `DayHand/Sync.swift` with `Tests/main.swift` and
runs them. All fixtures are invented; nothing reads your own cards. To check
that a real file still decodes, pass it in:

```sh
Tests/run.sh ~/Library/Application\ Support/cards.json
```

## How the code is laid out

| File | What lives there |
| --- | --- |
| `DayHand/Models.swift` | Cards, stacks, categories, tags, groups, date rules. Foundation only — no UI, which is why it is testable on its own. |
| `DayHand/Sync.swift` | The document format, merging two copies, the shared file, backups, CSV. |
| `DayHand/TodoStore.swift` | The observable store: every change to the data goes through here. |
| `DayHand/ContentView.swift` | The list of stacks, filtering, the floating buttons. |
| `DayHand/CardRow.swift` | One card: its colours, swipes and context menu. |
| `DayHand/AddCardView.swift` | New Task sheet, the card editor, the date picker. |
| `DayHand/FilterView.swift` | The filter: categories, groups and projects, as a sheet or a sidebar. |
| `DayHand/ProjectEditor.swift` | One project — rename, category, group, archive, merge, delete — and the one-time conversion of title prefixes. |
| `DayHand/ReviewView.swift` | What you finished in a week, grouped by day. |
| `DayHand/SettingsView.swift` | Categories, sync, CSV, backups. |
| `docs/PROMPT.md` | The full specification: enough to rebuild the app from nothing. |

## Where the data lives

One JSON file holding cards, categories, tags and tombstones:

- **iOS**: the app's Application Support directory.
- **macOS**: `~/Library/Application Support/cards.json`.

**Syncing** is a file you pick yourself in iCloud Drive, so no paid developer
account is needed. Every device reads and writes that one file, and edits are
merged per card by their edit time, with deletions recorded as tombstones so a
delete on one device is not undone by another.

**Backups** are taken once a day into three slots — the most recent, the day
before, and one from about a week ago — and can be restored from Settings.

**CSV** import and export cover cards, categories, tags and groups.
