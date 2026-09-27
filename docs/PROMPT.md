# Rebuild prompt — "DayHand"

Build a SwiftUI app (iOS 17+, one target for iPhone, iPad and Mac, no
third-party dependencies) called **DayHand**: a to-do app where every task is a
card in a single scrolling vertical stack.

## Core model — read this first, it drives everything

A card has five independent properties. Nothing is derived from anything else:

1. **Stack** (required) — one of `INBOX`, `TODAY`, `TOMORROW`, `LATER`, `COMPLETED`.
2. **Category** (optional) — one the user defined.
3. **Project** (optional) — one the user defined.
4. **Due date** (optional) — a specific day.
5. **Title** (required).

**An undated card's stack is stored, never computed.** A card placed in Tomorrow
with no date is still in Tomorrow next week and next year. Nothing rolls over as
time passes; only the user moves it. For undated cards, Today / Tomorrow / Later
are named lists you file things into, not calendar queries. This is the whole
point of the app: a job that takes four days can sit in Today for four days, and
nothing ever marks it late.

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

## Identity

Named **DayHand**: a deck of cards, dealt a day at a time. Short enough for a
home-screen label, and it says what the app is.

The app icon is three cards fanned out: a white one in front carrying a blue
tick and two lines, a sunrise-orange one behind it with a sun, and a deep blue
night card with a moon and stars. Today and tomorrow, said without a word.

**No lettering** — an iOS icon almost never contains text, and at home-screen
size a word turns to mush. Supply it **full bleed**, 1024 square, no
transparency and no rounded corners of its own: iOS applies its own mask, and
artwork that arrives already rounded shows the page in the corners and a second
edge inside the system's. One icon serves both appearances.

## First run

A new install opens with a handful of **sample cards** that explain the app by
being it: two in Today, two in Tomorrow, one in Later carrying a project and a
date, one in Inbox, one already completed.

Mark them, and clear the mark the moment the user edits one. The samples still
untouched are swept away the first time real cards arrive from another device,
so a second device set up later never pushes tutorial cards into the shared
file. Drop them without tombstones: they were never anywhere else.

The seeded categories are **Home** (house, teal), **Work** (briefcase, indigo)
and **Courses** (graduationcap, purple) — three that suit most people,
renameable like anything else. Give them **fixed ids** so a card written before
categories were editable still resolves, and match an old file's fixed category
names by label rather than by position, or renaming the seeded three would refile
old cards under the wrong one.

**Everything seeded is stamped `.distantPast`** — the categories and the sample
project — not with the clock of the machine it was installed on. Those fixed ids
collide with every other install's copy of themselves, so a merge always has to
choose between two versions of the same three categories. Stamped "now", a
brand-new device arrives holding what looks like the most recent edit of all
three and renames them back to the defaults on every other device. A default is
not an edit and must lose to one.

## Languages

English, French, Dutch, German, Spanish, Italian and Portuguese, through a
String Catalog.

**More** carries a **Language** row showing the language the app is being read
in, which opens the system's own per-app language screen. Nothing is
reimplemented: iOS gives any app shipping more than one localization its own
Language screen, and macOS keeps the same choice in Language & Region. An
in-app override would mean restarting the app to take effect, and would
disagree with what the system believes. No right-to-left language: the swipe
gestures are written in terms of left and right, and mirroring them is work this
has not done.

Three things are easy to miss:

- **The stack names live in the model layer** (`Bucket.title`) and are shown in
  headings, pickers and sentences such as "Move to Tomorrow". They must be
  localized like any other visible text, or the screen reads half-translated.
- **Counts need real plurals.** Building them as `"\(n) card" + (n == 1 ? "" : "s")`
  cannot be translated; give the catalog the whole sentence and let it vary.
- **Seeded data is translated once, at first run** — the categories and the
  sample cards. It is data from then on: changing the device language later
  leaves what is already there alone, because renaming someone's categories
  behind their back would be worse than a mixed-language page.

## Screen

One screen, no app title and no navigation bar. A vertically scrolling stack of
cards grouped into five sections, in this fixed order: Inbox, Today, Tomorrow,
Later, Completed.

- Section headers are large — the size an iOS large navigation title would be —
  led by the stack's own symbol in the stack's colour (the same symbols the
  pickers use, so a stack looks the same everywhere; COMPLETED's tint is clear,
  so its symbol takes the secondary colour), then the name and a small dimmed
  count. The symbol is a glyph, not an image view, so it sits on the title's
  baseline, and it is smaller than the display-sized title so the name still
  leads. They scroll with the content rather than pinning; a pinned header parks
  under the status bar and collides with the clock.
- Empty sections are hidden entirely.
- When there are no cards at all, show an empty state inviting the user to tap +.
- A round floating **+** button in the bottom-right corner.
- The floating circles are **48pt across**, not smaller: 44pt is the minimum a
  finger can reliably hit, and a 42pt circle that looks right in a screenshot is
  missed in use. Keep the bottom row clear of the home indicator, which takes
  touches from the strip along the edge.

The bottom-left row holds, in order, **filter**, **search** and **More**. Filter
leads: on a wide window it is the sidebar's switch, and a switch belongs against
the edge the sidebar comes from. The two narrowing tools then sit together, with
More last.

## Scroll position

On launch the list opens parked at the **top of Today**, not at the top of the
list — Inbox sits above it and is reached by scrolling up, everything else by
scrolling down. If Today is empty, fall back to the nearest non-empty section
below it so the jump never silently does nothing.

A small round button in the **top-right** corner scrolls back to that same Today
position, animated. Give these floating buttons a **solid background and a
shadow**, not a thin material: over a pale list background a material-filled
circle nearly disappears. It sits alone, mirroring the + button, so nothing
crowds the top of the list and nothing sits close enough to Today to be hit by
mistake. It stands down while the search bar is open: the bar wants the width,
and there is nothing to jump over in a handful of results.

## Adding cards

Tapping + opens a half-height sheet titled **New Task**, with a text field and
Add / Cancel. Add is disabled while the field is empty.

The sheet also offers a **stack** (defaulting to Inbox; Completed is not
offered), a **category**, a **project** and a **due date**, all optional. The
date starts **empty**; the category starts on the **default set in More** (or
empty if there is none) — the date behind a toggle, using the *compact* date
picker so the sheet stays half-height rather than filling the screen. Typing a
title and tapping Add must stay the fast path, with nothing else to dismiss or
clear.

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

**On a phone** this is a `confirmationDialog`, which is the right shape for a
thumb and already dismisses on a tap outside. It takes only a title string per
button: SF Symbols passed as a `Label` are silently dropped, and there is no way
to tint a button beyond `role`.

**Anywhere a pointer is used** — Mac and iPad — it is a **popover anchored to
the card that was clicked**, drawn as rows so the stacks can wear their own
colours: each destination carries its symbol and the same wash the cards in that
stack carry, so where a card is going is recognised rather than read. A click
outside puts it away, which a pointer expects and a modal dialog cannot offer.
Bind the popover per row rather than to the list, or it opens over the middle of
the screen instead of beside the card. There is no Cancel row: clicking away is
the cancel.

Either way it lists the **stacks the card is not already in**, then
**Edit…**, then **Show Only <project>** — or **Show All** while a filter is on,
on every card, since a category filter shows cards carrying no project — then
Cancel. One tap moves it, so filing stays the fast path with no menu to read;
the rest is there because once someone has learned that tapping a card opens a
menu, that menu is where they look for everything else the card can do. The
extra rows cost nothing to ignore, and a card with no project while nothing is
filtered adds none of them.

## Swipe gestures

The cards live in a ScrollView, not a List, so implement these as a drag gesture,
not `.swipeActions`. The gesture must yield to vertical scrolling: only engage
once the drag is more horizontal than vertical.

- **Swipe left** — moves the card to Today. For a card already in Today, it
  moves on to Tomorrow instead. This works from every stack, so a completed card
  swiped left comes back to life in Today.
- **Swipe right** — opens the **editor**: the card's name in an editable field,
  plus Stack, Category, Project, Due date, Complete and Delete. Everything a
  card has, in one place.

  The name field **is the one New Task uses**, not a lookalike: the same `#`
  button, the same suggestion chips, the same pill, the same reading of a
  half-typed word. One view with two parents, because the gesture people learn
  while writing a card has to work when they come back to it, and two copies
  would have drifted apart the first time either was touched. The parent
  decides what a chosen project *means* — New Task moves its own category
  picker, the editor writes it to the card — so all the field reports is which
  project is now on it. Removing the project in New Task gives back the
  category the card had before; in the editor it does not, because there the
  category is a thing the user may have set deliberately and it is already
  saved. And when the first word of a title reads
  like a code, by the same test the bulk conversion uses, the editor offers
  **Make “NF” a project** in one tap: the word becomes the project and leaves
  the title. It is the single-card version of Convert Title Prefixes, for a
  card written before its project existed.

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

## Card appearance

Each card has **one flat background colour, taken from its stack**. Keep it
low-opacity over the system card colour so text stays readable in light and dark
mode.

Stack colours: Inbox gray, Today blue, Tomorrow orange, Later green, washed
over the card at a strength chosen **per stack**, not one strength for all: the
same wash separates a card from the grey page by very different amounts
depending on the hue, and at a single value the orange and green cards nearly
disappear while the blue stands clear. Completed carries **no wash at all** —
the strikethrough, filled checkmark and dimming already say "done", and every
remaining colour is spoken for. Red is reserved exclusively for overdue.

Each card shows:

- A checkbox on the left that toggles completion.
- The category as **its coloured icon alone — no text label** — placed just
  after the checkbox and *before* the title, on the title's line. The slot is
  reserved even when the card has no category, so the icons form a column and
  every title starts at the same x. Draw the symbol as `Text(Image:)` rather
  than a plain `Image`, or it aligns by its own box and sits visibly above the
  text baseline. Same on both platforms.
- The title, led by the project in the card's category colour ("**TRIP** book
  flights") as one run of text, so a long title wraps naturally and the card is
  no taller. Yellow is darkened to ochre in light mode. Struck through and
  dimmed when completed. There is no way to remove a project from the card face
  — that is the editor's job.
- Its date as a relative label ("Today", "Tomorrow", "Tue, 1 Sep"). If the date
  has passed, show it in red and outline the card in red — but **leave the card
  where it is**; overdue is flagged, never moved.
- For completed cards with no date, a caption naming the stack it came from.

On a multi-line card the checkbox and category icon centre vertically rather
than sitting on the first line.

## Sort order

**Within INBOX, TODAY, TOMORROW and LATER**, in this priority:

1. Cards dated today — and overdue cards — first
2. Then cards dated tomorrow
3. Then everything else (undated cards and cards dated further out, together)

Alphabetical within each tier by the **displayed text** (project + title),
case-insensitive and number-aware (so "item 2" precedes "item 10"). Sorting by
what is shown keeps a project's cards together.

**Within COMPLETED**, ignore that rule entirely: sort by completion time, most
recently completed on top.

## The COMPLETED archive

Show only the 20 most recent. Below them a **More… (N)** button, where N is how
many remain hidden; each tap reveals 20 more. Once everything is visible the
button becomes **Show Less**, collapsing back to 20. With 20 or fewer completed
cards, no button appears.

The cap applies to what is left *after* filtering and searching, so narrowing
the list never hides a match behind it.

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

## Looking back

The bottom-left corner opens more than settings, so it is an **ellipsis, not a
gear**, and the sheet is titled **More**. Its first section is **Review**: two
rows, *This week* and *Last week*, each showing how many cards were finished
and opening a list of them grouped by the day they were finished, newest day
first, and newest card within a day.

This is the counterweight to a list that never nags. An app that cannot tell you
anything is late needs somewhere that says what you got done, or it reads as an
app that does not notice.

Two weeks only. The question worth answering is "what did I get done", not
"let me browse an archive" — the Completed stack already holds everything.

Weeks start on whichever day the reader's calendar starts on: Monday across
most of Europe, Sunday in the US. Take the boundary seriously — a card ticked
off at 23:59 on Sunday belongs to the week that was ending, not the one
beginning. A card that was un-completed has no timestamp and never happened.

Days with nothing on them are left out rather than drawn empty, and a week with
nothing at all shows one line of text instead of a row of blank days. The rows
are a record, not cards: no swipes, no checkbox to untick, no stack colour.

## Categories

Categories are **defined by the user**, not fixed. A category is a **label**, an
**icon**, and a **colour**. Cards display only the icon; the label names the
category in More, in the picker, and to VoiceOver.

More lets the user add, edit, reorder and delete categories. Deleting one strips
it from every card that used it — the cards themselves are kept — and the
confirmation says how many cards are affected.

Offer a palette of category colours **disjoint from the stack colours** (so not
gray, blue, orange or green) and from red: indigo, purple, teal, pink, brown and
yellow work. A category icon has to stay legible sitting on a stack-coloured
card. Offer a grid of SF Symbols to pick the icon from.

One category may be marked the **default for new cards**, chosen in a "New cards"
section and badged in the category list. It is a pre-selection, not a
constraint: the compose sheet shows it as an ordinary picker value the user can
change, including back to None. Store the default **on the document with its own
timestamp**, not as a flag on each category — otherwise two devices can each set
a different one and both end up marked. Deleting the default category clears it,
and a merge that removes the category must not leave the default dangling.

## Projects

Cards often begin with the name of the thing they belong to — a trip, a client,
a paper, a course. That is a first-class **project**: one optional project per
card, typed as `#NAME`, shown as a coloured prefix. Call it a project
everywhere in the interface; never "subproject" or "tag".

- **A project is its own record** (id, name, optional category, optional group,
  archived flag, `modifiedAt`), referenced by id from the card — never text
  inside the title. That is what makes renaming one edit instead of a rewrite of
  every title, and it syncs with the same `modifiedAt` + tombstone rules as
  categories.
- **Names match without regard to case, accents or a leading `#`**, and are
  shown as first written. A name is one word (spaces removed), so a space can
  finish it.
- **A project fills in its category** on cards given it afterwards.
- **Entry (New Task).** Typing `#` plus letters shows matching projects as chips
  under the field (prefix matches first, then contains; most recently *created*
  first — not last edited, because converting or merging touches every card).
  **The project is taken the moment the typed word names an existing one** —
  the pill appears and the category follows, without waiting for a space.
  Waiting means the sheet spends the whole time showing a category the card is
  not going to get, which reads as the tag having done nothing. Typing on past
  a name that matched, or deleting the `#`, gives back both the project and the
  category the card had before. Tap a chip, or type a space, to take the word
  literally (existing if it matches, otherwise new). An unknown word offers "Create #…". Before anything
  is typed, the five most recent projects are already shown as chips, so the
  common case is one tap. On the iPhone keyboard `#` is two layer-switches away,
  so put a `#` button inside the title row — a keyboard-toolbar button does not
  appear in this sheet. The chosen project sits as a pill before the title; tap
  it to remove it. A new project is only created when the card is added, so a
  cancelled sheet leaves nothing behind. Top-align the row: an empty vertical
  text field reports its placeholder's baseline lower than typed text.
- **Archived projects** are never suggested and drop out of the project list,
  so the list stays about what is still going on.

### Organising them — all in the Filter

There is no separate Projects screen. Everything about a project is reached from
the Filter, which is the one place projects are listed at all.

Every project row carries a **visible ⓘ**: the row filters by the project, the ⓘ
opens it — the way a Wi-Fi network is joined by its row and configured by its ⓘ.
A hidden gesture is not acceptable as the only way in.

The **project editor** holds everything: rename (one edit, every card; renaming
onto an existing name asks to merge), category, group, archive/unarchive, merge
into another, and delete (cards keep their titles, lose the project). It shows
how many cards are in the project.

**Changing a project's category moves its cards with it.** The project is what
says where the work belongs; cards keeping whatever category they happened to
have would scatter a project across categories with no way to see it or put it
right. A card already in the destination is left untouched, so nothing is
stamped for a change that did not happen — the rest are a real edit and sync as
one.

**Archiving is only offered once nothing in the project is still to do.** Asking
to archive a project with open cards prompts ("2 cards are still to do. They are
marked completed.") and ticks them off as one edit. Cards that vanished while
still open would be work lost, which is why it completes them rather than
quietly hiding them. Typing an archived project's name brings it back, as does
the Unarchive button.

Long-press a project (right-click on the Mac) for the same **Edit Project…**
plus the quick **Move to Group** menu and **Add to Selection**; it is an
accelerator, never the only route. The group menu — the groups already in the
category, a new one, or none — is one shared view used by both the long-press
menu and the editor's Group row, so the two cannot drift apart.

### Groups of projects

Groups such as Holidays or Clients within a category. A group is a *kind* of
project, never a state of one: when it is worked on is what the stacks say, so
examples must not read as timing.

A group is a plain optional label on the project (`group`), not a record of its
own: a category's groups are the distinct labels its projects carry, so a group
exists while something is in it, nothing lingers, and syncing needs no new
machinery (the label travels with the project's `modifiedAt`). Labels may be
several words; they match without regard to case or accents, and the first
spelling in use names the group. Groups belong to a category: moving a project
to another category clears its group.

Group headings sit inside the category section with the grouped projects
indented beneath them, followed by ungrouped projects. Tapping a heading selects
the group, and it carries the same **ⓘ** the projects under it do, opening the
rename directly: renaming is all a group has, so a sheet with one row in it
would be worse than the alert. Renaming onto another group's name joins them. Headings use primary, not secondary, text — dimmed rows read
as disabled. Cards, New Task chips and the editor's project menu are untouched
by grouping.

### Converting old titles

A one-time, reviewed step, never automatic, reached from **More** and shown only
while there is something to convert: list first words used as prefixes, with
their card counts and sample titles. Code-like words (no lowercase letters, or
letters with digits: NF, ABC1234) start ticked; ordinary words used on several
cards (Payer, Email) start unticked. Flag near-duplicates (STUDY vs STUDY2026)
with a "Merge into" choice. Strip the word and any following `-`/`:` from the
title; never convert a one-word title. A new project takes the category most of
its cards have.

### Two devices creating the same project offline

Both would survive a merge. After every load and merge, fold same-name projects
into the one with the lowest id, remap cards to it without stamping them, and
tombstone the others at their own `modifiedAt` — so every device independently
makes the same choice and writes the same tombstone.

## Filtering

The filter narrows the list to any mix of categories and projects: a card shows
if it matches any of them. Selecting nothing means everything. An uncategorised
card is *not* shown when a category is chosen, since it belongs to none of them.

It lists **Everything**, then each category with its projects beneath it,
grouped, indented and searchable.

**On a wide window — the Mac always, an iPad unless it is sharing the screen —
it is not a sheet at all but a sidebar**, beside the cards rather than on top of
them. Filtering is choosing a scope, and a sheet covers the very list it is
changing: you pick, dismiss, look, and reopen if it was wrong. In a sidebar,
clicking a project and seeing the cards change are the same moment, and the next
project is one click away — which is what browsing a structure needs. It is the
same list either way, written once, so the two cannot drift apart. A phone keeps
the sheet: there is no room to keep both, and a sidebar would crowd the cards it
exists to explain. (A Mac Catalyst sheet cannot be resized, so an enlarged sheet
would not answer this.)

Drive the choice off the **size class**, not `#if targetEnvironment(macCatalyst)`
— that way a wide iPad simulator shows the Mac's layout and can stand in for a
Mac window. Exclude phones by idiom: a Max in landscape is horizontally regular
too.

**The sidebar starts closed, on every launch.** The cards are what the app is
for, and a permanent column of machinery beside them is the clutter this app
does without.

**One control opens it, not two.** Remove the system's own sidebar toggle
(`.toolbar(removing: .sidebarToggle)`): it sits at the far right of the sidebar
header and floats over the first card when the sidebar is closed. The filter
button does the job on every platform — sheet on a phone, sidebar on a wide
window — and it is the only one of the two that can show *what* is being
filtered.

On a phone the sheet opens at the **large** detent. The list is categories,
groups and every project, and `.searchable` floats its field at the bottom of
the sheet, where at the medium detent it sits on top of the last rows.

**Clicking a row picks that one and drops the rest.** Filtering is normally a
question about one project, and a list that accumulates selections answers a
question nobody asked. Clicking what is already the whole selection clears it,
so the row that narrowed the list is the row that puts it back.

**Several at once is a circle at the head of every row** — category, group and
project alike — which takes that row in or out of what is already picked. It is
visible, so nothing has to be discovered; it needs no modifier key, which
matters because **⇧-click cannot be read in a Catalyst app**
(`Gesture.modifiers(_:)` is macOS-only and does not compile, and modifier flags
would mean a UIKit recogniser under every row); and it works the same on a
phone, where a modifier does not exist at all. A group's circle fills itself
once every project in it is picked. **Everything** has no circle — it clears
rather than joins — and keeps its tick on the right. A footer under it explains
both gestures, where the eye already is rather than at the bottom of a list
nobody scrolls to. The long-press menu keeps "Add to Selection" as an
accelerator.

**Every row carries the same tally: cards still to do**, counted with the test
the list itself applies — so a row offering one card always has one to show.
That includes group headings, which count the cards in their projects and not
the projects themselves. A row may read 0 and turn up completed cards, which is
the harmless direction: you are shown more than was promised, never less.

**"Include archived projects"** brings archived ones back into the list, off by
default and on every opening. It sits above the categories, because the search
field is pinned to the bottom of the sheet and a short list would leave a row
below it stranded underneath. An archived project shown that way is greyed, and
one that is currently filtering the list is never hidden from under its own
selection.

The filter button reflects the state: the plain filter glyph when nothing is
chosen, the category's own icon and colour when exactly one is, and the **count**
when several are — no single icon can stand for several. Deleting a category
removes it from the selection, so the list is never filtered by something that
no longer exists. On the Mac, right-click a card for "Show Only <project>";
while any filter is on, that item becomes "Show All" on every card.

## Searching

A magnifying glass beside the filter opens a bar above the stack, and ⌘F does
the same on the Mac. Typing narrows every stack at once, in place: the cards
stay in their sections, keep their colours and can still be swiped and ticked,
because a separate list of results would be a second place where cards live.
Closing the bar clears the query, so the list is never quietly narrowed by
something no longer on screen.

What is searched is what the card shows: its title, and the project name
printed in front of it. Case and accents are ignored, so "creche" finds
"crèche" without a French keyboard. Several words must all appear but in any
order — "flight book" finds "book the flights" — because a query is a memory
of a card, not its wording. Search and filter compose: a search runs inside
whatever the filter has already chosen, and the empty state says so.

## More

The sheet behind the ellipsis, in order: **Completed** (the weekly review
above), **Categories**, **Convert Title Prefixes into #Projects…** when there is
something to convert, **New cards** (the default category), **Language**,
**Sync**, **CSV**, and **Backups**.

**On the Mac it is a popover, not a sheet**, anchored to the button. A sheet is
modal: nothing behind it can be clicked, so neither clicking outside nor
clicking the button again can put it away, and More is a menu rather than a task
to be finished. A popover light-dismisses on a click outside, and the button
becomes a switch. That click also lands on the button, so a short guard after a
dismissal stops the same click reopening what it just closed. A phone keeps the
sheet, where a popover would fill the screen regardless.

Wording throughout says **every device**, never "both" — a sync file can be
pointed at by as many as the user likes.

## Persistence and sync

One JSON document holding categories, cards, projects, tombstones and the
default-category choice. Written to **iCloud Drive's ubiquity container** when it
is available so a companion Mac app shares the same data, and to Application
Support otherwise — a user not signed into iCloud must still get a working app.

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
  also gives the user an "On My iPhone" folder to fall back on.

Adopting a file offers a choice: **merge with this device**, or **replace the
cards on this device** with the file's. Merge is the default shape — overwriting
silently would wipe one side the moment a second device is set up.

The two are not symmetric, and getting this wrong is destructive. Deleting cards
normally leaves **tombstones** so the deletion propagates. Replacing on adopt
must *not*: those cards are being abandoned, not deleted, and tombstoning them
would push straight back into the file being adopted and erase the very cards
just taken from it. Drop them and their tombstones instead. Refuse to replace
from a file holding no cards.

**Delete All Cards** sits behind a confirmation naming the count. That one *does*
tombstone, so it reaches the other device. Categories survive it.

**Sync Now says what it did.** A line under the button reports what changed and
when: "3 cards arrived", "Already up to date", or "Could not read the sync file".
For a feature whose whole proposition is "trust this one file", silence is the
worst possible answer, and finding nothing is a real answer reported like any
other. Count it as a pure function on the document (`change(from:)`) rather than
in the view, so it can be tested: a card with a new id has *arrived*, the same id
with different contents was *updated* — moving stack counts, it is the same card
— and an id that is gone was *removed*.

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

**Merging must not need to know which device is "newer".** Give every card,
category and project a `modifiedAt`, and resolve each one independently — latest
edit wins. Record deletions as **tombstones** (id → time deleted): without them,
deleting a card on one device and merging with another that still has it silently
brings it back. A deletion beats an edit only if it happened after that edit, so
an edit made later can deliberately resurrect a card.

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

## macOS and iPad

The same target runs on the Mac via **Mac Catalyst** — set
`SUPPORTS_MACCATALYST = YES` and `TARGETED_DEVICE_FAMILY = "1,2,6"`. The model,
store and sync layers are Foundation-only, and the views' UIKit-flavoured pieces
(`Color(.systemGroupedBackground)`, `presentationDetents`,
`UIImpactFeedbackGenerator`, the compact date picker) all exist under Catalyst.

**The Mac build is sandboxed.** App Store Connect refuses a macOS upload that is
not, so TestFlight for Mac needs `com.apple.security.app-sandbox`, wired in
through `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` so it reaches Catalyst only — iOS
is sandboxed by the system and must not carry these keys. The user-picked sync
file also needs `files.user-selected.read-write` and
`files.bookmarks.app-scope`; the latter is what lets a security-scoped bookmark
resolve on a later launch rather than failing silently.

The sandbox moves where the Mac's data lives: `NSHomeDirectory()` becomes the
container, so both the local document and the `UserDefaults` holding the
sync-file bookmark move with it. A Mac that was running an unsandboxed build
opens the sandboxed one with no cards and no sync file. Nothing is lost — the
old file stays where it was, and choosing the sync file again restores
everything — but say so before anyone installs it.

Because it is one target, behaviour changes land on both platforms at once.
Two differences that matter:

- The swipes become **click-and-drag** on a Mac: a two-finger trackpad swipe
  scrolls instead, so the swipe left stays for anyone who wants it. The Mac
  also has a **right-click menu** on a card, mirroring what a click already
  offers — Edit and Show Only both appear in both, deliberately: a context menu
  that will narrow the list by a card but not open it reads as broken, and
  Finder puts Open in both places for the same reason.
- **The window shows no title.** It is not a document, so there is nothing to
  name, and the app is already named in the menu bar and the Dock
  (`titlebar?.titleVisibility = .hidden`). The titlebar itself stays: the
  traffic lights live there, and it is the window's drag region.
- Wide windows get the filter **sidebar** described above, which also fills the
  width that would otherwise leave cards stretched across a wide Mac window.

A fully native AppKit-backed Mac target is possible instead — share Models,
Sync and TodoStore, rewrite the views — but the swipe gestures, half-height
sheets and floating buttons do not translate, so the layout would change.

## CSV import and export

More offers **Export Cards as CSV…** and **Import Cards from CSV…** through
the system save and open panels.

Columns, in this order: `id, title, stack, category, due, completed, created,
project, group`. The last two are written **last** so header-less older exports
still read by position.

**Parse the due column leniently.** Only the app's own export uses `yyyy-MM-dd`;
open that file in a spreadsheet and the column comes back in the user's locale,
and hand-written files use whatever the author typed. Accept the common shapes —
`yyyy/MM/dd`, `dd/MM/yyyy`, `dd-MM-yyyy`, `dd.MM.yyyy`, `d MMM yyyy`, a full ISO
timestamp — plus the device's own short and medium date styles, and normalise to
the start of the day. A due date that silently fails to parse looks exactly like
a card that never had one.

The category is written as its *label*, and matched back case-insensitively on
import; an unknown name leaves the card uncategorised rather than inventing a
category. Dates are `yyyy-MM-dd`, timestamps ISO 8601.

On import, a `project`/`course`/`hashtag` column, or a title starting with
`#CODE `, sets the project (created if new). `tag` means category. A `group` (or
`cluster`) column puts the row's project in that group — the first row naming a
group for a project wins — and an empty one leaves the project's group alone, so
an older file never takes a project out of its group.

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

More lists them with their age and card count; tapping one restores it behind a
confirmation.

Restoring is a rescue, so it has to win: stamp the restored cards as edited now
and clear their tombstones, or the very delete being undone will simply reapply
from the other device. Cards added since the backup are dropped locally but
**not** tombstoned — they are not what the user asked to remove, so if the other
device still has them they come back on the next sync.
