# DayDeck

A to-do app for iPhone and Mac, built in SwiftUI. Cards live in stacks you file
them into — **Inbox, Today, Tomorrow, Later, Completed** — and nothing rolls
over on its own.

## The idea

**An undated card stays where you put it.** A card in Tomorrow is still in
Tomorrow next week. Time passing never moves it; only you do.

**A date files a card, but only once it arrives.** Give a card a date and it
sits where it is until that day comes round, then it moves to Today or
Tomorrow by itself. Cards raised out of Later that way say so in a banner,
since that is the one move you did not ask for.

**Tags for subprojects.** A card can carry one project — a course code, a study
— typed as `#ABC1234`. It shows as a coloured prefix on the card, fills in the
card's category, and can be renamed or merged in one edit. Tags can be gathered
into groups such as Grants and Ongoing.

## Building it

Requires Xcode 16 or newer. No third-party dependencies.

```sh
open DayDeck.xcodeproj
```

Press ⌘R with an iPhone, a simulator, or **My Mac** selected. The same target
runs on macOS through Mac Catalyst.

From the command line:

```sh
xcodebuild -project DayDeck.xcodeproj -scheme DayDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project DayDeck.xcodeproj -scheme DayDeck \
  -destination 'platform=macOS,variant=Mac Catalyst' build
```

Set `DEVELOPMENT_TEAM` to your own team before running on a device.

## Tests

The model layer — dates and filing, the document format, merging two devices,
CSV, tags and groups — is tested without Xcode, a simulator or any app data:

```sh
Tests/run.sh
```

It compiles `DayDeck/Models.swift` and `DayDeck/Sync.swift` with `Tests/main.swift` and
runs them. All fixtures are invented; nothing reads your own cards. To check
that a real file still decodes, pass it in:

```sh
Tests/run.sh ~/Library/Application\ Support/cards.json
```

## How the code is laid out

| File | What lives there |
| --- | --- |
| `DayDeck/Models.swift` | Cards, stacks, categories, tags, groups, date rules. Foundation only — no UI, which is why it is testable on its own. |
| `DayDeck/Sync.swift` | The document format, merging two copies, the shared file, backups, CSV. |
| `DayDeck/TodoStore.swift` | The observable store: every change to the data goes through here. |
| `DayDeck/ContentView.swift` | The list of stacks, filtering, the floating buttons. |
| `DayDeck/CardRow.swift` | One card: its colours, swipes and context menu. |
| `DayDeck/AddCardView.swift` | New Task sheet, the card editor, the date picker, the filter sheet. |
| `DayDeck/ProjectsView.swift` | Settings → Projects, and the one-time conversion of title prefixes. |
| `DayDeck/SettingsView.swift` | Categories, sync, CSV, backups. |
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
