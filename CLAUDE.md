# Working on DayHand

A to-do app for iPhone and Mac: one SwiftUI target, no third-party
dependencies. `README.md` describes the app; `docs/PROMPT.md` is the full
specification and is the place to record a decision about how the app should
behave.

## Commands

```sh
# Tests — no Xcode project, no simulator, no app data. Run these first.
Tests/run.sh

# Build for the phone and for the Mac. Both must pass before anything is done.
xcodebuild -project DayHand.xcodeproj -scheme DayHand \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project DayHand.xcodeproj -scheme DayHand \
  -destination 'platform=macOS,variant=Mac Catalyst' build
```

The selected toolchain is the **released** Xcode at `/Applications/Xcode.app`,
so the commands above need no prefix. A beta may also be installed alongside it
— never build an upload with that one: App Store Connect rejects anything built
against a beta SDK, and the version number alone does not tell you (27.0 beta
is build 27A5252f, the release is 27A266a).

## The rule that keeps the tests possible

`DayHand/Models.swift` and `DayHand/Sync.swift` import **Foundation only**. No SwiftUI,
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
- **Check a hand-written `cards.json` before loading it**: `Tests/run.sh
  path/to/file.json` decodes it and says why if it will not. The app answers a
  file it cannot read by silently replacing it with the starter document, which
  looks exactly like the seed having no effect. Two traps: `deletedCards`,
  `deletedCategories` and `deletedProjects` are **maps** of id to tombstone
  date, not arrays; and timestamps take exactly three fractional digits
  (`2026-09-26T09:15:00.123Z`), so Python's default microseconds throw.
- The Mac window cannot be checked from here — the app shares the live file,
  and screen capture needs a permission this process does not have. A **wide
  iPad simulator is the proxy**: the sidebar layout keys off size class, not
  `#if targetEnvironment(macCatalyst)`, so the iPad shows the Mac's layout.

## Dates never move cards

Two optional fields, deliberately separate: **`deadline`** (a day, when the
work is due) and **`remindAt`** (a day and a time, when to be interrupted).
Neither moves a card, and moving a card keeps both. There is no filing pass,
no auto-stack rule and no Later date floor — those existed only to serve
automatic filing, and their absence is the feature.

`dueDate` is read once as a migration and **never written back**. That is the
only thing stopping a version that still files cards from doing it again: it
would ignore any flag it did not recognise, but it cannot file a date it cannot
see.

A reminder leaves the review for one reason: the user answered it. Dismissing
the notification is explicitly not an answer — see
`UNUserNotificationCenterDelegate` in `ReminderScheduler.swift`, which posts
only on the default action.

## Sync, and why edits are stamped carefully

Two devices merge one JSON file per card by `modifiedAt`, with tombstones for
deletions. Two consequences:

- **A derived change must not bump `modifiedAt`.** Filing a dated card, or
  folding duplicate projects, is computed identically on every device. Stamping
  it would let an idle device outrank a real edit made elsewhere. A tie keeps
  the local copy, and the pass runs again after every merge.
- **Anything seeded is stamped `.distantPast`.** The three default categories
  carry fixed ids, so they collide with every other install's copy of
  themselves and a merge must choose between them. Stamped with the install's
  clock, a brand-new device arrives claiming the freshest edit and renames
  "Research" back to "Home" everywhere — which is exactly what happened to the
  real file on 26 September 2026. A default is not an edit and must lose to
  one. The same goes for the seeded TRIP project.
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

## The Mac build is sandboxed; the iPhone build's settings are not touched

App Store Connect refuses a macOS upload that is not sandboxed, so TestFlight
for Mac needs `com.apple.security.app-sandbox`. It is set in
`DayHand/DayHand-Mac.entitlements`, wired in through
`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` so it applies to Mac Catalyst only — iOS
is sandboxed by the system and must not carry these keys. Check after touching
signing: `codesign -d --entitlements - --xml <app> | plutil -p -`.

The sync file is user-picked, so the sandbox also needs
`files.user-selected.read-write` and `files.bookmarks.app-scope`; the latter is
what makes `DocumentStorage`'s `.withSecurityScope` bookmark resolve on a later
launch rather than failing silently.

**The sandbox moves where the Mac app's data lives.** `NSHomeDirectory()`
becomes the container, so `~/Library/Application Support/cards.json` becomes
`~/Library/Containers/com.andremouraux.tnt/Data/Library/Application Support/cards.json`,
and `UserDefaults` — which holds the sync-file bookmark — moves with it. A Mac
that was running an unsandboxed build therefore opens the sandboxed one with no
cards and no sync file. Nothing is lost: the old file stays where it was, and
choosing the sync file again in Settings brings everything back. Say so before
anyone installs it.

## Uploading to App Store Connect

Three things it refuses, each learned the hard way:

- **A beta SDK.** Archive with the released Xcode, not the beta.
- **A development signature.** Xcode archives with a development identity and
  re-signs at export, but only if an **Apple Distribution** certificate exists
  (Xcode → Settings → Accounts → Manage Certificates → + ). Distribute through
  **App Store Connect → Upload**; "Release Testing" and "Debugging" produce
  development-signed builds it will not take.
- **A repeated build number.** Nothing to do: the stamp below handles it.

An iPad build must also declare all four orientations, or the bundle is
rejected for multitasking.

## The site

`docs/` is the GitHub Pages site — `index.html`, the app icon, and screenshots
under `docs/screenshots/`. Pages serves it from the `main` branch, `/docs`
folder, at <https://amouraux.github.io/DayHand/>.

- **Screenshots come from a simulator seeded with dummy data**, never from real
  cards: `xcrun simctl io <device> screenshot --type=png docs/screenshots/x.png`
  works even when the simulator has stopped accepting taps. Wait for animations
  to finish — a sidebar caught mid-slide looks like a layout bug.
- `docs/screenshots/mac.png` can only be taken on a real Mac, so the page drops
  any screenshot that 404s (`onerror` on the `img`) rather than showing a hole.
- `header`, `section` and `footer` all carry `class="wrap"`, so vertical
  padding has to be written as `section.wrap { ... }`: a bare `section` selector
  loses to `.wrap` and is silently discarded.

## xcodebuild can say SUCCEEDED without relinking

Twice now an edit has been "verified" against a binary that predated it: the
build reports **BUILD SUCCEEDED**, `simctl install` reports success, and the app
on screen is the one from half an hour ago. When a change does not appear and
the code plainly says it should, check the product before debugging the code:

```sh
stat -f '%Sm' ~/Library/Developer/Xcode/DerivedData/DayHand-*/Build/Products/Debug-iphonesimulator/DayHand.app/DayHand
```

If that timestamp is older than the edit, `touch` the file and build again.
Believing the screenshot over the timestamp costs far more than the check does.

## Finishing a change

Run the tests, build both platforms, then commit with a message that explains
the reasoning. Leave pushing to the user unless asked. If the change alters how
the app behaves, update `docs/PROMPT.md` in the same commit.
