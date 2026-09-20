# Rebuild prompt — "TnT"

Build an iPhone app in SwiftUI (iOS 17+, no third-party dependencies) called **TnT**
(Today aNd Tomorrow): a to-do app where every task is a card in a single
scrolling vertical stack.

## Core model — read this first, it drives everything

A card has four independent properties. Nothing is derived from anything else:

1. **Stack** (required) — one of `INBOX`, `TODAY`, `TOMORROW`, `LATER`, `COMPLETED`.
2. **Category** (optional) — one the user defined in Settings.
3. **Due date** (optional) — a specific day.
4. **Title** (required).

**An undated card's stack is stored, never computed.** A card placed in Tomorrow
with no date is still in Tomorrow next week and next year. Nothing rolls over as
time passes; only the user moves it. For undated cards, Today / Tomorrow / Later
are named lists you file things into, not calendar queries.

**A date, however, files the card.** Dating a card today puts it in Today; dating
it tomorrow puts it in Tomorrow. A date further out leaves the card where it is
and only affects its position within that stack.

Because days turn, this filing must be re-applied every time the app loads and
every time it returns to the foreground — a card dated tomorrow sits in Tomorrow,
and when that day arrives its date now reads "today", so it belongs in Today.
Apply it at load time, before the first render: mutating the list from `onAppear`
leaves rows painting their previous stack's colour after they have moved section.

Filing must never stamp a card as edited. It is derived, not edited: every
device computes the same stack from the same date and the same calendar day, so
it needs no syncing at all. Stamping it would let a device that merely sat there
overnight outrank a real edit made on another device just before midnight and
not yet synced, and every device runs this pass at the same moment. A tie on the
edit timestamp keeps the local copy, and the pass re-runs after every merge, so
devices converge on the same stack without the change ever being transmitted.

It must also survive a session that outlives the day it began in — a window left
open overnight would otherwise still be showing yesterday's stacks in the
morning. Watch for the day turning three ways, all landing on the same idempotent
check (re-file only if the calendar day differs from the one last filed for):
the system's day-changed notification, the significant-time-change notification
(which also covers timezone and DST shifts), and a slow repeating timer as the
backstop for a machine that was asleep when midnight passed.

An overdue date files a card into Today: a card that is late belongs with today's
work, not stranded in the stack it was written into. Overdue is *also* flagged in
place (see Card appearance).

A deliberate move beats a date. If the user moves a dated card into a stack its
date contradicts, drop the date rather than letting the next launch drag the card
back — otherwise manual placement and the date fight each other.

## Screen

One screen, no app title and no navigation bar. A vertically scrolling stack of
cards grouped into five sections, in this fixed order: Inbox, Today, Tomorrow,
Later, Completed.

- Section headers are large — the size an iOS large navigation title would be —
  showing the name plus a small dimmed count. They scroll with the content
  rather than pinning; a pinned header parks under the status bar and collides
  with the clock.
- Empty sections are hidden entirely.
- When there are no cards at all, show an empty state inviting the user to tap +.
- A round floating **+** button in the bottom-right corner.

## Scroll position

On launch the list opens parked at the **top of Today**, not at the top of the
list — Inbox sits above it and is reached by scrolling up, everything else by
scrolling down. If Today is empty, fall back to the nearest non-empty section
below it so the jump never silently does nothing.

A small round button in the **top-right** corner scrolls back to that same Today
position, animated. Give these floating buttons a **solid background and a
shadow**, not a thin material: over a pale list background a material-filled
circle nearly disappears. It sits alone: the Filter and Settings buttons go in the
**bottom-left** corner, mirroring the + button, so nothing crowds the top of the
list and nothing sits close enough to Today to be hit by mistake.

## Adding cards

Tapping + opens a half-height sheet titled **New Task**, with a text field and
Add / Cancel. Add is disabled while
the field is empty.

The sheet also offers a **stack** (defaulting to Inbox; Completed is not
offered), a **category** and a **due date**, all optional. The date
starts **empty**; the category starts on the **default set in Settings** (or empty
if there is none) — the date behind a toggle, using the *compact* date picker
so the sheet stays half-height rather than filling the screen — typing a title and tapping Add must stay the fast path,
with nothing else to dismiss or clear.

The title field wraps onto a second line as you type, which means Return is
delivered to it as a line break and never as a submit. Return must add the card.
Turn a typed line break back into the submit it was meant to be, and tell it
apart from newlines arriving in *pasted* text — those fold into spaces and leave
the sheet open. Guard the add itself so that a platform delivering Return by
both routes at once files one card, not two.

Keep the stack and date **reconciled live**, using the same rules as the rest of
the app, so a card can never be created in a state the next launch would
immediately correct:

- Picking a date of today or tomorrow moves the stack picker to match.
- Picking a stack by hand wins over a contradicting date, which is dropped —
  exactly as moving an existing card does.
- Choosing Later pushes a too-soon date forward to the earliest day Later
  allows, and restricts the picker's range, rather than changing the stack.

The last one matters: switching the date on defaults it to today, and without
the Later exception that silently drags the stack to Today and undoes the user's
explicit choice.

The footer says where the card is actually going.

## Tapping a card

Raises a short dialog listing only the **stacks the card is not already in**.
One tap moves it. Nothing else is offered — filing is the common case and it
should cost two taps total, with no menu to read.

## Swipe gestures

The cards live in a ScrollView, not a List, so implement these as a drag gesture,
not `.swipeActions`. The gesture must yield to vertical scrolling: only engage
once the drag is more horizontal than vertical.

- **Swipe left** — moves the card to Today. For a card already in Today, it
  moves on to Tomorrow instead. This works from every stack, so a completed card
  swiped left comes back to life in Today.
- **Swipe right** — opens the **editor**: the card's name in an editable field,
  plus Stack, Category, Due date, Complete and Delete. Everything a card has,
  in one place.

Feel: reveal a coloured panel behind the card that grows as you drag, ~96pt
commit threshold, resistance past that, capped travel, and a haptic tick the
moment the gesture arms. The move panel wears the **destination stack's own
colour and name** — blue "Today", or orange "Tomorrow" for a card already in
Today — so the gesture previews where the card will land. Indigo "Category" for
the other direction.

Name the two callbacks by intent (move / choose category), not by direction, and
decide which direction triggers which in exactly one place. Direction-named
callbacks make swapping the two an error-prone edit across several files.

Completion is not a swipe: it is the checkbox on the card, and the tap menu.

One trap to avoid: a card that moves stack keeps its identity, and if rows are
identified by that alone SwiftUI reuses the old row without feeding it the new
card — it keeps painting the previous stack's colour and a date it no longer has.
Include the stack in each row's view identity.

## Categories and Settings

Categories are **defined by the user**, not fixed. A category is a **label**, an
**icon**, and a **colour**. Cards display only the icon; the label names the
category in Settings, in the picker, and to VoiceOver.

A gear button in the top-left corner opens Settings, where the user can add,
edit, reorder and delete categories. Deleting one strips it from every card that
used it — the cards themselves are kept — and the confirmation should say how
many cards are affected.

Offer a palette of category colours **disjoint from the stack colours** (so not
gray, blue, orange or green) and from red: indigo, purple, teal, pink, brown and
yellow work. A category icon has to stay legible sitting on a stack-coloured
card. Offer a grid of SF Symbols to pick the icon from.

One category may be marked the **default for new cards**, chosen in a "New cards"
section of Settings and badged in the category list. It is a pre-selection, not a
constraint: the compose sheet shows it as an ordinary picker value the user can
change, including back to None. Store the default **on the document with its own
timestamp**, not as a flag on each category — otherwise two devices can each set
a different one and both end up marked. Deleting the default category clears it,
and a merge that removes the category must not leave the default dangling.

Seed three categories on first run — Research (flask), Teaching (graduationcap),
Personal (house) — so the app isn't empty, and give them fixed ids so cards
written before categories were editable still resolve.

## Projects

Most work cards begin with a subproject code — a course (LKNR1307), a study
(SFRD2026). Make that a first-class **project**: one optional project per card,
typed as `#CODE`, shown as a coloured prefix.

- **A project is its own record** (id, name, optional category, archived flag,
  `modifiedAt`), referenced by id from the card — never text inside the title.
  That is what makes renaming one edit instead of a rewrite of every title, and
  it syncs with the same `modifiedAt` + tombstone rules as categories.
- **Names match without regard to case, accents or a leading `#`**, and are
  shown as first written. A name is one word (spaces removed), so a space can
  finish it.
- **A project fills in its category.** Choosing `#LKNR1307` sets Teaching; the
  card can still be moved to another category.
- **Entry (New Task).** Typing `#` plus letters shows matching projects as chips
  under the field (prefix matches first, then contains; most recently *created*
  in first — not last edited, because converting or merging touches every card).
  Tap a chip, or type a space to take the word literally (existing if it
  matches, otherwise new). An unknown word offers "Create #…". Before anything
  is typed, the five most recent projects are already shown as chips, so the
  common case is one tap. On the iPhone keyboard `#` is two layer-switches away,
  so put a `#` button inside the title row — a keyboard-toolbar button did not
  appear in this sheet. The chosen project sits as a pill before the title; tap
  it to remove it. A new project is only created when the card is added, so a
  cancelled sheet leaves nothing behind. Top-align the row: an empty vertical
  text field reports its placeholder's baseline lower than typed text.
- **On the card** the project leads the title in the card's category colour
  ("**LKNR1307** slides"), as one run of text, so the card is no taller. Yellow
  is darkened to ochre in light mode. There is no way to remove a project from
  the card face — that is the editor's job.
- **Sort** within a tier by the displayed text (project + title), which keeps a
  project's cards together exactly as they were when the code lived in titles.
- **Editor** gets a Project row: a menu of projects (plus None and New Project…).
- **Filter** selects any mix of categories and projects; a card shows if it
  matches any. Projects are listed under their category with open-card counts,
  and are searchable. On the Mac, right-click a card for "Show Only <project>";
  while any filter is on, that item becomes "Show All" on every card.
- **Settings → Projects**: grouped by category, with open · total counts.
  Rename (one edit, every card; renaming onto an existing name asks to merge),
  change category, archive (kept, not suggested; typing its name revives it),
  merge into another, delete (cards keep their titles, lose the project).
- **Converting old titles** is a one-time, reviewed step, never automatic:
  list first words used as prefixes, with their card counts and sample titles.
  Code-like words (no lowercase letters, or letters with digits: NF, LKNR1307)
  start ticked; ordinary words used on several cards (Payer, Email) start
  unticked. Flag near-duplicates (SFRD vs SFRD2026) with a "Merge into" choice.
  Strip the word and any following `-`/`:` from the title; never convert a
  one-word title. A new project takes the category most of its cards have.
- **Groups (clusters) of projects**, such as Grants vs Ongoing within Research.
  A group is a plain optional label on the project (`group`), not a record
  of its own: a category's groups are the distinct labels its projects carry,
  so a group exists while something is in it, nothing lingers, and syncing
  needs no new machinery (the label travels with the project's `modifiedAt`).
  Labels may be several words; they match without regard to case or accents,
  and the first spelling in use names the group. Groups belong to a category:
  moving a project to another category clears its group. **Organise them in
  the Filter sheet**, where tapping keeps its one job (select): long-press a
  project (right-click on the Mac) for a flat menu headed "Move <project> to
  Group" listing the category's groups, New Group… and No Group; long-press a
  group heading for Rename Group… (renaming onto another group's name joins
  them). Group headings sit inside the category section with the grouped
  projects indented beneath them, followed by ungrouped projects; tapping a
  heading selects all its projects (or clears them when all are selected).
  Headings use primary, not secondary, text — dimmed rows read as disabled.
  Settings → Projects shows the same grouping read-only. Cards, New Task
  chips and the editor's project menu are untouched.
- **Two devices creating the same project offline** would both survive a merge.
  After every load and merge, fold same-name projects into the one with the
  lowest id, remap cards to it without stamping them, and tombstone the others
  at their own `modifiedAt` — so every device independently makes the same
  choice and writes the same tombstone.
- **CSV** gains `project` and `group` columns, written *last* so header-less old files
  still read by position. On import, a `project`/`course`/`hashtag` column, or a
  title starting with `#CODE `, sets the project (created if new). `tag` still
  means category, as before. A `group` (or `cluster`) column puts the row's
  project in that group — the first row naming a group for a project wins —
  and an empty one leaves the project's group alone, so an older file never
  takes a project out of its group.

## Filtering

A filter button beside the Settings button opens a sheet listing **All
Categories** plus each category, and **any number can be selected at once**. Use
a sheet rather than a menu: a menu closes after every tap, which makes
multi-select painful. The list narrows as choices are made, behind the sheet.

Selecting nothing means everything. Selecting one or more shows only cards
carrying one of them — an uncategorised card is *not* shown, since it belongs to
none of the chosen categories.

The button reflects the state: the plain filter glyph when nothing is chosen,
the category's own icon and colour when exactly one is, and the **count** when
several are — no single icon can stand for several. Deleting a category removes
it from the selection, so the list is never filtered by something that no longer
exists.

## Later and dates

Later means "explicitly not soon", so a card *put* in Later may not be *given* a
date that is today, tomorrow, or in the past. Prevent it at the picker: for a
card in Later the date picker starts at the day after tomorrow, so the
contradictory dates are never offered. Say why in a caption under the calendar.

What a Later card may do is mature. A card dated next Friday and left in Later is
fine until Friday comes round — and on that day it is filed like any other card,
into Today or Tomorrow. Dating a card in Later is making an appointment, and when
the appointment arrives the card has stopped being "later"; nothing is gained by
stopping to ask.

Because that is the one move the user did not ask for and would not otherwise
notice, say what happened. A transient banner at the top of the list, not an
alert: the move is already made and correct, so there is nothing to decide, only
something to notice. Name the card if there is one ("Renew passport" moved to
Tomorrow), otherwise count them and their destinations. It clears itself after a
few seconds so it cannot sit on the Today button, and a tap dismisses it at once.
Only cards raised out of Later are worth reporting — every other move the filing
pass makes is what the user already expects.

## Sort order

**Within INBOX, TODAY, TOMORROW and LATER**, in this priority:

1. Cards dated today — and overdue cards — first
2. Then cards dated tomorrow
3. Then everything else (undated cards and cards dated further out, together)

Alphabetical by title within each of those three tiers, case-insensitive and
number-aware (so "item 2" precedes "item 10").

**Within COMPLETED**, ignore that rule entirely: sort by completion time, most
recently completed on top.

## The COMPLETED archive

Show only the 20 most recent. Below them a **More… (N)** button, where N is how
many remain hidden; each tap reveals 20 more. Once everything is visible the
button becomes **Show Less**, collapsing back to 20. With 20 or fewer completed
cards, no button appears.

## Card appearance

Each card has **one flat background colour, taken from its stack**. Keep it
low-opacity over the system card colour so text stays readable in light and dark
mode.

Stack colours: Inbox gray, Today blue, Tomorrow orange, Later green. Completed
carries **no wash at all** — the strikethrough, filled checkmark and dimming
already say "done", and every remaining colour is spoken for. Red is reserved
exclusively for overdue.

Each card shows:

- A checkbox on the left that toggles completion.
- The title, struck through and dimmed when completed.
- The category as **its coloured icon alone — no text label** — placed just
  after the checkbox and *before* the title, on the title's line. The slot is
  reserved even when the card has no category, so the icons form a column and
  every title starts at the same x. Draw the symbol as `Text(Image:)` rather
  than a plain `Image`, or it aligns by its own box and sits visibly above the
  text baseline. Same on both platforms.
- Its date as a relative label ("Today", "Tomorrow", "Tue, 1 Sep"). If the date
  has passed, show it in red and outline the card in red — but **leave the card
  where it is**; overdue is flagged, never moved.
- For completed cards with no date, a caption naming the stack it came from.

## Persistence and sync

One JSON document holding categories, cards, and tombstones. Written to **iCloud
Drive's ubiquity container** when it is available so a companion Mac app shares
the same data, and to Application Support otherwise — a user not signed into
iCloud must still get a working app.

Note that a **free Apple developer account cannot sign the iCloud entitlement** —
Xcode refuses with "Personal development teams do not support the iCloud
capability". Keep the entitlement easy to switch off so the app still installs on
a device without a paid membership, falling back to local storage.

**Offer a second route that needs no entitlement:** let the user pick their own
sync file through the document picker and keep access with a **security-scoped
bookmark**. Put that file in iCloud Drive and the system syncs it between
devices — access is granted by the user choosing the file, not by the app
claiming a container. The picked file takes precedence over both the ubiquity
container and local storage; keep writing the local copy too, so the app still
works if the file is moved or deleted.

Three things this needs to actually work on iOS:

- **The device must be signed into iCloud** for iCloud Drive to appear in the
  document picker at all. No entitlement is involved — the picker runs out of
  process — but a simulator with no Apple ID simply has nowhere to browse to.
- **A file in iCloud Drive may be a placeholder**, not yet downloaded. Reading it
  then returns nothing, which is indistinguishable from an empty file. Call
  `startDownloadingUbiquitousItem(at:)` and wait for
  `ubiquitousItemDownloadingStatus == .current` before reading.
- **Keep the picker's allowed types broad.** A file copied or renamed between
  devices may not be reported as JSON, and a greyed-out file cannot be picked at
  all. Setting `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`
  also gives the user an "On My iPhone" folder to fall back on. Adopting a file offers the same choice: **merge with this device**, or **replace
the cards on this device** with the file's. Merge must be the default shape —
overwriting silently would wipe one side the moment a second device is set up.

The two are not symmetric, and getting this wrong is destructive. Deleting cards
normally leaves **tombstones** so the deletion propagates. Replacing on adopt
must *not*: those cards are being abandoned, not deleted, and tombstoning them
would push straight back into the file being adopted and erase the very cards
just taken from it. Drop them and their tombstones instead. Refuse to replace
from a file holding no cards.

Settings also offers **Delete All Cards**, behind a confirmation naming the
count. That one *does* tombstone, so it reaches the other device. Categories
survive it.

**Update live rather than only on foreground.** While the app is on screen, keep
an `NSFilePresenter` on the shared file — it fires as soon as another device (or
iCloud finishing a download) writes to it — *and* poll its modification date
every few seconds as a backstop, since a presenter does not catch every way a
file can be replaced. Tear both down when the app leaves the screen. The
re-read must bail out when the file already matches what is held in memory,
or a write triggers a notification that triggers a write.

**iCloud does not merge simultaneous writes.** When two devices write the file
at once it keeps one copy as the current file and parks the others as
*unresolved conflict versions*. Reading only the current file silently discards
whatever the other device wrote — exactly the case concurrent editing produces.
Read `NSFileVersion.unresolvedConflictVersionsOfItem(at:)`, fold every copy
through the same merge, and mark them resolved **only after** the merged result
has been written back, so a failed write cannot lose the copy it came from. The
fold must be order-independent: the file system reports those versions in no
particular order.

One trap: **`URL` caches its resource values.** Polling the modification date
through a stored `URL` can keep returning the value it first saw, so the poll
never fires. Copy the URL and call `removeAllCachedResourceValues()` before each
probe — the same applies to checking an iCloud download's status in a loop.

Resolve the iCloud container **off the main thread**; `url(forUbiquityContainerIdentifier:)`
blocks, sometimes for seconds. Start on the local copy, adopt the cloud one when
it resolves, merge the two, and keep watching for writes from the other device
with an `NSMetadataQuery`. Read and write through `NSFileCoordinator`.

**Merging must not need to know which device is "newer".** Give every card and
category a `modifiedAt`, and resolve each one independently — latest edit wins.
Record deletions as **tombstones** (id → time deleted): without them, deleting a
card on one device and merging with another that still has it silently brings it
back. A deletion beats an edit only if it happened after that edit, so an edit
made later can deliberately resurrect a card.

Two traps, both of which cause silent data loss:

- Swift's **synthesised `Codable` decoder requires every key**, even for
  properties that have default values. Add a hand-written `init(from:)` that uses
  `decodeIfPresent` wherever a field was introduced later — otherwise a document
  written by an older build fails to decode and gets replaced with an empty one.
- **Timestamps must survive a round-trip.** Plain `.iso8601` rounds to whole
  seconds, and even with fractional seconds the format only holds milliseconds
  while `Date()` carries more. Stamp times at millisecond resolution so what is
  written is exactly what is read back.

Decode defensively throughout: missing keys and unknown enum values degrade
gracefully (an unknown category becomes none) rather than throwing away the
file, and an untimestamped card reads as `.distantPast` so any real edit wins.

## macOS

The same target runs on the Mac via **Mac Catalyst** — set `SUPPORTS_MACCATALYST = YES`
and `TARGETED_DEVICE_FAMILY = "1,2,6"`. No code changes are needed: the model,
store and sync layers are Foundation-only, and the views' UIKit-flavoured
pieces (`Color(.systemGroupedBackground)`, `presentationDetents`,
`UIImpactFeedbackGenerator`, the compact date picker) all exist under Catalyst.

Two things to know:

- **The two apps only share data through iCloud.** Unsandboxed, the Mac build
  writes to `~/Library/Application Support/cards.json` while the phone writes to
  its own container. They converge only once both carry the iCloud entitlement,
  which needs a paid developer account.
- The layout was designed for a phone. In a wide Mac window the cards stretch
  the full width; cap the list's width if that reads badly.
- Because it is one target, behaviour changes land on both platforms at once —
  there is no second codebase to keep in step. But the swipes become
  **click-and-drag** on a Mac: a two-finger trackpad swipe scrolls instead. So
  the Mac also offers **Edit on a right-click** (a context menu), with the swipe
  left in place for anyone who wants it.

A fully native AppKit-backed Mac target is possible instead — share Models,
Sync and TodoStore, rewrite the views — but the swipe gestures, half-height
sheets and floating buttons do not translate, so the layout would change.

## CSV import and export

Settings offers **Export Cards as CSV…** and **Import Cards from CSV…** through
the system save and open panels.

Columns: `id, title, stack, category, due, completed, created`.

**Parse the due column leniently.** Only the app's own export uses `yyyy-MM-dd`;
open that file in a spreadsheet and the column comes back in the user's locale,
and hand-written files use whatever the author typed. Accept the common shapes —
`yyyy/MM/dd`, `dd/MM/yyyy`, `dd-MM-yyyy`, `dd.MM.yyyy`, `d MMM yyyy`, a full ISO
timestamp — plus the device's own short and medium date styles, and normalise to
the start of the day. A due date that silently fails to parse looks exactly like
a card that never had one. The category is
written as its *label*, and matched back case-insensitively on import; an
unknown name leaves the card uncategorised rather than inventing a category.
Dates are `yyyy-MM-dd`, timestamps ISO 8601.

Import offers two modes, chosen before the file picker opens: **add to what is
here**, or **replace all cards**. Either way it matches **by id** — a card
already present is updated, anything else is added — and clears any tombstone
for an imported id, or a previous delete would immediately remove it again.

Refuse to replace when the file turns out to hold no usable rows: obeying would
empty the device and put nothing back.

Three things a naive implementation gets wrong:

- **Quote properly.** Titles contain commas, quotes and newlines. Write a real
  escaper and a real parser, not `split(separator:)`.
- **Locate columns by header name, not position**, with synonyms accepted
  (`name`/`task` for title, `list`/`bucket` for stack). A file that has been
  reordered in a spreadsheet must still import correctly. Fall back to the
  canonical order only when there is no recognisable header.
- **`\r\n` is a single `Character` in Swift.** Matching only `"\n"` and `"\r"`
  silently swallows every line break in a CRLF file — which is what Excel
  writes — and imports the whole thing as one row.

## Backups

Take one backup a day, the first time the app opens that day, into three
rotating slots: the most recent, the day before, and one from about a week ago.
The weekly slot only takes over when it is genuinely seven days behind,
otherwise it just shadows the dailies and the third point in time is wasted.
Opening the app repeatedly in one day must not churn the chain, and a long gap
with the app unopened should still rotate exactly once.

Settings lists them with their age and card count; tapping one restores it
behind a confirmation.

Restoring is a rescue, so it has to win: stamp the restored cards as edited now
and clear their tombstones, or the very delete being undone will simply reapply
from the other device. Cards added since the backup are dropped locally but
**not** tombstoned — they are not what the user asked to remove, so if the other
device still has them they come back on the next sync.
