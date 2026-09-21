# Working on TnT

A to-do app for iPhone and Mac: one SwiftUI target, no third-party
dependencies. `README.md` describes the app; `docs/PROMPT.md` is the full
specification and is the place to record a decision about how the app should
behave.

## Commands

```sh
# Tests — no Xcode project, no simulator, no app data. Run these first.
Tests/run.sh

# Build for the phone and for the Mac. Both must pass before anything is done.
xcodebuild -project TnT.xcodeproj -scheme TnT \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project TnT.xcodeproj -scheme TnT \
  -destination 'platform=macOS,variant=Mac Catalyst' build
```

On this Mac, Xcode is a beta: prefix commands with
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

## The rule that keeps the tests possible

`TnT/Models.swift` and `TnT/Sync.swift` import **Foundation only**. No SwiftUI,
no UIKit. `Tests/run.sh` compiles exactly those two files with `Tests/main.swift`,
which is why the model layer can be tested in a second without a simulator.

Anything worth testing — date rules, merging, CSV, names and matching — belongs
there, not in a view. Logic that must live in `TodoStore` should be thin enough
to read at a glance, or pushed down into the model layer as a pure function
(`StoreDocument.canonicalizingProjects()` is the pattern).

## Never touch the real data

`DocumentStorage` is hard-wired to `~/Library/Application Support/cards.json`
and, when one is configured, to the user's sync file in iCloud Drive.

- **Never construct a `TodoStore` in a test or a script.** It would read and
  write those files.
- **Don't launch the Mac app to try something out.** It shares the user's live
  cards and sync file. Build it to check it compiles; test behaviour on the
  simulator, which has its own container.
- Seeding the simulator with a copy of real data is fine; say so afterwards.

## Sync, and why edits are stamped carefully

Two devices merge one JSON file per card by `modifiedAt`, with tombstones for
deletions. Two consequences:

- **A derived change must not bump `modifiedAt`.** Filing a dated card, or
  folding duplicate projects, is computed identically on every device. Stamping
  it would let an idle device outrank a real edit made elsewhere. A tie keeps
  the local copy, and the pass runs again after every merge.
- **A change to the file format must decode older files.** Every `init(from:)`
  is hand-written with `decodeIfPresent`, because a synthesised decoder demands
  every key and would throw away the user's cards. New CSV columns go last, so
  header-less older exports still read by position.

## House style

- Comments say **why**, not what. A comment that explains a non-obvious choice
  earns its place; one that narrates the next line does not.
- User-facing wording is plain and sentence case: "Move to Group", not "Move
  Tag Into Group". Say what happened, not that it succeeded.
- Both platforms at once: this is one target. A change to a card, a sheet or a
  gesture lands on the phone and the Mac together — check the Mac path
  (`#if targetEnvironment(macCatalyst)`) when touching gestures or menus.
- Dark mode is not an afterthought. Colours on cards are checked for contrast;
  category tints are lightened in dark mode for exactly that reason.

## Build numbers

The build number is stamped by a script phase from `git rev-list --count HEAD`,
into the built app only — never into the project, so it leaves no diff. App
Store Connect refuses a build number it has already seen, and this one only
ever grows.

Two things make it work, and both look redundant until they are removed:

- The phase declares the built `Info.plist` as an **input**, so Xcode schedules
  it after the step that writes that file. Without it the stamp is overwritten.
- `ENABLE_USER_SCRIPT_SANDBOXING = NO`, because the sandbox hides `.git` and
  git then reports "not a git repository".

## Finishing a change

Run the tests, build both platforms, then commit with a message that explains
the reasoning. Leave pushing to the user unless asked. If the change alters how
the app behaves, update `docs/PROMPT.md` in the same commit.
