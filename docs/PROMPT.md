# Rebuild prompt — "DayHand"

Build a SwiftUI app (iOS 17+, one target for iPhone, iPad and Mac, no
third-party dependencies) called **DayHand**: a to-do app where every task is a
task in a single scrolling vertical stack.

## Core model — read this first, it drives everything

A task has five independent properties. Nothing is derived from anything else:

1. **Stack** (required) — one of `INBOX`, `TODAY`, `TOMORROW`, `LATER`, `COMPLETED`.
2. **Category** (optional) — one the user defined.
3. **Project** (optional) — one the user defined.
4. **Due date** (optional) — a specific day.
5. **Title** (required).

**A task's stack is stored, never computed.** A task placed in Next is still in
Next next week and next year. Nothing rolls over as time passes; only the user
moves it. Now / Next / Later are named lists you file things into, not calendar
queries. This is the whole point of the app: a job that takes four days can sit
in Now for four days, and nothing ever marks it late.

**WAITING is for work that is not yours to do.** A manuscript out with
co-authors, a quote asked for and not received, a reply owed to you. The task is
not late and you are not behind — somebody else has it. Left in Now it makes the
pile look fuller and more accusatory than it is, which is the exact feeling this
app exists to remove.

It is a stack like any other: one tap from the task's menu, and one tap back when
the thing arrives. **Nothing returns it automatically.** "The quote came — when
do I do this?" is a real decision, and restoring the task to wherever it was
before would answer it wrongly, because the context has moved on.

**Waiting does not count as addressed.** A reminder on a waiting task — "chase
the co-author on Friday" — is the best use a reminder has, and when it arrives
there is something to do. So the flag goes on gathering it, which quietly turns
the flag into *what do I need to chase?* alongside *what do I need to start?*.

**Adding a stack is safe for a device that has not updated.** `decodeIfPresent`
answers nil for a raw value it does not recognise, so an older build reads
`"waiting"` as Inbox and the rest of the document is untouched — no throw, no
replacement with the starter file. It does not stamp the task as edited either,
so the next merge is a tie on `modifiedAt` and the newer device keeps its own
copy. Check this before adding a case, not after.

**They are called Now, Next and Later, and not Today and Tomorrow**, because a
calendar word turns a pile into a promise. A task that has sat in "Today" since
Monday looks like a failure; one that has sat in "Now" looks like work in
progress, which is what it is. The old names needed a sentence of explanation
wherever they appeared — the surest sign a label is wrong.

**The stored values are still `today` and `tomorrow`.** Every file ever
written holds them, in tasks, backups, sync files and CSV exports. This is a
change of label and nothing else; renaming the raw values would strand every
one of those files.

The **dates on a task stay calendar words**: a reminder falling tomorrow reads
"Tomorrow" whatever stack the task is in. That contrast is the point — the stack
says what you decided, the date says when.

They are looked up like any other visible text. These three had been hard-coded
English in all seven languages, which nobody noticed until the stack beside them
started saying "Maintenant".

**Neither date moves a task. Ever.** That is the rule the rest of this section
exists to protect. There is one date, and optionally its far end:

- **Remind me** (a day) — when to *pick the task up*. It fires a
  notification, colours the task's edge as it approaches, orders the task
  inside its stack, and is what the flag gathers. Offered first, because for
  most tasks it is the only date worth having.
- **Deadline** (a day) — when the work must be *finished*, for a job of more
  than a day. Shown on the task and nothing else: it colours nothing and fires
  nothing.

**A new deadline is normally offered once a reminder exists.** A finish line with no
start is a date the app can do nothing with — it cannot ask about it, cannot
colour by it, and cannot tell you when to begin. Asking "when is it due?"
before "when will you start?" is what made the earlier version of this confusing.

The distinction is the whole reason a four-day job works here. "Write the
grant case" is picked up on Monday and due on the 23rd: the reminder is
Monday, and Monday is what turns the task red. A list that only knew the 23rd
would leave it grey until the day it was already too late.

Moving a task by hand keeps both dates. There is nothing for a stack and a date
to disagree about, so there is no rule dropping one to satisfy the other, and a
task in Later may be started tomorrow and stay in Later.

A deadline can outlive its reminder — clearing a reminder keeps its deadline —
so the editor also shows the deadline
whenever a task already carries one. A date that can be seen but not changed is
worse than one that was never offered.

## Identity

Named **DayHand**: a deck of tasks, dealt a day at a time. Short enough for a
home-screen label, and it says what the app is.

The app icon is three tasks fanned out: a white one in front carrying a blue
tick and two lines, a sunrise-orange one behind it with a sun, and a deep blue
night task with a moon and stars. Today and tomorrow, said without a word.

**No lettering** — an iOS icon almost never contains text, and at home-screen
size a word turns to mush. Supply it **full bleed**, 1024 square, no
transparency and no rounded corners of its own: iOS applies its own mask, and
artwork that arrives already rounded shows the page in the corners and a second
edge inside the system's. One icon serves both appearances.

## First run

A new install opens with a handful of **sample tasks** that explain the app by
being it: two in Today, two in Tomorrow, one in Later carrying a project and a
date, one in Inbox, one already completed.

Mark them, and clear the mark the moment the user edits one. The samples still
untouched are swept away the first time real tasks arrive from another device,
so a second device set up later never pushes tutorial tasks into the shared
file. Drop them without tombstones: they were never anywhere else.

The seeded categories are **Home** (house, teal), **Work** (briefcase, indigo)
and **Courses** (graduationcap, purple) — three that suit most people,
renameable like anything else. Give them **fixed ids** so a task written before
categories were editable still resolves, and match an old file's fixed category
names by label rather than by position, or renaming the seeded three would refile
old tasks under the wrong one.

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
- **Counts need real plurals.** Building them as `"\(n) task" + (n == 1 ? "" : "s")`
  cannot be translated; give the catalog the whole sentence and let it vary.
- **Seeded data is translated once, at first run** — the categories and the
  sample tasks. It is data from then on: changing the device language later
  leaves what is already there alone, because renaming someone's categories
  behind their back would be worse than a mixed-language page.
- **The word for a task, per language**: *Aufgabe*, *tarea*, *tâche*,
  *attività*, *taak*, *tarefa*. Never the language's word for a card. Renaming
  the English and leaving the translations is the easy half of a rename: the
  key changes, every translation keeps the old noun, and the app goes on
  calling them cards in six languages while English says task. German
  addresses the reader as **Sie**, Portuguese in the third person; Spanish,
  Italian and Dutch are informal; French uses **vous**.
- **A translation that reorders arguments must use `%1$@`-style specifiers.**
  Several languages put the count before the name in "%@'s %lld tasks move to
  %@", and without the positions the name is read as the number. A string with
  one argument needs nothing; one with two of different types is where this
  bites.
- **An `en` entry in the catalogue is an override, not the key.** The
  multi-argument strings carry one, and a rename that edits only the key
  leaves English itself reading the old word.

## Screen

One screen, no app title and no navigation bar. A vertically scrolling stack of
tasks grouped into six sections, in this fixed order: Inbox, Now, Next, Later,
Waiting, Completed. **An empty section is not drawn at all**, which is what lets
there be six of them without the screen growing: Waiting costs nothing on the
days nothing is blocked.

- Section headers are large — the size an iOS large navigation title would be —
  led by the stack's own symbol in the stack's colour (the same symbols the
  pickers use, so a stack looks the same everywhere; COMPLETED's tint is clear,
  so its symbol takes the secondary colour), then the name and a small dimmed
  count. The symbol is a glyph, not an image view, so it sits on the title's
  baseline, and it is smaller than the display-sized title so the name still
  leads. They scroll with the content rather than pinning; a pinned header parks
  under the status bar and collides with the clock.
- Empty sections are hidden entirely.
- When there are no tasks at all, show an empty state inviting the user to tap +.
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
position, animated. It sits alone, mirroring the + button, so nothing crowds the
top of the list and nothing sits close enough to Today to be hit by mistake. It stands down while the search bar is open: the bar wants the width,
and there is nothing to jump over in a handful of results.

### Glass, and where it stops

The floating buttons are **glass**, on a system that has it; an opaque disc and
a drop shadow everywhere else. That shadow was the app faking depth, and glass
is depth. The point is not the finish: four opaque circles sitting on a green
Later task read like holes punched in the list, and glass lets the task pass
under them.

**The `+` button stays solid.** It is the primary action and has to be
findable without looking. A solid accent circle is findable on any backdrop; a
glass one is as prominent as whatever happens to be scrolled behind it. One
solid action with glass chrome around it is the right hierarchy anyway.

**A button that is doing something tints its glass**, and does not rely on its
ring. On an opaque disc a 2pt coloured ring was enough to say "filtering", "has
a query", "a reminder is waiting". On glass it is not — measured on the phone,
the bell's red ring all but vanishes against a dark backdrop, and that bell
appearing is the one thing in the app meant to be noticed. The ring thickens
*and* the glass takes a light tint of the same colour.

**Glass at rest, solid for a mode.** The flag filter is glass until it is on,
and then a solid red disc: it is telling you the list on screen is not the
whole list, and a tint says that too quietly. Its count sits outside the glass
shape, or it is clipped away.

**Not on the tasks, and not in the sheets.** A task's stack colour is the
information — blue Today, green Later — and glass samples what is behind it,
washing those toward each other. The urgency edge is a coloured stroke that
glass fights. And task contrast is checked deliberately; translucency makes it
depend on what happens to be underneath, which cannot be checked. Sheets
already carry the system's own material.

## Adding tasks

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
delivered to it as a line break and never as a submit. Return must add the task.
Turn a typed line break back into the submit it was meant to be, and tell it
apart from newlines arriving in *pasted* text — those fold into spaces and leave
the sheet open. Guard the add itself so that a platform delivering Return by
both routes at once files one task, not two.

**A title may say whatever it likes.** A task called "fix issue #42" was once
one keystroke from inventing a project called 42, which needed a rule comparing
the title against the one the editor opened on. That rule is gone, and for a
better reason than a guard: nothing is ever taken out of a title without being
chosen. The first word is *offered* — as a chip, which can be ignored — so a
title can begin with anything at all, including a hash, and mean only itself.

**And committing does nothing when nothing changed.** The editor writes on
Done, and only what differs from the draft it opened on. Together these two rules are why opening the editor and closing it
again cannot alter the task — which it could, renaming it and creating a
project named after whatever followed the hash.

**This belongs to the title field, not to the sheets that use it.** It was
written at one call site and the New Task sheet went without it, so a Return
there put a line break in the title and did nothing else — on the Mac, where
Return is the obvious way to finish, for weeks. One field, one rule.

**The stack and the dates do not talk to each other.** There is nothing to
reconcile: a date never decides which stack a task belongs in, so picking one
cannot contradict the other. A task can be filed in Later and be due to be
picked up tomorrow, and both are true.

This section used to describe the opposite — a date of today moving the stack
picker to match, a stack chosen by hand dropping a contradicting date, a floor
pushing a too-soon date forward for Later. All of it existed to keep the sheet
consistent with a filing pass that no longer runs, and its absence is the
feature.

The footer says where the task is going.

## Tapping a task

**On a phone** this is a `confirmationDialog`, which is the right shape for a
thumb and already dismisses on a tap outside. It takes only a title string per
button: SF Symbols passed as a `Label` are silently dropped, and there is no way
to tint a button beyond `role`.

**Anywhere a pointer is used** — Mac and iPad — it is a **popover anchored to
the task that was clicked**, drawn as rows so the stacks can wear their own
colours: each destination carries its symbol and the same wash the tasks in that
stack carry, so where a task is going is recognised rather than read. A click
outside puts it away, which a pointer expects and a modal dialog cannot offer.
Bind the popover per row rather than to the list, or it opens over the middle of
the screen instead of beside the task. There is no Cancel row: clicking away is
the cancel.

Either way it lists the **stacks the task is not already in**, then
**Edit…**, then **Show Only <project>** — or **Show All** while a filter is on,
on every task, since a category filter shows tasks carrying no project — then
Cancel. One tap moves it, so filing stays the fast path with no menu to read;
the rest is there because once someone has learned that tapping a task opens a
menu, that menu is where they look for everything else the task can do. The
extra rows cost nothing to ignore, and a task with no project while nothing is
filtered adds none of them.

## Swipe gestures

The tasks live in a ScrollView, not a List, so implement these as a drag gesture,
not `.swipeActions`. The gesture must yield to vertical scrolling: only engage
once the drag is more horizontal than vertical.

- **Swipe left** — moves the task to Today. For a task already in Today, it
  moves on to Tomorrow instead. This works from every stack, so a completed task
  swiped left comes back to life in Today.
- **The swipe is a UIKit pan recogniser, not a SwiftUI gesture**, and that is
  the whole reason it exists. A `DragGesture` has already begun by the time
  `onChanged` can look at its direction, and the scroll view has lost the touch
  by then — so a drag that started on a task often did not scroll the list at
  all, and trying again worked. Reproduced every time: the same drag scrolled
  when it began on a heading and not when it began on a task. UIKit asks
  `gestureRecognizerShouldBegin` *first*, and a recogniser that answers no
  leaves the scroll completely alone. Nothing in SwiftUI can say no that early.

  Two things about where it hangs. A recogniser fires for the view that was hit
  and its **ancestors**, and the view SwiftUI gives a background representable
  is not an ancestor of the task's own content — put there, it never saw a
  touch and the swipe silently did nothing. So it goes on the enclosing scroll
  view, which is an ancestor of everything in the list; and because that view
  holds every task, each task's recogniser checks the touch is inside its own
  bounds before agreeing to begin. The task's tap, its completion button and
  the context menu's long press all still work, because the recogniser agrees
  to run alongside anything else.
- **Swipe right** — opens the **editor**: the task's name in an editable field,
  plus Stack, Category, Project, Due date, Complete and Delete. Everything a
  task has, in one place.

  **The editor holds its edits and writes them on Done.** It used to edit the
  task live — every picker wrote straight through — which left Cancel nothing
  to undo and made Escape a commit by another name. Everything the sheet can
  change is held in one draft: title, stack, category, project, group and both
  dates. Done writes only what differs from what the sheet opened on, so
  opening the editor and closing it again still stamps nothing. A project named
  but not yet created is held as a name and made on Done, so a cancelled sheet
  leaves no project behind either. Escape takes the Cancel button's role.
  Swiping the sheet down is the phone's Cancel, and when something has changed
  it asks **Discard changes?** first rather than throwing an edit away in
  silence. Complete writes the edit before completing, because it is an
  explicit action; Delete does not, the task going with it.

  The name field **is the one New Task uses**, not a lookalike: the same `#`
  button, the same suggestion chips, the same pill, the same reading of a
  half-typed word. One view with two parents, because the gesture people learn
  while writing a task has to work when they come back to it, and two copies
  would have drifted apart the first time either was touched. The parent
  decides what a chosen project *means* — New Task moves its own category
  picker, the editor writes it to the task — so all the field reports is which
  project is now on it. Removing the project in New Task gives back the
  category the task had before; in the editor it does not, because there the
  category is a thing the user may have set deliberately and it is already
  saved. And when the first word of a title reads
  like a code, by the same test the bulk conversion uses, the editor offers
  **Make “NF” a project** in one tap: the word becomes the project and leaves
  the title. It is the single-task version of Convert Title Prefixes, for a
  task written before its project existed.

  In the editor the pill and the **Project** row are two views of one fact, so
  neither may hold its own copy of it: both read the project off the task. Given
  a copy to show, the pill went on offering a project the task no longer carried
  the moment the row below was used — the row, the New Project alert and the
  first-word button all write to the task, and only one of them was telling the
  copy. For the same reason one of them writes: the task's edit stamp is what
  decides a merge, so a second write of the same value would bump it for nothing.

Feel: reveal a coloured panel behind the task that grows as you drag, ~96pt
commit threshold, resistance past that, capped travel, and a haptic tick the
moment the gesture arms. The move panel wears the **destination stack's own
colour and name** — blue "Today", or orange "Tomorrow" for a task already in
Today — so the gesture previews where the task will land. Indigo "Category" for
the other direction.

Name the two callbacks by intent (move / choose category), not by direction, and
decide which direction triggers which in exactly one place. Direction-named
callbacks make swapping the two an error-prone edit across several files.

Completion is not a swipe: it is the checkbox on the task, and the tap menu.

One trap to avoid: a task that moves stack keeps its identity, and if rows are
identified by that alone SwiftUI reuses the old row without feeding it the new
task — it keeps painting the previous stack's colour and a date it no longer has.
Include the stack in each row's view identity.

## Task appearance

Each task has **one flat background colour, taken from its stack**. Keep it
low-opacity over the system task colour so text stays readable in light and dark
mode.

Stack colours: Inbox gray, Now blue, Next orange, Later green, Waiting a muted
slate at a fainter wash than the rest — it is not your move and should not shout
as loudly as one that is — washed
over the task at a strength chosen **per stack**, not one strength for all: the
same wash separates a task from the grey page by very different amounts
depending on the hue, and at a single value the orange and green tasks nearly
disappear while the blue stands clear. Completed carries **no wash at all** —
the strikethrough, filled checkmark and dimming already say "done", and every
remaining colour is spoken for. Red is reserved exclusively for the edge of a task whose reminder has arrived.

Each task shows:

- A checkbox on the left that toggles completion.
- The category as **its coloured icon alone — no text label** — placed just
  after the checkbox and *before* the title, on the title's line. The slot is
  reserved even when the task has no category, so the icons form a column and
  every title starts at the same x. Draw the symbol as `Text(Image:)` rather
  than a plain `Image`, or it aligns by its own box and sits visibly above the
  text baseline. Same on both platforms.
- The title, led by the project in the task's category colour ("**TRIP** book
  flights") as one run of text, so a long title wraps naturally and the task is
  no taller. Yellow is darkened to ochre in light mode. Struck through and
  dimmed when completed. There is no way to remove a project from the task face
  — that is the editor's job.
- Its dates as relative labels ("Today", "Tomorrow", "Tue, 1 Sep"), **start
  then finish, in that order**: a plain **flag** for the reminder — the day to
  pick the task up — and, when the task has one, a **chequered flag** for the
  deadline after it. The chequered flag stays grey while the plain one carries
  the colour, because only one of the two is saying "now". Both fit on one
  line; the pair shrinks slightly rather than wrapping.
- **A coloured edge for how close the reminder is**: orange while it is coming —
  within three days, long enough to act on and short enough that a wall of
  orange does not become the normal state of the list — and red once it is here
  or past. Red stays reserved for exactly that. The edge is the reminder's
  whole voice before it fires: it never moves the task, so how the task looks
  is the only thing it can say. The deadline colours nothing; two things on one
  task competing to say "now" is how the earlier version got confusing.
- For completed tasks with no date, a caption naming the stack it came from.

On a multi-line task the checkbox and category icon centre vertically rather
than sitting on the first line.

## Sort order

**Within INBOX, NOW, NEXT and LATER**: tasks carrying a date come first,
soonest at the top; the rest follow. The reminder orders a task, falling back
to the deadline for a task that has only that — ordering and the colour of the
edge are the only things a date does.

Alphabetical within each group by the **displayed text** (project + title),
case-insensitive and number-aware (so "item 2" precedes "item 10"). Sorting by
what is shown keeps a project's tasks together.

**Within COMPLETED**, ignore that rule entirely: sort by completion time, most
recently completed on top.

## The COMPLETED archive

Show only the 20 most recent. Below them a **More… (N)** button, where N is how
many remain hidden; each tap reveals 20 more. Once everything is visible the
button becomes **Show Less**, collapsing back to 20. With 20 or fewer completed
tasks, no button appears.

The cap applies to what is left *after* filtering and searching, so narrowing
the list never hides a match behind it.

**COMPLETED is grouped by the day the work was done** — "Today 1", "Tue, 20
Oct 3" — and nothing else is. It is the one stack with a date on every task in
it, so it is the only one worth reading as a run. The headings are quieter than
a stack header: they sit inside one, and the stack above has already said what
these are.

This is what makes the screen a project review. Every stack is already scoped
by Organise, COMPLETED included, so filtering to a project gives one screen
holding both halves of the question: what is still open, by stack, above; and
when the rest got done, by day, below. No mode to be in and no second screen —
the filter was doing the scoping already, and only the dates were missing.

A **review mode** was considered and rejected for the same reason. Nothing but
a completion has a date to group by, so a mode showing the run would have to
hide the open tasks — and the question being asked while reviewing a project is
usually "does this need another task?", which is exactly the half it would
hide.

The grouping is built from what is **shown**, not from everything, so the cap
still caps: More… reveals twenty more and they fall into their days. A
completed task carrying no date is listed after the run rather than dropped —
`Timeline.months` can only place a task it can date, and a task must not vanish
from the list for want of a timestamp.

## How long a task has been sitting

A task records **`enteredStackAt`**: when it arrived in the stack it is in now.
It is not shown on the card or in any list. It is stored because the question
cannot be answered afterwards — a timestamp not written at the moment of the move is gone
— and because the helpers worth building on a list that never nags are reviews
of a stack that has stopped moving: what has been in the inbox a fortnight,
what has sat in NOW all week, what went to LATER in July.

`modifiedAt` cannot stand in for it. It is bumped by any edit, so renaming a
task that has not moved since July would make it look as though it had just
arrived. `createdAt` only bounds it from the other side.

Stamped wherever a bucket changes, and nowhere else: moving, completing,
reopening, and the bulk completion that archiving a project performs. Reopening
counts as an arrival — the task starts sitting in that stack again from now,
not from whenever it first did.

**Absent, it falls back to `createdAt`, never to now.** A file written before
the field existed knows nothing about when its tasks last moved, and the day
they were made is the one honest answer available; falling back to now would
have every task in the list claim it had just arrived, on the first launch
after this shipped. The CSV carries it as an `entered` column and falls
back the same way, because tasks are matched by id on import — without it,
exporting and re-importing would quietly reset every task to today.

### Editing it

The task editor has one row for it, under **Stack**: **In this stack since**, a
date. It exists for the one case the app cannot know about — a task that has
been sitting longer than it has been here, such as one brought in from another
app — and it is the same draft as everything else in that sheet: nothing is
written until **Done**, and **Cancel** discards it.

Four rules, each there because the obvious version would be wrong:

- **Choosing a stack is an arrival, so the date follows.** Move a task from
  Later to Next in the same edit and the row reads today, not the day it reached
  Later under the name of Next. Choosing the stack it started in puts the
  original date back, since nothing has then moved.
- **A date the user chose is written after the move**, which stamps its own
  arrival as now, so the chosen one is the one that stands.
- **Never later than now.** The picker greys out the future, and the store
  clamps as well, because the picker keeps the time of day it was given and
  choosing today could otherwise land a few hours ahead.
- **Not shown for a completed task.** Its stack is locked, and the date it
  entered Completed is when it was done, which is a different field.

It may be **earlier than `created`**, and `created` is left alone. For an
imported task the creation date can itself be wrong, and one picker silently
rewriting a second field would be a surprise.

**The importers set it from the source, not from the import.** The field
defaults to the moment of import, which would have every task in a four-year-old
backlog report that it had just arrived. An open task takes the date it was made
in the other app, a finished one the date it was finished, and either falls back
to when it was made — then, only when the source gives nothing, to the import. A
bulk fix for tasks already imported is a CSV with an `entered` column.

## Reminders

A reminder is armed on a task with a **day**, and fires a local notification.

**Not a time.** The whole app thinks in days — the edge colours by day, the flag
gathers by day, snooze means tomorrow — and being asked for an hour you did not
care about is a question with no right answer. A notification has to go off at
some point, so they all go off at **nine**, which is when a day's work gets
looked at. The picker shows a date and nothing else.

A reminder set by an earlier version at some other hour keeps it: it fires when
it was told to, and moving it would be a change nobody asked for. Everything
that reads a reminder reads its day, so it behaves like any other; editing its
date snaps it to the hour as a new one would be. **Dismissing that notification changes nothing.** Swiping a
notification away is how a notification is got rid of, not how a decision is
made, so the reminder is still waiting afterwards.

**There is one way in.** The **badged flag beside the jump-to-Today button**
narrows the task list to what is still to be settled: a **red** reminder — due
today, or come and gone — on a task **still sitting in Inbox or Later**. It
wears the same flag the tasks do, it appears only while something is on it, and
the tasks show up in their own stacks where they can be moved, ticked off or
swiped like anything else. Opening the notification goes there, since the
notification was a question about one task and that is the list the task is in.

**The stack is the answer, so filing a task takes it off the flag.** A task in
Today is one the user has already decided to do today; flagging it would be the
app asking a question it has been given the answer to, and the number would
never go down however much work got done. Moving a task to Today or Tomorrow
drops it from the count while leaving its red edge alone — it is still today's
work, it is simply no longer an open question. Moving it back to Later brings
it back, which is right: that is un-deciding.

Read from where the task *is*, not from a record of what was done to it, so the
reason a task is or is not flagged is visible on screen. And it is not the app
having a view about where a dated task belongs: nothing files anything, and a
task reminded today may live in Later as long as the user likes — it is just
still on the list of things to settle.

So every flagged task carries a red edge, but not every red task is flagged.
The count is a subset of the colour, never the other way round.

There was a second way in — a bell in the button row opening a review sheet
that answered reminders one at a time — and it was dropped. The two sets were
almost identical, and the only reason the sheet was not redundant is that
**moving a task did not answer its reminder**: you could deal with a task and
have it go on asking, and the sheet existed to say "yes, I did that". Fixing
that removed the reason for the sheet.

### Dealing with a task answers the reminder that asked

Moving a task, completing it or deleting it is an answer. The user has decided
what to do with it; nothing should still be asking.

**Answered is not cleared.** A move keeps both dates — that rule has not
changed — so the task holds on to its reminder and stays red for the rest of
the day. It is still today's work; it just is not a question any more. The flag
goes on showing it after you have moved it, which is right: the flag is the
day, not a queue of unanswered questions.

The only two things that are about the reminder rather than the task live on
the task's own menu, beside Edit and the four stacks:

- **Snooze until tomorrow**, shown for any reminder that has **arrived** — red,
  which starts at the beginning of its day. Not "waiting on an answer", which is
  narrower and leaves tasks the flag is showing with no snooze on them: a
  reminder set for five this afternoon is on the flag from the morning without
  having fired, and a task dealt with and then put back in Later is on the flag
  again with its answer still stamped. **Anything the flag gathers offers the
  choices that go with it** — one predicate, so the two cannot drift apart.
  A reminder still to come is excluded, because "until tomorrow" would move it
  *earlier*, which is not what the word means.
- **Clear the reminder**, shown whenever there is one. This is how a reminder is
  silenced for good, and it takes the red edge with it.

**Orange is deliberately left out.** A task three days off is being shown, not
asked about, and a list of things to deal with now loses its meaning the moment
it also contains things to deal with later.

Both appear only while there is something to count; a count of nothing is not
worth a permanent control.

**The app icon carries the flag's number**, and exactly that: two numbers
meaning nearly the same thing is how you end up with an icon saying 1 beside a
button saying 0.

Each scheduled notification carries the badge the icon should show **once it
fires** — the flag's count evaluated at that moment, not a running total. It
has to be worked out in advance, because nothing can update a badge while the
app is closed, and it is knowable: a task joins the flagged set when its
reminder's day begins and leaves it only when someone files or finishes it. So
a reminder arriving on a task already red adds nothing, and a task that turns
red at midnight adds itself with no notification to announce it. The app
corrects the count the moment it is opened. That count is the only thing that says something is waiting without the
app being opened, which is exactly what an unanswered reminder needs. Each
scheduled notification carries the badge the icon should show once it has fired — those already waiting, plus itself and
everything before it — and the app corrects the number the moment it is opened.

**Snooze** asks again at the same time of day tomorrow, counted from **now**,
not from the reminder. A reminder left alone for a week is the usual case, and
adding a day to it would land in the past: the task would go quiet and never
ask again, which reads exactly like the button having eaten it. The task does
not move.

**Clearing** leaves the **deadline exactly as it was**: the job may still have
a day it must be finished by, and the editor offers the field again the moment
a reminder is set.

Doing nothing is deliberately not an answer. Leaving a reminder alone is the
absence of one, which is why it goes on asking — the same reason dismissing a
notification changes nothing.

A reminder is silenced by clearing it. There is no separate switch for
whether one fires: a task with a date that will not go off is a task that lies
about what it is going to do, and the field only ever meant "clear this, but
keep the date I can no longer see".

Completing or deleting a task cancels its reminders.

Pending notifications are rewritten wholesale from the tasks after every change
that could affect them, rather than patched one at a time — the set is a
handful, and a schedule that has drifted from the tasks is how a reminder ends
up firing for a task finished last week. Permission is asked the first time a
reminder is actually set, not at launch: a permission sheet in front of an
empty list is a question about nothing. If it is refused, reminders still
appear in the review; only the notification is lost.

## Looking back

The bottom-left corner opens **More**. **Completed → Timeline** shows the
whole completion history, grouped by month and day. The main Completed stack
also groups tasks by day; neither surface needs This week / Last week filters.
Project **History** keeps the same timeline scoped to that project.

## Inbox review helper

**Review Inbox** is available at the Inbox heading and in More's **Review**
section. It reviews the entire Inbox, regardless of the main list's filters
or search. It asks **Where does this task belong?**, showing one live task at a
time, including its category, project, Notes, reminder and deadline.

The choices are **Now** (I am working on this), **Next** (I intend to work on
this next), **Later** (This is for another time), and **Waiting** (I am waiting
for someone or something). These use the normal move operation: dates stay,
and an outstanding reminder is answered. **Edit task** opens the existing
editor for title, organisation, Notes and dates; Cancel changes nothing.
Editing alone does not advance unless the task leaves Inbox.

**Keep in Inbox** leaves the task unchanged and continues. **Complete** uses
normal completion. **Delete** asks for confirmation. Normal Undo is available
inside the helper; restoring a moved, completed or deleted task returns it to
this review. Keeping a task never changes its edit timestamp or reminder.

A pass snapshots Inbox task IDs in the usual Inbox order. Its IDs and kept
choices are saved locally, so closing and reopening resumes the same pass,
including after a relaunch. Tasks are always read live; remote edits appear,
and removed tasks are skipped. New arrivals wait for the next pass. At the
end, **Review remaining Inbox** starts a fresh pass including kept tasks and
new arrivals. An empty Inbox says **Inbox is clear**; finishing a pass with
kept tasks says **Review finished**, without claiming the Inbox is empty.
This UI state does not enter the shared document or impose a review schedule.
No paid restriction is added in this implementation.

## Completion timeline

**Each day carries a bar**, scaled to the busiest single day anywhere in that
timeline — not the busiest in its own month, which would make a quiet month
look exactly like a frantic one. A day with one task still draws a visible
mark rather than an empty track. The bar is what makes a run of work read as a
shape instead of a list of dates, and it costs one integer per day.

Months with nothing finished are left out entirely rather than drawn empty: a
project that ran for a fortnight two years ago must not cost two years of
scrolling to reach.

**Completions only.** A task carries the day it was created and the day it was
finished; `modifiedAt` is overwritten on every edit and spent on resolving sync
conflicts, so nothing records a task having moved from Next to Now on a
Tuesday. A timeline drawn from what exists can say when work landed and must
not pretend to say more. Showing moves and renames would need an append-only
event log in the document — new storage, dedupe-by-id on merge, and a file that
only ever grows — which is a different feature, not a bigger version of this
one.

Days with nothing on them are left out. The timeline is a record of
completions, not an alternative task editor.

## Categories

Categories are **defined by the user**, not fixed. A category is a **label**, an
**icon**, and a **colour**. Tasks display only the icon; the label names the
category in More, in the picker, and to VoiceOver.

More lets the user add, edit, reorder and delete categories. Deleting one strips
it from every task that used it — the tasks themselves are kept — and the
confirmation says how many tasks are affected.

**The Edit control sits in the Categories heading, not in the navigation bar.**
More is sync, backups, CSV and language as well, and a button at the top right
of all that reads as editing the sheet itself rather than the one list it
reorders.

Offer a palette of category colours **disjoint from the stack colours** (so not
gray, blue, orange or green) and from red: indigo, purple, teal, pink, brown and
yellow work. A category icon has to stay legible sitting on a stack-coloured
task. Offer a grid of SF Symbols to pick the icon from.

One category may be marked the **default for new tasks**, chosen in a "New tasks"
section and badged in the category list. It is a pre-selection, not a
constraint: the compose sheet shows it as an ordinary picker value the user can
change, including back to None. Store the default **on the document with its own
timestamp**, not as a flag on each category — otherwise two devices can each set
a different one and both end up marked. Deleting the default category clears it,
and a merge that removes the category must not leave the default dangling.

## Projects

Tasks often begin with the name of the thing they belong to — a trip, a client,
a paper, a course. That is a first-class **project**: one optional project per
task, typed as `#NAME`, shown as a coloured prefix. Call it a project
everywhere in the interface; never "subproject" or "tag".

- **A project is its own record** (id, name, optional category, optional group,
  archived flag, `modifiedAt`), referenced by id from the task — never text
  inside the title. That is what makes renaming one edit instead of a rewrite of
  every title, and it syncs with the same `modifiedAt` + tombstone rules as
  categories.
- **Names match without regard to case, accents or a leading `#`**, and are
  shown as first written. A name is one word (spaces removed), so a space can
  finish it.
- **A project fills in its category** on tasks given it afterwards.
- **A project comes from the first word of the title, and nowhere else.**
  `BIO2140 mark the problem sets` offers BIO2140; `mark the problem sets for
  BIO2140` offers nothing. The rule once read the *last* word, which made the
  order of typing matter invisibly, and then the first word *behind a hash*,
  which is where the hash finally proved unnecessary: the position was already
  doing the work. The CSV importer still lifts a leading `#CODE`, because that
  is a file format rather than a gesture, and `clean` strips a hash anywhere a
  name is read, so an old habit costs nothing.
- **A list narrowed to one project starts a new task in it.** The project is
pre-selected, its category comes with it, and the pill carries its × for the
times the task is not about it — a task written while looking at PAPER is
almost always a PAPER task. Narrowed to two projects, or to a category alone,
nothing is assumed: neither names one project.

**Entry (New Task).** Typing `#` plus letters shows matching projects as chips
  under the field (prefix matches first, then contains; most recently *created*
  first — not last edited, because converting or merging touches every task).
  **The project is taken the moment the typed word names an existing one** —
  the category follows, without waiting for a space.
- **While the tag is still being typed there is no pill**; the typed word turns
  the project's own colour instead. Because a tag has to be the first word, an
  unfinished one means the field holds nothing *but* the tag — so a pill beside
  it was the same name twice over, reading as `NOCIONS ×  #NOCIONS` until the
  space landed. The colour is the same signal said once, under the cursor, and
  the coloured word becomes the coloured pill when the space arrives, which
  reads as one movement rather than a stutter. Typing on past a match still
  gives the project back: the colour drops away instead of a pill vanishing.
- **There is no `#`.** A project is made from the **first word of the title**,
  because that was the only place one could ever be: `BIO2140 mark the problem
  sets`. The hash was never doing anything but saying *this first word is a
  project* — the position was already fixed — and it cost two keyboard layers
  to reach, three on a layout that puts £ there.
- **The first word is offered, never taken.** As it is typed, a word that names
  an existing project brings that project up in the chips; one that names none
  of them offers **New project NOCIONS**, whatever case it was typed in. Accepting is a
  tap, or Tab for the first one. Only then does the word come out of the title
  and become the pill — a task draws its project as a coloured prefix, so
  leaving it would write the name twice. Typing a space used to commit a
  project outright, which was the one place in the app where something was
  written without being asked for.
- **A chip takes the word out of the title only when it is the word that put it
  there** — and *put there* is the test the chips are gathered by, not equality.
  Typing NOCIO and taking the NOCIONS it offered left NOCIO behind as the
  title, because the two names are not equal; one is why the other was on
  screen. `ProjectSuggestions.matches` answers both questions so they cannot
  drift. Choosing a recent project while typing "Buy milk" still sets the
  project and leaves the title alone, which is what the test is protecting.
- **The new-project chip comes first in the row.** A word that names nothing is
  exactly when the suggestions fall back to the five most recent projects, so
  the one chip answering what was typed sat behind all of them in a row that
  scrolls sideways — off the edge of the screen, and indistinguishable from the
  offer never being made.
- **Any first word of two characters or more is offered as a new project**, not
  only one that reads like a code. Capitals were the signal and they are a poor
  one on a phone: the field capitalises the first letter of a sentence, so a
  code typed in lower case arrives as "Trip" and was turned away, and reaching
  for the shift key costs more than the project saves. Nothing is lost by
  offering widely — it is an offer, it is ignored by doing nothing, and the name
  it makes is capitalised anyway. The bulk conversion keeps the strict test,
  because that one reads every title in the file unprompted.
- **The row reads: what the word names, then the offer, then the recents.**
  Typing `bio` wants BIO2140 before it wants a new project called BIO, and the
  recents appear only when the word named nothing — where they must not bury
  the offer, which is what put it off the edge of a row that scrolls sideways.
- **A project's icon is a paperclip**, because that is what a project does:
  it holds tasks that belong together. It is the same glyph everywhere — the
  button beside the title field, the Project row, the filter bar, Settings, the
  project editor — so nothing points at a character nobody types any more. It
  had to miss `CardCategory.iconChoices`, which people pick their own category
  icons from, as well as `tag`, `folder` and `tray.full`, which Category,
  groups and the stacks already use. The candidates were put side by side at
  the real size to choose between them: a box read as a parcel, a stack
  collided with the word this app uses for Now and Next, and the rest were
  decorative rather than legible.
- **The button carries a chevron.** It is a menu, not a key — a bare glyph
  beside a text field invites a press, and pressing it is the reflex this
  change retired.
- **That button is the picker.** There is no character to insert, so it
  lists every project and offers **New Project…** — the way to a project the
  first word will not offer, because it reads like a word or because it is not
  what is being typed. One tap, from anywhere in the field.
- **A `#` typed out of old habit still works**, quietly: `clean` strips it, so
  `#BIO2140` finds the project `BIO2140` would. It is simply not required, and
  not advertised. The CSV importer still reads a leading `#CODE`, which is a
  file format rather than a gesture.
- **Tab takes the first suggestion.** Only while a tag is being typed, and only
  onto a project that already exists — completing to something that does not
  exist is not completion, and a space already commits a new name.

  **Backspace against the tag does not remove it, and cannot.** It was tried:
  `onKeyPress(.delete)` never fires, for the same reason Tab's did not — a
  focused text field takes keys first. Tab at least landed *in the text*, where
  it could be caught; backspace on an empty field changes nothing and so fires
  nothing at all. The only remaining route is wrapping a `UITextView` to
  override `deleteBackward()`, which would mean rebuilding the placeholder, the
  growing height, focus, submit and the tag colouring by hand — a great deal of
  risk for one keystroke, when the pill's **×** already does it. Removing a tag
  is the ×.

  **Tab arrives as a character, not as a key.** `onKeyPress(.tab)` never fires
  through a focused text field; it was tried and does not work. The tab lands
  in the text instead, where it is whitespace — and whitespace is what finishes
  a tag, so Tab on `#NOC` committed a project called NOC rather than reaching
  NOCIONS. It has to be taken out of the string before the tag is read. With
  nothing to complete to, the tab is simply dropped: a title has no use for
  one.
  Waiting means the sheet spends the whole time showing a category the task is
  not going to get. Tap a chip, or press Tab for the first one, to take the
  word — and only then does it leave the title. A word that names nothing
  offers "New project …", in capitals, however it was typed. Before anything is
  typed, the five most recent projects are already shown as chips, so the common
  case is one tap. The button beside the field opens the rest.
  The chosen project sits as a pill before the title; tap
  it to remove it. A new project is only created when the task is added, so a
  cancelled sheet leaves nothing behind. Top-align the row: an empty vertical
  text field reports its placeholder's baseline lower than typed text.
- **Archived projects** are never suggested and drop out of the project list
  unless the filter's Show row asks for them, so the list stays about what is
  still going on.
- **Typing a project's name always offers it, used or not.** A project nothing
  is filed under is kept out of the suggestions, which is right while browsing
  and wrong while naming: asked for by name it was offered neither as a match,
  being unused, nor as a new project, because it already exists. Moving a
  project's last task away therefore put it out of reach of the field
  altogether, leaving Organise as the only way back to it.
- **A project no task carries is not offered either.** The last task moving to
  another project leaves one behind that is still in the file but no longer a
  tag anybody is using, and it went on being suggested and listed in the
  project menu. It is *not* deleted: whether a project is empty is read off the
  tasks, and two devices that have not merged yet do not agree about those — a
  device holding an older copy would write a tombstone for a project the other
  one is filing tasks under, and leave those tasks pointing at nothing. Folding
  duplicate projects can write a tombstone precisely because it is decided by
  the project list alone and every device decides it identically; emptiness is
  not. So the project stays, stops being offered, and comes back by itself the
  moment a task carries it again — keeping the id, group and category it had.
  A name typed in full still matches it, so it is reused rather than made a
  second time, and Organise still lists it, which is where it can be renamed,
  merged or deleted deliberately.

### Organising them — all in Organise

There is no separate Projects screen. Everything about a project is reached from
Organise, which is the one place projects are listed at all.

**A project row carries no `#` of its own**; the hash is joined to the name,
`#GRANT`. A separate glyph cost a 24pt frame and the gap beside it — 36pt of a
sidebar that has none to spare, to say what one character already says. Names
never wrap: a wrapped name turns one row into two and reads as two projects, so
a long one shrinks a little and then truncates. Every project sits on the column
a group's folder icon starts on, grouped or not — the heading above already says
whether it is in a group, and saying it again with an indent left a run of empty
space between the checkbox and the name.

**Headings carry a faint band of their category's colour**, so a category and
everything under it read as one block: strongest on the category row, lighter on
the groups inside it, and nothing at all on the projects, which keeps them the
only coloured *text* in the list. The band is built from the same tint the
project names use, which is lightened in dark mode — the plain colour goes muddy
behind a dark row.

**A project is refiled from its menu.** **Move to Group** puts it in a group;
**Move to Category** moves it, and takes every task in the project along, so
that one says how many and asks first. Both go through one rule, so they cannot
answer differently.

**Drag a project by the handle beside its name onto a group or an “All
[category]” row — in the sidebar only.** A group receives the project in that group's category;
a category receives it with no group, including when removing it from a group
in the same category. Valid targets show an accent outline, including folded
headings. A move across categories still asks before changing any tasks, using
the same rule as the menu. Dropping onto its current location does nothing.

The handle uses `UIDragInteraction`, and headings attach `UIDropInteraction`
to their native list cell's content view. The earlier SwiftUI per-row drop
modifiers never received the session in Catalyst's List. Only a single local
project drag is accepted; arbitrary text and external drags cannot move a
project. The dedicated handle leaves the name's selection and rename gestures
available. The menu remains available as an alternative to dragging. A confirmed
move resolves the current project and category again: a project or destination
deleted during sync makes the move a no-op. Category, group and affected tasks
are saved together with one edit timestamp, never as an intermediate move with
no group.

**The handle is not drawn on a phone**, where its column is held open by a
clear spacer so names still line up under their group's folder icon. Dragging
there asked for a 22pt target to be touched, held and then moved; what it
carried was a preview of the grip icon rather than the project, and valid
targets lit up only while hovered, so nothing on screen said what was being
moved or where it could go. A drop onto a group changes only a label, so it
also passed the "does this touch any tasks?" test that makes a category move
ask first, and went through in silence — the project left the ungrouped list
for a group section with nothing to say it had. Taken together that reads as
the project vanishing, and a reorganisation nobody can see is worse than no
reorganisation.

The phone keeps two routes that move a project by naming where it goes: the ⓘ
opens the project editor, which has both category and group, and a long press
on the name gives the same Move menu. The hint under the first row says so
rather than describing a handle that is not there.

Builds and model tests verify none of this. A pointer drag on a Mac,
cancellation and folded headings still want a manual check.

**Double-clicking a project or a group name renames it in place.** Enter commits
and so does clicking away, the way a Finder rename does — an untouched field
writes nothing, so neither can rename anything by accident. A name that belongs
to another project would be a merge rather than a rename, which is not something
to do by accident from a list row: it says so and sends you to the ⓘ. The single
click still picks, and is declared after the double so the double wins; only
these rows pay the wait that costs, not the tasks.

**Categories and groups fold in the sidebar, and only there.** On a phone this
same view is a sheet that is opened, picked from and closed, not a list anyone
lives in, and a triangle there is one more target crowding the checkbox. The
sheet ignores the folded state rather than merely hiding the control: it is
remembered per device, so a category folded in an iPad's sidebar would
otherwise come up collapsed in that same iPad's compact sheet with nothing to
expand it. The sidebar is **told** which it is, by the view that decided to
show one — each column of a NavigationSplitView carries its own size class and
the sidebar's is *compact*, so a view inside it that asks the environment
concludes it is the phone, and the triangles and the tighter rows went missing
from the one place they were for.

**Folding**, with the rows sliding in and out rather than
appearing. The triangle beside a heading **and the heading's own icon are one
control**: the triangle alone was 18pt sitting 6pt from a 22pt checkbox, two
targets inside the width of one fingertip, and on a phone the fold was nearly
impossible to hit without toggling the filter by mistake. Taking the icon into
the same button makes it 48pt wide and costs nothing, since the icon was there
anyway. The name beside it still filters, the way a row's name does in any
outline. The triangle
folds what is under it away, and what is folded is remembered between launches —
a sidebar that forgets is worse than one that does not fold. A heading with
nothing under it shows no triangle but still reserves its width, so the project
names stay in one column instead of stepping in and out as groups fill and
empty. The sidebar's rows are also tighter than the phone's: it is driven by a
pointer, where the 44pt a finger needs turns a dozen projects into a scroll.
The filter *sheet* on the phone is this same view and keeps the full target.

Every project row carries a **visible ⓘ**: the row filters by the project, the ⓘ
opens it — the way a Wi-Fi network is joined by its row and configured by its ⓘ.
A hidden gesture is not acceptable as the only way in.

The **project editor** holds everything: rename (one edit, every task; renaming
onto an existing name asks to merge), category, group, archive/unarchive, merge
into another, and delete (tasks keep their titles, lose the project). It shows
how many tasks are in the project.

**Changing a project's category moves its tasks with it.** The project is what
says where the work belongs; tasks keeping whatever category they happened to
have would scatter a project across categories with no way to see it or put it
right. A task already in the destination is left untouched, so nothing is
stamped for a change that did not happen — the rest are a real edit and sync as
one.

**Archiving is only offered once nothing in the project is still to do.** Asking
to archive a project with open tasks prompts ("2 tasks are still to do. They are
marked completed.") and ticks them off as one edit. Tasks that vanished while
still open would be work lost, which is why it completes them rather than
quietly hiding them. Typing an archived project's name brings it back, as does
the Unarchive button.

Long-press a project (right-click on the Mac) for the same **Edit Project…**
plus the quick **Move to Group** menu and **Add to Selection**; it is an
accelerator, never the only route. The group menu — the groups already in the
category, a new one, or none — is one shared view used by both the long-press
menu and the editor's Group row, so the two cannot drift apart.

**The Group row says who else a change reaches.** It is the one control on a
task's editor that edits something other than the task in front of you: a group
sits on the project, so setting it there regroups every task in that project.
When the chosen project already exists and already carries other tasks, a line
under the label says so — *"Also changes 148 other tasks"* — counted by id, so
it stays right while a task is being moved *into* a project it is not in yet.

It is a caption and not a confirmation. The app asks before a **category** move
because that stamps every task in the project and syncs them; a group is one
string on one project row, touches no task, and is undone by setting it back.
Reserving the modal for what cannot be taken back is what keeps the modal
meaningful.

Three cases need no line at all, and must not show one: a project **named but
not yet created** (there is nobody else to tell — it is created on Done, with
the group), a project **holding this task alone**, and a task **with no
project**, where the row is not drawn.

**The New Task sheet shows the group but does not let an existing project's be
changed**, because that sheet promises that cancelling leaves nothing behind
and a global edit surviving Cancel is the opposite of that. A greyed row with
no reason beside it reads as broken, so it carries its own line: *"Set on the
project. Change it from its ⓘ in Organise."* A project being named for the
first time is settable there, since nothing exists yet to be edited.

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

**A group can be chosen where a project is**, in the New Task sheet and in the
task editor: one row under the project, naming the group and offering the ones
the category already has, plus **New Group…**. A group is easiest to set at the
moment the project is first named, and having to find Organise afterwards is
how projects end up ungrouped for good.

That row appears **only when there is a project**. A group is a label projects
carry, so there is nothing to put in one until something exists to put — and
offering a group for a task with no project would be offering nothing.

**In the New Task sheet the row is settable only for a project that does not
exist yet.** For one that does, it shows the group and nothing more. A group
belongs to the project, not to this task, so changing it there would refile that
project on every task carrying it — and that edit would survive **Cancel**,
which is the opposite of what this sheet promises. Creating new projects late
exists precisely so a cancelled sheet leaves nothing behind; a global write
sitting in the same sheet would undo the point of it. Changing an existing
project's group belongs in the task editor, which saves as you go and has no
Cancel to contradict.

So a project still being typed only records the choice, and it is applied when
the task is added and the project is actually created. A typed name that turns
out to name an existing project keeps the group it already had: the user was
naming a task's project, not quietly refiling one that other tasks carry.

Group headings sit inside the category section with the grouped projects
indented beneath them, followed by ungrouped projects. Tapping a heading selects
the group, and it carries the same **ⓘ** the projects under it do, opening an
**Edit Group** alert rather than a sheet: a group has only two things that can
be done to it, so a sheet would be a screen built around two buttons.

Those two are **Rename**, which writes the new label on every project in the
group — onto another group's name joins them — and **Ungroup**, which takes the
label off them and keeps the projects, their tasks and their category. That is
the whole of what ungrouping can mean, because a group is a label rather than a
record; it is the only way to dissolve one in a single action, the alternative
being to drag each project out in turn. It clears the label from **every**
project carrying it, archived ones included: a group is dissolved entirely or
not at all, never down to the part that happened to be on screen.

Both also sit on the heading's long-press menu, but neither lives there alone.
The ⓘ exists precisely because renaming and grouping used to need a long press,
which is no way to reach the only place an operation lives.

Headings use primary, not secondary, text — dimmed rows read as disabled. Tasks,
New Task chips and the editor's project menu are untouched by grouping.

### Converting old titles

A one-time, reviewed step, never automatic, reached from **More** and shown only
while there is something to convert: list first words used as prefixes, with
their task counts and sample titles. Code-like words (no lowercase letters, or
letters with digits: NF, ABC1234) start ticked; ordinary words used on several
tasks (Payer, Email) start unticked. Flag near-duplicates (STUDY vs STUDY2026)
with a "Merge into" choice. Strip the word and any following `-`/`:` from the
title; never convert a one-word title. A new project takes the category most of
its tasks have.

### Two devices creating the same project offline

Both would survive a merge. After every load and merge, fold same-name projects
into the one with the lowest id, remap tasks to it without stamping them, and
tombstone the others at their own `modifiedAt` — so every device independently
makes the same choice and writes the same tombstone.

## Organise

The filter narrows the list to any mix of categories and projects: a task shows
if it matches any of them. Selecting nothing means everything. An uncategorised
task is *not* shown when a category is chosen, since it belongs to none of them.

It lists **Everything**, then each category with its projects beneath it,
grouped, indented and searchable.

**On a wide window — the Mac always, an iPad unless it is sharing the screen —
it is not a sheet at all but a sidebar**, beside the tasks rather than on top of
them. Filtering is choosing a scope, and a sheet covers the very list it is
changing: you pick, dismiss, look, and reopen if it was wrong. In a sidebar,
clicking a project and seeing the tasks change are the same moment, and the next
project is one click away — which is what browsing a structure needs. It is the
same list either way, written once, so the two cannot drift apart. A phone keeps
the sheet: there is no room to keep both, and a sidebar would crowd the tasks it
exists to explain. (A Mac Catalyst sheet cannot be resized, so an enlarged sheet
would not answer this.)

Drive the choice off the **size class**, not `#if targetEnvironment(macCatalyst)`
— that way a wide iPad simulator shows the Mac's layout and can stand in for a
Mac window. Exclude phones by idiom: a Max in landscape is horizontally regular
too.

**The sidebar starts closed, on every launch.** The tasks are what the app is
for, and a permanent column of machinery beside them is the clutter this app
does without.

**One control opens it, not two.** Remove the system's own sidebar toggle
(`.toolbar(removing: .sidebarToggle)`): it sits at the far right of the sidebar
header and floats over the first task when the sidebar is closed. The filter
button does the job on every platform — sheet on a phone, sidebar on a wide
window — and it is the only one of the two that can show *what* is being
filtered.

On a phone the sheet opens at the **large** detent. The list is categories,
groups and every project, and `.searchable` floats its field at the bottom of
the sheet, where at the medium detent it sits on top of the last rows.

**The panel is called Organise, not Filter.** Every row in it is still a filter
row — tapping one narrows the task list — but it is also the only place
projects, groups and categories are arranged at all, and on the Mac and the
iPad it is a permanent sidebar rather than something opened to perform one
action. "Filter" named a verb; a sidebar is a place. The floating button that
opens it on a phone keeps its filter glyph and its state, because what the
button does is still filter.

It is not called "Projects". Categories are a **peer axis**, not a container
for projects: `FilterCounts.matches` answers true for any task carrying a
category whether or not it has a project, so "All Research" includes tasks with
no project at all. A name that covered only the projects would hide the half of
the panel that is not about them.

**New Project…** sits under the Show row, and makes a project from nothing
rather than from a task. Every other route starts by typing a first word into a
task, which is right when capturing and wrong when setting up, where the point
is to lay out categories and projects first and add work to them afterwards. It
asks for name, category and group together, because a project created with no
category lands in "Other projects" and has to be moved immediately — the
opposite of what setting up is for. A project with nothing in it is a real row:
projects are removed only by merge or delete, so it waits under *Active
projects* and is correctly hidden by *With open tasks*, where nothing is
waiting yet.

**A category carries the same ⓘ a project and a group do**, opening the editor
for its name, icon and colour. It was the one row without one, so recolouring a
category meant leaving the panel the category is actually looked at from.
Adding, reordering and deleting categories stay in **More**: those are about the
*set* of categories, and reordering needs a list in edit mode. The ⓘ is about
the one in front of you.

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

**The footer is written twice, once per input**: a pointer clicks and a finger
taps, and the sidebar's copy ends with the drag line while the phone's does
not, because the phone has no handle to drag. It is two whole sentences rather
than one with a verb substituted in, because a string's key in the catalogue
*is* its English text — a sentence assembled from pieces cannot be translated
as a sentence.

**Every row carries the same tally: tasks still to do**, counted with the test
the list itself applies — so a row offering one task always has one to show.
That includes group headings, which count the tasks in their projects and not
the projects themselves. A row may read 0 and turn up completed tasks, which is
the harmless direction: you are shown more than was promised, never less.

**A "Show" row picks which slice of the project list is on screen**, in four
scopes: **With open tasks** (not archived, something still to do), **Active
projects** (the default, and what the list has always shown), **All projects**,
and, set apart below a divider, **Archived projects**. Three of the four end in
"projects" because three of them are about the archive; the odd one out is
named for what it is about, tasks. "Not archived" came first and was dropped:
it defines the ordinary case by negation, and names the exception.

**The default is Active projects, not With open tasks**, even though the
narrower one is the better answer to "where is work waiting?". Archiving lives
in this panel, and a project whose tasks are all done is exactly the one about
to be archived — a default that hid it would hide each project at the moment it
is finished, which is the moment its row is wanted. The same reasoning that
keeps a selected project visible whatever the scope: a list people organise
from must not drop rows out from under them. It sits above the categories,
because the search field is pinned to the bottom of the sheet and a short list
would leave a row below it stranded underneath.

Two of the four are about being finished and two about being put away, which
are different things: a project whose tasks are all done is still open, and is
simply not where work is waiting. The fourth scope is the only way to look at
the archive on its own — mixing archived projects in among the live ones, which
is all the single "include archived" switch could ever do, means reading past
everything else to find one.

The choice is **remembered**, because it is a way of working rather than a
one-off look — except **Archived, which is undone on every opening**: coming
back next week to a list holding only the projects you had put away reads as
having lost the others. An archived project is **greyed and italic**, because in
the scopes that mix the two, colour alone is the cue the category tints already
use and a grey project reads as one with no category. A project that is
currently filtering the list is never hidden from under its own selection,
whatever the scope says.

Groups need no scope of their own. A group is a label its projects carry rather
than a record, so it is drawn exactly when the scope leaves something in it, and
disappears with its last visible project.

The filter button reflects the state: the plain filter glyph when nothing is
chosen, the category's own icon and colour when exactly one is, and a **count**
when several are, since no single icon can stand for several.

**That count is tasks, not filters**, using the same rule as the numbers beside
the rows in the sidebar — completed tasks left out of both. It once counted how
many filters were switched on, which is a different number wearing the same
clothes: ticking a group of two projects holding three tasks between them put a
2 on the button while the sidebar said 3 a thumb's width away. One predicate
now serves the list, the sidebar and the button, so they cannot disagree again. Deleting a category
removes it from the selection, so the list is never filtered by something that
no longer exists. Clicking a task offers "Show Only <project>",
and on the Mac so does right-clicking it; while any filter is on, that item
becomes "Show All" on every task, since a category filter also shows tasks
carrying no project.

### Undo

**Deleting, completing, reopening and moving a task are undoable**, and each
says so: a bar at the bottom of the screen naming what just happened, with
**Undo** beside it and a way to dismiss it. It goes on its own after a few
seconds. **⌘Z keeps working after it has gone** — the bar is the offer, not the
only route, and the last twenty changes are kept.

The stack is deliberately shallow. Undo here is for the slip you just made, not
a history to walk back through: on a document two devices are both editing, a
deep stack would let someone undo their way into a state neither device ever
held.

**Putting a task back is `StoreDocument.restoring`**, and two rules in it are
what make an undo safe to sync. Both are easy to leave out and neither shows up
on one device:

- The restored task is stamped **now**, not with the time it used to carry. A
  deletion beats an edit only if it happened after it, so a task put back with
  its old timestamp would leave the tombstone newer and the other device would
  delete it again.
- Its **tombstone is dropped**. Keeping it would mean this device still held a
  record saying the task was deleted, and the next merge would hand that to
  everyone else.

And a third that only a test found: the stamp must be **strictly after** the
tombstone, not merely `now`. A merge gives a tie to the deletion
(`deletedAt >= modified`), so a task deleted and put back inside the same
millisecond would come back on this device and stay dead everywhere else.
Stamps carry milliseconds, so one is the smallest step that settles it.

**Moving a project to another category is undoable too, and no longer asks
first.** It used to stop and count the tasks it would take along — but only
from the sidebar; the project editor's own picker applied the same change
directly, so the two disagreed about whether it was worth a question.

They agree now, and on the lighter answer. A confirmation makes the deliberate
case pay for the mistaken one, and it cannot help with the mistake people
actually make here, which is dropping on the wrong row: the dialog names the
destination, but so does the bar — *"Moved FRIA to Teaching"* — and the bar
does not interrupt the nine times in ten the drop was right.

The project and its tasks are restored **together**. Moving a project rewrites
the project's row *and* the category on every task carrying it, so undoing one
without the other would leave a project in one category with its tasks in
another. Only the tasks that actually moved are recorded: one already in the
destination category is not changed by the move, and restoring it would stamp
it for a change it never had.

**The bar is shown by any sheet that can make an undoable change**, not only by
the task list. A sheet is its own presentation context, so an overlay on the
list behind it is simply not visible — and on a phone, where there is no ⌘Z, a
category moved from the project editor would otherwise offer no way back at
all.

**Delete sits on the task's own menu**, last and in red. It is safe there
rather than behind a confirmation precisely because it is undoable. The
confirmations that remain are the ones no single step puts back: emptying the
whole list, restoring a backup over it, completing an entire project.

The bar goes through the same `FloatingChrome` as the round buttons, as a wide
capsule rather than a disc — one `#available(iOS 26, *)` fork, as that modifier
has always promised.

### One list, three surfaces

What a task offers is **one list** — `CardMenu.actions(for:isFiltered:hasProject:)`
— and the three places that show it decide only how to draw it: the phone's
dialog plainly, the Mac and iPad popover with the stack colours, the Mac's
right-click menu with symbols. The stacks it is not already in come first, so
the common move stays one tap with nothing in the way; then the reminder, if it
has one; then Edit; then the filter item.

Each surface used to carry its own hand-written copy, which is the hazard this
file already names about Snooze and Clear living in two code paths. They
drifted exactly as predicted: the right-click menu was written with Edit and
Show Only and never learned the rest, so the Mac's richer gesture gave the
poorer menu. The rule is in the model layer now, where a test can say that a
task in Next is not offered Next, that Snooze follows the same rule the flag
uses to gather the task, and that Show All replaces Show Only rather than
joining it.

**Edit is on every surface, always.** A menu that will move a task but not open
it reads as broken — Finder puts Open in both places for the same reason.

## The keyboard

Four shortcuts, and each belongs to the control that does the thing rather than
to a menu, so there is only ever one of each:

| | |
|---|---|
| **⌘N** | a new task — on the + button |
| **⌘F** | search — on the magnifying glass |
| **⌘Z** | undo — the one exception, in `.commands`, because it has to replace the system's own Undo item rather than sit greyed out beside it |
| **Escape** | leave the search bar, or the sheet in front of you |

**Escape mostly worked already, and that is worth knowing before adding it
anywhere.** A toolbar button placed as the `.cancellationAction` is what
Escape picks, so every sheet with a Cancel — and More, whose Done is placed
there too — already closed on Escape. That is also how leaving the task editor
by keyboard came to discard rather than commit.

Two sheets did not: Organise and the project editor, whose only way out is a
**Done** placed as the *confirming* action, leaving no cancellation role for
Escape to find. Those two bind it by hand. The search bar's Cancel is a plain
button rather than a toolbar item, so it binds it too.

## Searching

A magnifying glass beside the filter opens a bar above the stack, and ⌘F does
the same on the Mac. Typing narrows every stack at once, in place: the tasks
stay in their sections, keep their colours and can still be swiped and ticked,
because a separate list of results would be a second place where tasks live.
Closing the bar clears the query, so the list is never quietly narrowed by
something no longer on screen.

What is searched is what the task shows — its title, and the project name
printed in front of it — plus **the group that project belongs to**, which is
the one part of the haystack no task displays. It earns its place because a
group is how a project is remembered once there are enough of them: "grants
case" should find the task whichever project under Grants it was filed in.
Case and accents are ignored, so "creche" finds "crèche" without a French
keyboard. Several words must all appear but in any
order — "flight book" finds "book the flights" — because a query is a memory
of a task, not its wording. Search and filter compose: a search runs inside
whatever the filter has already chosen, and the empty state says so.

## More

The sheet behind the ellipsis, in order: **Review** (Inbox helper),
**Completed** (timeline), **Categories**, **Convert Title Prefixes into Projects…** when there is
something to convert, **New tasks** (the default category), **Language**,
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

One JSON document holding categories, tasks, projects, tombstones and the
default-category choice. Written to Application Support, and to the file the
user picked as well when there is one.

**There is no iCloud container, and no entitlement for one.** A
**free Apple developer account cannot sign the iCloud entitlement** — Xcode
refuses with "Personal development teams do not support the iCloud capability"
— so the app syncs the other way instead: the user picks their own file through
the document picker and access is kept with a **security-scoped bookmark**. Put
that file in iCloud Drive and the system syncs it between devices. Access is
granted by the choosing, not by the app claiming a container.

The container route was built first and removed once the entitlement went. Its
code outlived it by a long way — unreachable on both platforms, writing nothing,
watching nothing, and from the outside looking exactly like the thing that
noticed another device's writes. **Delete the mechanism when the entitlement
goes**, or the next person to read the file will believe it.

The picked file takes precedence over local storage; keep writing the local copy
too, so the app still works if the file is moved or deleted.

**Say when there is no sync file, in Settings and nowhere else.** One device
needs no sync file and must not be nagged about it — but a device that has *lost*
one looks exactly like a device that never had one, and the only way to tell was
to notice the other device had stopped agreeing with you. A plain "Not syncing"
beside the sync-file row costs nothing and answers the question wherever it is
asked.

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
tasks on this device** with the file's. Merge is the default shape — overwriting
silently would wipe one side the moment a second device is set up.

The two are not symmetric, and getting this wrong is destructive. Deleting tasks
normally leaves **tombstones** so the deletion propagates. Replacing on adopt
must *not*: those tasks are being abandoned, not deleted, and tombstoning them
would push straight back into the file being adopted and erase the very tasks
just taken from it. Drop them and their tombstones instead. Refuse to replace
from a file holding no tasks.

**Delete All Tasks** sits behind a confirmation naming the count. That one *does*
tombstone, so it reaches the other device. Categories survive it.

**Sync Now says what it did.** A line under the button reports what changed and
when: "3 tasks arrived", "Already up to date", or "Could not read the sync file".
For a feature whose whole proposition is "trust this one file", silence is the
worst possible answer, and finding nothing is a real answer reported like any
other. Count it as a pure function on the document (`change(from:)`) rather than
in the view, so it can be tested: a task with a new id has *arrived*, the same id
with different contents was *updated* — moving stack counts, it is the same task
— and an id that is gone was *removed*.

**Update live rather than only on foreground.** While the app is on screen, keep
an `NSFilePresenter` on the shared file — it fires as soon as another device (or
iCloud finishing a download) writes to it — *and* poll its modification date
every few seconds as a backstop, since a presenter does not catch every way a
file can be replaced. **Ten seconds while the window is frontmost, two minutes
when it is not.** The energy a slow poll saves is all in the second case: a
window somebody is looking at is on a Mac that is awake and in use anyway.
Thirty seconds and a generous tolerance meant a task added on the phone could
sit the best part of a minute before a Mac in front of you showed it, which
reads as sync being broken and sends people to Sync Now. The re-read must bail out when the file already matches
what is held in memory, or a write triggers a notification that triggers a
write.

**"Off screen" means something different on the Mac.** A phone that is
backgrounded should stop watching. A Mac window that is merely not frontmost is
still a window being looked at, and stopping there means a visible list can sit
an hour behind the other device and catch up only when it is clicked into —
indistinguishable from sync being broken. On Catalyst, stop only when the app is
properly put away; everywhere else, stop as soon as it is not active.

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

Read and write through `NSFileCoordinator`. There is no `NSMetadataQuery`:
it watches an app's *own* ubiquity container, which is precisely what this
design does without, and it will never match a file the user picked somewhere in
their iCloud Drive. The presenter and the poll are the whole mechanism.

**An older version must not be able to start filing tasks again.** A version
that moved tasks by their date read a `dueDate` key. That key is read once, as
a migration — the day is what the user meant, the moving was the app's idea —
and **never written back**. A flag would not have helped: an old build ignores
keys it does not know. It cannot file a date it cannot see. The cost is that
such a version shows no dates at all, which is the right way round: tasks sit
still and look bare, rather than moving on their own.

**A task whose only date is a deadline becomes a task to start that day.**
Every date written before this scheme — an old `dueDate`, or a deadline written
by the version in between — meant one thing, and that thing is the reminder
now. Leaving it as a deadline would leave a finish line with no start: a date
that colours nothing, asks nothing, and that the editor no longer offers.

Promote it to nine in the morning on that day, since the old date carried no
time. The pass is **derived** — every device computes the same thing from the
same file — so nothing is stamped as edited, and running it twice changes
nothing.

A promoted reminder whose moment has already passed **arrives answered**. The
task still shows red, which is the part worth seeing; what it must not do is
drop a year of old dates into the review as a backlog of questions nobody
asked. One still to come is left unanswered, and will ask.

Migrating moves nothing.

**Merging must not need to know which device is "newer".** Give every task,
category and project a `modifiedAt`, and resolve each one independently — latest
edit wins. Record deletions as **tombstones** (id → time deleted): without them,
deleting a task on one device and merging with another that still has it silently
brings it back. A deletion beats an edit only if it happened after that edit, so
an edit made later can deliberately resurrect a task.

Two traps, both of which cause silent data loss:

- Swift's **synthesised `Codable` decoder requires every key**, even for
  properties that have default values. Add a hand-written `init(from:)` that uses
  `decodeIfPresent` wherever a field was introduced later — otherwise a document
  written by an older build fails to decode and gets replaced with an empty one.
- **Timestamps must survive a round-trip.** Plain `.iso8601` rounds to whole
  seconds, and even with fractional seconds the format only holds milliseconds
  while `Date()` carries more. Stamp times at millisecond resolution so what is
  written is exactly what is read back.

**Stamps are read without a formatter.** `ISO8601DateFormatter.date(from:)`
costs about 70µs a call, and a task carries up to five dates, so parsing them
was roughly 93% of the time spent loading the file — and not only at launch,
because a write from another device decodes the whole file again, on the main
thread. `DocumentCoding.stamp(from:)` reads the bytes at fixed offsets instead.
At ten thousand tasks a load went from 1.9s to 74ms, which is what takes the
size of the file back out of the question for years.

It is a fast path and never the only one. Anything that is not exactly
`2026-09-26T09:15:00.123Z`, or the older form with no fractional part, is handed
back to the formatters and answered as it always was.

Three things decide whether it is safe, and all three were found by running it
against Foundation rather than by reasoning about it:

- **It stops at 1583.** Foundation reads an older date through the Julian
  cutover, so `0001-01-01` comes back two days from where proleptic Gregorian
  arithmetic puts it. That is not a curiosity: `.distantPast` is what every
  seeded row is stamped with, and the encoder writes it as exactly that string.
  Disagreeing there would stop a merge seeing seeded data as older than every
  real edit — which is the whole point of the sentinel, and the bug that
  renamed "Research" back to "Home" on 26 September.
- **The millisecond is carried as whole milliseconds, divided once** — the same
  arithmetic as `Date.stamp()`, which wrote the file. Adding `milli / 1000` to a
  seconds-sized `Double` lands a bit away from it often enough to break a save
  and load, which is how the first version was caught.
- **Agreeing with Foundation matters more than being right.** Foundation reads
  30 February as 2 March rather than refusing it, so the day of the month is
  deliberately not validated and the arithmetic rolls over the same way. The
  tests compare the two across every month and every day from 1 to 31 for
  exactly this reason.

The encoder is left alone deliberately: formatting costs 15ms per ten thousand
dates against 666ms to parse them, so the time in a save is the JSON and not the
stamps.

Decode defensively throughout: missing keys and unknown enum values degrade
gracefully (an unknown category becomes none) rather than throwing away the
file, and an untimestamped task reads as `.distantPast` so any real edit wins.

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
opens the sandboxed one with no tasks and no sync file. Nothing is lost — the
old file stays where it was, and choosing the sync file again restores
everything — but say so before anyone installs it.

Because it is one target, behaviour changes land on both platforms at once.
Two differences that matter:

- The swipes become **click-and-drag** on a Mac: a two-finger trackpad swipe
  scrolls instead, so the swipe left stays for anyone who wants it. The Mac
  also has a **right-click menu** on a task, offering **exactly what a click
  offers** — the stacks, the reminder, Edit, and the filter item. It used to
  hold two of those eight, which had it backwards: a right-click is the
  richer gesture, and on a Mac a context menu that is shorter than a plain
  click reads as a mistake.
- **The window shows no title.** It is not a document, so there is nothing to
  name, and the app is already named in the menu bar and the Dock
  (`titlebar?.titleVisibility = .hidden`). The titlebar itself stays: the
  traffic lights live there, and it is the window's drag region.
- Wide windows get the filter **sidebar** described above, which also fills the
  width that would otherwise leave tasks stretched across a wide Mac window.

A fully native AppKit-backed Mac target is possible instead — share Models,
Sync and TodoStore, rewrite the views — but the swipe gestures, half-height
sheets and floating buttons do not translate, so the layout would change.

## CSV import and export

More offers **Export as CSV…** and **Import from CSV…** through
the system save and open panels.

### One file, three kinds of row

The CSV holds the whole document: a row for every **category**, every
**project** and every **task**, each saying which it is in a final `type`
column. A **blank `type` is a task**, so every file written before there were
kinds of row still reads as exactly what it was.

Columns, in this order: `id, title, stack, category, deadline, completed,
created, project, group, remind, notes, entered, answered, before, archived,
modified, symbol, color, default, type`. Every new column goes **last**, so
header-less older exports still read by position.

It is one wide table with empty cells where a column does not apply, because a
CSV is one file and a spreadsheet can filter on `type` to see any one kind
alone. Where two kinds mean the same thing they share a column: **`title`** is a
task's title, a project's name or a category's label — what it is *called* — and
**`category`** is, for a task or a project, the category it belongs to. The rest
are specific to a kind:

| | task | project | category |
|---|---|---|---|
| `stack`, `deadline`, `remind`, `completed`, `created`, `entered`, `answered`, `before`, `notes`, `project` | ✓ | | |
| `group`, `archived` | | ✓ | |
| `symbol`, `color`, `default` | | | ✓ |
| `id`, `title`, `category`, `modified` | ✓ | ✓ | ✓ |

**A project's group and archived state live on its own row only.** They used to
be repeated on every task row, which gave one fact many places to disagree. An
older file that still repeats them is read as before, for any project the file
does not describe itself.

Rows are written categories, then projects, then tasks, so the structure reads
at the top of the sheet. **Import does not depend on the order**: it resolves
categories first, then projects, then tasks, whatever order the rows are in, so a
file sorted by hand in a spreadsheet still imports.

What the columns carry that a task-only file lost silently:

- **`entered`** — when the task arrived in its stack. Tasks are matched by id,
  so without it a round trip would reset every task to today.
- **`answered`** — when a reminder was answered. Without it a task whose
  reminder had been dealt with would come back asking again.
- **`before`** — the stack a completed task would be reopened to. Ignored on any
  stack but Completed, where it contradicts the stack and the stack wins.
- **`archived`** — `yes` or `no` on a project row. Blank is silence, never a
  `no`: a file that does not say must not take a project out of the archive.
- **`symbol`, `color`, `default`** — a category's look, and which one new tasks
  start in. A category a file declares and this device lacks is created, with
  the icon and colour the file gives it; a bare name with neither gets a tag
  icon and indigo, because a category still has to look like something. A task
  naming a category *nobody declared* is still left uncategorised rather than
  having one invented.
- **A project with no tasks** is a row like any other, so it is no longer lost.

Timestamps in the CSV are to the second; nothing here depends on the
millisecond.

### What import does to what is already here

Rows are matched **by id, then by name** (case-insensitively), and an existing
category, project or task is updated rather than duplicated. A project can be
**renamed** in the sheet — never onto a name another project already has, which
would be a merge — and moved to another **category**, which takes its tasks as
it does everywhere else, without the undo bar: an import is not something to
take back one project at a time.

**Only rows that actually changed are stamped.** This is the rule that makes a
whole-file round trip safe. Import is an edit, but not an edit of every row in
the file. Stamping them all would let a stale file overwrite a newer change made
on another device in the meantime, and would turn every sync after a restore
into a rewrite of the whole document. So:

- a row **identical to what is here is left exactly as it is**, its `modified`
  included, and writes nothing;
- a row that **differs is stamped now**, so a corrected file wins a sync;
- a row that is **new keeps the `modified` the file gives it**, so a restore
  keeps its history — and gets *now* when the file has none, as a row typed by
  hand does.

Identical is judged by the second, which is all a CSV holds, and a deadline by
the day, since that is what it is: one stored with a time of day — an imported
one can be — reads back as midnight and is not thereby a task that changed. That
last case was found by laying a real document over its own export; the model
tests had used tidy data.

**A file only changes what it says.** A column the file does not have, an
unreadable date, an unknown category label, or an empty cell where empty cannot
mean "clear" leaves the existing value alone. Empty means *clear* only for
`category`, `project`, `deadline`, `remind`, `completed`, `answered`, `before`
and `notes`; for the stack, the title and the timestamps it means the file has
nothing to say, because a blank stack that moved a task to the inbox, or a blank
`created` that made it new, would let a half-filled spreadsheet damage tasks it
never meant to touch.

**Moving a task's stack in the sheet is an arrival**, and `entered` is stamped
now — unless the sheet also gives an `entered` date, which is how an imported
backlog says it has been sitting there since March.

**Deliberately not in the file:** deletion records, the "already imported"
ledgers of the Reminders and Todoist importers (device bookkeeping, not data),
`dateSemanticsVersion` and the sample flag (derived or internal). A restore
therefore cannot delete anything by itself; only **replace** does, and it
replaces tasks and **only tasks** — every category and project stays.

The rules are `StoreDocument.importing`, a pure function in the model layer,
because the store is not something a test may construct and this is where the
rules a spreadsheet user depends on live.

**Parse the due column leniently.** Only the app's own export uses `yyyy-MM-dd`;
open that file in a spreadsheet and the column comes back in the user's locale,
and hand-written files use whatever the author typed. Accept the common shapes —
`yyyy/MM/dd`, `dd/MM/yyyy`, `dd-MM-yyyy`, `dd.MM.yyyy`, `d MMM yyyy`, a full ISO
timestamp — plus the device's own short and medium date styles, and normalise to
the start of the day. A due date that silently fails to parse looks exactly like
a task that never had one.

A category is written as its *label* on a task or project row, and matched back
case-insensitively on import. Dates are `yyyy-MM-dd`, timestamps ISO 8601.

On import, a `project`/`course`/`hashtag` column, or a title starting with
`#CODE `, sets a task's project (created if new). `tag` means category. A
`group` (or `cluster`) column on a project row puts it in that group, and an
empty one leaves the project's group alone, so a file never takes a project out
of one by leaving a cell blank.

Import offers two modes, chosen before the file picker opens: **add to what is
here**, or **replace all tasks**. Either way it clears any tombstone for an
imported id, or a previous delete would immediately remove it again.

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

**Back Up Now** takes one on demand, kept under the day it was taken. A second
on the same day replaces the first, so pressing the button is never a way to
fill the disk.

**One swipe action per edge**: share on the trailing edge, delete on the
leading one. They were both on the trailing edge to begin with, where a full
swipe runs the first and the second is reachable only by stopping halfway,
which is no way to find it.

**Delete is offered only for the ones taken by hand.** The automatic three
rotate, so removing one buys nothing and the next opening puts it back; a
hand-made copy is the only kind whose going is permanent, and so the only kind
worth a button. Its edge sets `allowsFullSwipe` to false, because the file is
removed rather than trashed: a full swipe is too easy a way to lose the copy
someone made on purpose, and the tap is the confirmation.

### The name is the backup

Each copy is its own file, named for what it is and which device wrote it:

```
DayHand-1day-Fatima-s-iPhone-9c3f.json
DayHand-1week-Fatima-s-iPhone-9c3f.json
DayHand-2026-09-28-Fatima-s-MacBook-Pro-1a2b.json
```

A backup that only makes sense to the app that wrote it is not much of a
backup. The point is a folder of JSON that still means something to someone who
has lost the app — which device, which copy, and when. The device part is the
host name reduced to what a filesystem and a mail attachment can both carry,
plus four fixed characters, because two phones that both call themselves
"iPhone" would otherwise overwrite each other's copies. A `.local` suffix is
dropped: every device has one, so it names none of them.

A date tag is ten characters wide and holds dashes of its own, which is what
makes the name readable back — it is parsed by width, not by splitting on the
first dash.

**When a copy was taken is the file's own timestamp**, not a note kept
somewhere else. An earlier version recorded these in preferences; a file
restored from a device backup while preferences were not is exactly the case
this is meant to survive, and then only the file is telling the truth. Ageing a
copy down the chain carries its timestamp with it, or the copy would appear to
have been taken on the day it was moved.

Anything in the folder that parses is listed, **including a file copied in from
another device** — that is what the name is for. A row says where it came from
when it was not this device, and says it was taken by hand when it was, because
the automatic copy and a manual one from the same day both read "Today" and
choosing the wrong one replaces every task.

Files the earlier version wrote under fixed names are renamed on first launch
rather than left behind, so updating never loses a copy.

More lists them with their age and task count; tapping one restores it behind a
confirmation, and a swipe shares it somewhere safer or deletes a manual one.

Restoring is a rescue, so it has to win: stamp the restored tasks as edited now
and clear their tombstones, or the very delete being undone will simply reapply
from the other device. Tasks added since the backup are dropped locally but
**not** tombstoned — they are not what the user asked to remove, so if the other
device still has them they come back on the next sync.


## One-time import from Apple Reminders

More → Tasks → Import from Apple Reminders opens a copy-only importer on
all three platforms. Nothing is requested on launch: the user first chooses
“Choose lists”, and EventKit then requests full Reminders access (Apple has no
read-only Reminders permission). DayHand never writes to EventKit and installs
no continuous sync observer.

The importer reads a snapshot of the device's ordinary Reminders lists. Each
selected list can go to an existing category, an explicitly selected active
project (which supplies its category), or a newly named project. No list is
selected initially and no project is created until tasks are actually imported.
New project names follow the existing uppercase, no-spaces rule; a collision
with an existing project requires selecting that project explicitly.

Unfinished tasks start in Inbox unless another stack is selected. Completed
tasks require a separate opt-in, retain their known completion dates, and return
to the selected stack if reopened. An unknown completion date stays unknown.
Recurring reminders are skipped rather than silently becoming one-off tasks.
Subtask relationships, tags, attachments and smart-list rules are not preserved.

Due dates optionally become DayHand reminders at 9 a.m. on the corresponding
local day. They never become deadlines or move tasks between stacks. Original
due/start dates and times, notes, links, locations and priority values are kept
in the task's Notes. Original alerts are not transferred. Past reminders arrive
answered; their dates can still make them appear in Attention. Future reminders
may notify in both apps because Apple Reminders is left unchanged. All these
limits are shown before import.

The preview shows individual task exclusions and counts of added, already
imported, skipped and newly created projects. Import recomputes the plan against
the current document, saves a manual backup, and writes the batch once. If the
backup or local write fails it reports an error and does not apply the plan in
memory. No import claims that an iCloud write has already reached other devices.

`StoreDocument.importedReminderIDs` is a union-merged set of namespaced local
EventKit identifiers. It survives deleting an imported task, so importing the
same source again does not resurrect it or overwrite later DayHand edits. It
only marks tasks actually imported. EventKit identifiers are device-local and
may change after account resets or source reorganisation: importing from
another device or after such changes can produce duplicates. There is no
heuristic merging by task title.

Tasks now carry an optional-on-disk `notes` string, defaulting to empty for
older documents. It is editable in the task editor with Done/Cancel semantics,
and round-trips through a new final `notes` CSV column. Existing CSV column
positions and old JSON decoding remain compatible. Devices running older
builds do not understand these new fields; update all devices before relying
on Notes or import history across sync.

Model tests cover mapping, idempotency, deletion history, new-project conflicts,
completion, date-only/time-zone/DST handling, and JSON/CSV compatibility without
constructing TodoStore or opening live app data. Simulator verification still
needs permission denial/retry, list loading, all mapping choices, preview
exclusion, import, reopen, repeat import, cancellation, and a sample recurring
reminder. Use dummy data only; do not launch the Mac app against live data.


## One-time import from Todoist project CSVs

More → Tasks → Import from Todoist opens a separate one-time file importer.
Use Todoist's project menu → Manage data → Export as CSV, then select one or
more UTF-8 CSV files. No account token, OAuth connection, server or continuous
sync is involved. The selected files and the Todoist account are never modified.

Each selected file can go to a category, an explicitly chosen active project,
or a new project. The common `TaskImportDestinationFields` is shared with Apple
Reminders, and existing projects always supply their category. New project
names follow the app's existing uppercase, no-spaces rule. Empty files and
excluded tasks create no projects. Inbox is the default destination stack.

`TodoistCSV` is Foundation-only and parses the documented TYPE/CONTENT format.
It supports task, section, note and meta rows, reordered columns, a UTF-8 BOM,
quoted multiline fields, escaped quotes, CRLF, and older files missing optional
columns. Malformed quoting, duplicate headers, missing required headers and
extra fields are rejected before import. UTF-8 and a 20 MB per-file limit are
checked by the file reader off the main actor. A failed file load does not
partially replace the current selection.

Task titles, including label text already in them, remain literal. The importer
uses the existing `TodoItem.notes` field, task editor and CSV support from main;
it introduces no second Notes feature or additional task panel. Descriptions,
comments, sections, section descriptions, parent-task paths, assignees,
priorities, original date strings, date languages, time zones, durations and
other nonempty exported details are preserved as text in Notes. Comment rows
attach to the preceding task. Notes can be expanded in the import preview,
then edited in the existing task editor after import. They survive JSON, sync,
backups and the existing final `notes` CSV column.

Subtasks become independent tasks. Section and parent relationships are not
recreated as live structures; their context stays in Notes. Orphan comments and
unsupported row types are counted as ignored CSV rows. Attachment links in
exported text are retained in Notes; attachments are not downloaded. Recurring
schedules are not recreated. These limits are shown in the preview.

Only unambiguous absolute dates are parsed: ISO civil days, ISO timestamps with
offsets, and year-month-day times with the exported time zone. Localized,
relative, recurring, invalid or otherwise unrecognised date expressions are
never guessed. Affected tasks are excluded until the user explicitly enables
“Include tasks with unrecognised dates”. Then they are imported once with
unrecognised dates kept only as text in Notes; recurring schedules are never
recreated. The UI explicitly explains this mapping before import.
Recognised task dates become reminders at 9 a.m. on the local day. Recognised
deadlines remain deadlines, including when there is no reminder. “Import dates”
can be turned off to keep dates only as text in Notes. Dates never move tasks.
Todoist project CSVs do not include completed tasks; the importer says so.

The preview shows mappings, tasks, exclusions, counts, ignored rows and date
warnings. Confirming recomputes the plan against the current document and uses
the same backed-up single-write commit as the Apple importer. No import
replaces or updates existing tasks by title.

Todoist project CSVs have no stable task ids. `TodoistFileReader` uses SHA-256 of
the filename plus file bytes, and the parser identifies each row within that
file. `StoreDocument.importedTodoistIDs` is a separate union-merged history set
that survives deletion. The exact same unchanged file with the same name is
skipped on repeat import. Edited or renamed exports can produce duplicates;
this limitation is shown before import. Two differently named projects with
identical CSV content remain distinct. No content-based task-title guessing is
used. Source paths are not stored.

### Explicit modern deadlines and the legacy date migration

`TodoItem.dateSemanticsVersion` defaults to 1 for new tasks and to 0 when absent
from old JSON. The legacy migration only visits version-0 tasks, promoting old
standalone deadlines into reminders as before and marking all visited tasks as
version 1. It never stamps `modifiedAt`. Explicit modern standalone deadlines
therefore survive reload, sync and clearing a reminder. DayHand CSV headers
naming `deadline` are modern; old `due` headers and headerless legacy files keep
the legacy migration. Update all devices before relying on the new marker,
Notes or either import history across sync: older builds ignore these fields.

### Verification and remaining runtime checks

The model tests include Todoist's official CSV template (downloaded from its
Help Center on 25 October 2026), quoted fields, hierarchy and comment association,
invalid files, conservative date parsing, opt-in handling, exclusions, repeated
imports, deletion history, history merging and deadline migration. They never
construct TodoStore or read live app data. The fixture source is documented in
Tests/Fixtures/README.md.

Simulator runtime access remains unavailable in this session. Before release,
use dummy exports to check the file picker on iPhone/iPad, cancellation,
UTF-8/error messages, multiple files, all project/category mappings, preview
exclusions, the date-review opt-in, imported Notes, import, the
backup, reload,
repeat import after editing/deleting a task, and the Mac layout. Do not launch
the installed Mac app or use its real data to perform these checks.

**The decision is pinned to the bottom; nothing about it scrolls.** The task and
its details take the room that is left at the top, and the four moves — Now,
Next, Later, Waiting — sit below as large colour-coded buttons in a two-by-two
grid, each with its one-line explanation, with Edit, Keep in Inbox, Complete and
Delete in a row beneath them. Only the details scroll, and only when Notes run
long.

This replaced a form-style list with the moves below the details. That put the
only thing the screen is for under a scroll on every task — and the scroll
position then survived the decision, so the *next* task opened with its title
above the top edge: you would be pressing the buttons for a task you could not
see. With the actions fixed in place there is nothing to scroll to and nothing
to lose; each task is a glance and a tap.

Details shown: the title, the age, the project and category, the reminder and
deadline, and the Notes **in full rather than behind a disclosure** — they are
often what decides it, and deciding is the purpose of being here.

The undo bar sits **above** the buttons, in the layout, not over them, so a
control never moves under a thumb when it appears. The finished state keeps its
one action beside its message rather than at the screen's edge.

A task's project is marked with the **paperclip**, as everywhere else in the
app; the folder means a group.

### Inbox age in the review helper

Below the task title, show a neutral secondary label: **Entered Inbox today**,
**In Inbox for 1 day**, or **In Inbox for N days**, based on `enteredStackAt`.
Count local calendar days, including across daylight-saving changes. Refresh
while the helper stays open; hide future dates rather than show negative ages.
No warning colour or automatic movement. The existing migration uses creation
date for older tasks without an entry date; the helper uses that same value,
which the user can correct in the existing task editor.

## Now review helper

**Review Now** is available at the Now heading and in More → Review. It shares
the Inbox helper's exact layout implementation: scrolling details (reset for
each task), visible Notes, stack age, a bottom-pinned two-column decision grid,
secondary actions and an Undo banner above the controls. Inbox behavior stays
the same. Now asks **Am I still actively working on this?**:

- **Keep in Now** — Yes, still working on it.
- **Next** — Not now, but it is next.
- **Later** — I am putting this aside.
- **Waiting** — I am blocked or waiting.

Keep advances only the local review, preserving `enteredStackAt`, reminders,
`modifiedAt` and all task data. Edit, Complete and Delete remain secondary;
Delete still confirms. No separate Skip button. Users can close and resume.
Now and Inbox have separate local session keys, preserving existing saved
Inbox progress. Both use the same ID snapshot model; live edits, deletion,
Undo and new arrivals follow the same rules. Now reviews all Now tasks,
regardless of main-list filters, and shows its neutral time-in-Now label.
At the end, kept work remains in Now; reviewing again starts a new pass.

## Waiting review helper

**Review Waiting** appears at the Waiting heading and in More → Review. It
uses the same shared layout as Inbox and Now, asking **Am I still waiting,
or can this move forward?** Four primary choices: Still waiting (keep), Now
(I can work on this now), Next (It is ready; I will tackle it next), and Later
(I am putting this aside). Keeping advances the review without touching the
entry date, reminder or edit timestamp. Age is shown neutrally as Waiting
since today / Waiting for 1 day / Waiting for N days.

**Edit / set reminder** opens the existing editor, where a follow-up reminder
can be set without moving the task; saving an edit alone does not advance the
review. Complete and confirmed Delete stay secondary. Undo, live task reads,
new-arrival handling and resume use the shared mechanics. Waiting saves its
progress under waitingReviewSession.v1, independently of Inbox and Now.
