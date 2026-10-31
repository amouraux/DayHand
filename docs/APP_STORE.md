# DayHand — App Store submission information

Last reviewed: 31 October 2026. Source reviewed: `ffb1b71` (main). English master copy.

Use this file to prepare the public App Store listing and production submission
for iPhone/iPad and Mac. For beta distribution, use [TESTFLIGHT.md](TESTFLIGHT.md).
This file does not submit, publish or change anything in App Store Connect.

**Status:** draft metadata based on the repository, not a verified production
release. Items marked **TO COMPLETE**, **TO CONFIRM** or **OWNER DECISION** must
be resolved before submission. Copy only the text for the individual field,
without headings, character counts or maintainer notes.

## 1. App identity and shared information

Use the existing DayHand app record; do not create a second record just for
production distribution or for the paid unlock. Confirm existing identifiers
in App Store Connect before editing them.

| Field | Proposed value / action |
| --- | --- |
| Name | `DayHand` — 7 characters; limit 30 |
| Subtitle | `Tasks beyond the calendar` — 25 characters; limit 30 |
| Primary language | English; **TO CONFIRM** the existing App Store Connect locale |
| Primary category | Productivity; matches the Mac category declared in the project |
| Secondary category | Leave unset; Productivity is the relevant category |
| Platforms | iOS (iPhone and iPad) and macOS (Mac Catalyst); confirm both in the same app record |
| Bundle ID | `com.andremouraux.tnt` in the current project; confirm against the existing record |
| SKU | **TO COMPLETE:** copy the existing record’s SKU; do not invent or replace it |
| Apple ID | **TO COMPLETE:** the numeric app identifier assigned by Apple |
| Age rating | **TO COMPLETE:** answer the current questionnaire for the shipping build; Apple determines the rating |
| Made for Kids | **OWNER DECISION:** general-purpose positioning does not itself establish eligibility for the Kids category |
| Content rights | **TO CONFIRM:** complete Apple’s declaration for the actual content and assets |
| License agreement | **TO CONFIRM:** Apple’s standard EULA unless a custom agreement is chosen |
| Privacy Policy URL | **TO COMPLETE:** a published policy describing the actual app and data practices |

The first version and the Mac platform need their own version information and
assets where App Store Connect requests them. Sharing an app record does not
mean every field or screenshot is automatically copied to both platforms.

## 2. Public product-page text

Use this English copy for each platform where it accurately describes the
selected build. Translate metadata separately for other storefront languages;
the seven UI languages do not automatically create translated store listings.

### Promotional Text — 162 characters; limit 170

Give every task a place: Now, Next, Later or Waiting. Capture ideas in Inbox, review your priorities, and let work take the time it needs on iPhone, iPad and Mac.

### Description — 3,353 characters; limit 4,000

Your task manager asks which day. Your work takes as long as it takes.

Preparing a talk, planning a trip, building a feature, renovating a room — much of what matters cannot fit neatly into a daily checklist. Yet many task managers encourage you to assign a date before you know when the work will happen. When that day passes, unfinished tasks become overdue, and you spend time rescheduling work that is still progressing -- also generates frustration and perception that we are late, overdue, not on track which is not the case --

DayHand lets a task stay active for as long as it takes - without ... --. Organise your life and work around what you are doing Now, what comes Next, what belongs Later, and what is Waiting for someone or something  -- indeed, often, completion of a project includes tasks are beyond your control, because you are waiting for feedback or other -- rather than setting up complex sharing and teams, just a waiting stack -- Capture new tasks in Inbox until you are ready to decide.


And when your lists need a rethink, guided reviews help you make decisions -- On the Mac version, sidebar which allows, on all devices, helpers that work well ... --. Where does this new task belong? Am I still working on this? Can this move forward? Is it still relevant? Review tasks one at a time, or walk through your projects to make sure each has a clear next step. Stop whenever you need to and resume where you left off.

-- Sometimes, tasks do need a reminder, a date -- Use a reminder when you want to bring something back to your attention, and a deadline when there is a genuine finish date. You decide when a task moves.

Inspired by Kanban, adapted -- finetuned -- to everyday task management -- from simple list of tasks to complex project management with ... --.

A PLACE FOR EVERY TASK

• Inbox: capture a task when it comes to mind and decide where it belongs later. You can also choose its stack as you add it.
• Now: what you are actively working on, for as long as it takes.
• Next: what you intend to pick up next.
• Later: ideas and tasks you are keeping for the future.
• Waiting: work that needs a reply, delivery, decision or someone else’s contribution before you can continue.

You decide when tasks move. Complete them when the work is finished.

--should we mention the clean UI, with the stacks and the sidebar? --

DATES WITH A PURPOSE

A reminder brings a task back to your attention on a chosen day. A deadline records when the work really needs to be finished. Dates never move tasks automatically. Reminders provide notifications and coloured edges; deadlines display the finish date without a separate alert.

KEEP RELATED WORK TOGETHER

Use projects for related tasks, categories for broad areas of your life, and groups to gather projects. Add notes to keep useful details with a task. Search and filter your work, and archive finished projects while retaining their tasks.

REVIEW AT YOUR OWN PACE

Review Inbox, Now, Waiting, or Next and Later separately, or review all tasks in one pass without repeating tasks you have moved. Project reviews let you add a next step, review related tasks, or archive a finished project.

SEE WHAT YOU HAVE ACCOMPLISHED

Browse completed tasks in a timeline organised by month and day, or open a project’s History. Your finished work stays connected to the work still ahead.

ONE APP ACROSS YOUR DEVICES

Designed for iPhone, iPad and Mac from the start. Choose the same file in your own iCloud Drive on each device to keep your tasks in sync. Your data stays in your own files, with no DayHand account or server.

BRING YOUR TASKS WITH YOU

Import from Apple Reminders or Todoist CSV exports, or use DayHand’s CSV import and export. Imports bring a copy into DayHand; they do not create ongoing sync with the original app. Automatic local backups and manual backups help you keep a recoverable copy of your work.

Available in English, French, Dutch, German, Spanish, Italian and Portuguese.

### Free and paid paragraph — append only when purchases are ready

Free to use with unlimited tasks, categories and groups, up to three active projects, and the last 30 days of completed history. Review helpers, notes, reminders, imports, exports, backups and sync are included. A single one-time purchase unlocks unlimited active projects and full completed history across your iPhone, iPad and Mac using the same Apple Account. No subscription. Archived projects do not count towards the free limit, and your tasks are never deleted because you stay on the free version -- because you stay, is that clear? --.

**Maintainer note — not listing copy:** the main description above describes
implemented features. Append the free/paid paragraph only after StoreKit
purchase and restoration work on both platforms. The combined description and paragraph total 3,860 characters, including
the separating blank line (limit 4,000). The current build defaults to unlocked access; do not
publish it with copy suggesting these are already functioning purchases.
The planned trial is deliberately omitted from public copy until implemented
and tested. Section 8 records its intended metadata and behaviour.

### Keywords — limit 100 bytes

```text
todo,kanban,projects,reminders,deadlines,organise,work,personal,planner,checklist,notes,productivity
```

English search terms avoid repeating DayHand and the subtitle’s words. This is
a starting set, not a ranking claim. Recheck the byte count after translation.

### What’s New in This Version — limit 4,000 characters

First App Store release: leave this field empty where App Store Connect permits.
There is no previous public release against which to describe changes.

If introductory release text is requested, use:

```text
Welcome to DayHand. Give tasks a place in Inbox, Now, Next, Later or Waiting, review your tasks and projects, and keep your work together across iPhone, iPad and Mac.
```

For subsequent releases, replace this with changes since the previous public
App Store version. TestFlight changes alone do not establish that baseline.

### URLs and copyright

| Field | Value / action |
| --- | --- |
| Marketing URL | https://amouraux.github.io/DayHand/ |
| Support URL | Proposed: https://amouraux.github.io/DayHand/ — verify its support contact route before submission; GitHub issues: https://github.com/amouraux/DayHand/issues |
| Privacy Policy URL | **TO COMPLETE:** no dedicated published policy has been established in this repository |
| Copyright | **TO COMPLETE:** `2026 [confirmed rights holder]`; do not assume the rights holder from Git author details |
| Public App Store link | **TO COMPLETE after the record’s numeric Apple ID and availability are confirmed**; this is distinct from the TestFlight link |

## 3. Version and build fields

Complete these separately for iOS and macOS where required.

| Field | Value / action |
| --- | --- |
| Version | Source currently declares `1.0`; confirm the version being submitted |
| Build | Select the processed production build for that platform; **TO COMPLETE** its uploaded build number |
| Source commit | **TO COMPLETE:** record the exact revision used for the archive |
| Minimum OS | Currently documented as iOS/iPadOS 17+ and macOS 14+; verify the archived products |
| Build processing / compliance | **TO CONFIRM:** resolve any processing errors and outstanding compliance questions |
| App Review attachment | Supply a demonstration or other explanatory attachment if useful or requested |

The build number is generated from the repository’s commit count. Do not copy
a number from this document or assume the current branch head identifies a
previously uploaded build. Use the actual archive and App Store Connect record.

## 4. Screenshots, icon and previews

### Required assets to prepare

- Current App Store icon included in each platform’s archive; check the final
  exported app rather than assuming `docs/icon.png` is the submission asset.
- iPhone screenshot set for Apple’s currently required display slot.
- iPad screenshot set because DayHand supports iPad.
- Separate screenshots of the actual Mac app for the macOS product page.
- Localised screenshots where the listing’s language and visible UI require them.
- App preview videos are optional; prepare them only if they help explain the app.

Apple’s required screenshot slots and accepted dimensions can change. Use the
current [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
and the slots shown in App Store Connect when exporting. Apple currently allows
1–10 screenshots per device size and disallows transparency.

### Proposed screenshot story

1. **Tasks beyond the calendar:** show a task remaining in Now across several days.
2. **A place for every task:** show Inbox, Now, Next, Later and Waiting with clear examples.
3. **Keep related work together:** show projects, categories, groups and task notes.
4. **Dates with a purpose:** show a reminder and a genuine deadline.
5. **Find your next step:** show a task helper’s question and actions.
6. **Give every project a way forward:** show the project review overview.
7. **See what you have accomplished:** show the completion timeline, with the correct free/paid state.
8. **Your tasks across your devices:** use actual platform-specific interfaces.

Use invented demo tasks and the actual shipping interface. Keep captions short,
accurate and readable on a phone. Do not show unavailable paid features, private
tasks, or unsupported claims about instant sync or time tracking.

The existing `docs/screenshots/iphone.png` and `ipad.png` are illustrative older
beta screenshots. There is no current Mac screenshot in that folder. Refresh
assets before submission; do not treat website images as an approved current
App Store screenshot set.

## 5. App Review information

This is the production app review section, separate from TestFlight App Review.

| Field | Value / action |
| --- | --- |
| Contact first / last name | **TO COMPLETE privately in App Store Connect** |
| Contact phone / email | **TO COMPLETE privately in App Store Connect** |
| Sign-in required | No app sign-in in the current implementation |
| Demo username / password | Not applicable to the current implementation |
| Review Notes | Draft below; update for the submitted build and any implemented purchase |
| Review attachment | Optional or as requested; **TO CONFIRM** |

Do not commit personal phone numbers, passwords, API keys or two-factor codes.
The reviewer can use core task management without an iCloud sync file.
Cross-device sync uses the reviewer’s own iCloud Drive; never provide access
to the developer’s personal Apple Account or tasks.

### Review Notes — draft for the current implementation

DayHand is a personal task manager for iPhone, iPad and Mac. No app account or demo login is required. Core task management can be reviewed without setting up sync.

Tap + to create a task. Tasks start in Inbox unless another stack is selected. Tap a task to move it between stacks or choose Edit. The circular checkbox completes or reopens a task. Dates never move tasks automatically.

A reminder requests a notification on a selected day and controls the task’s coloured edge. Notification permission is requested when reminders are scheduled. A deadline is an additional displayed finish date; it does not create a separate notification.

Filter opens projects, categories and groups. A project’s information button opens its editor and History. More (the ellipsis button) contains Review projects, Review all tasks, individual stack helpers, Timeline, category settings, sync, import/export and backups. Helpers save progress locally. The all-tasks helper avoids repeating tasks moved during the same pass. Project review lets you inspect tasks, add a task, review that project’s tasks, edit the project and return to a previous project.

To test sync, use More → Create Sync File on one device and save the file in your iCloud Drive. On another device using the same iCloud Drive, use More → Use Existing Sync File and select that file. Choose Merge With This Device to retain tasks from both devices. No DayHand account or server is used.

Import from Apple Reminders requests permission to read reminders and lets the reviewer select what to import. Import from Todoist reads a CSV export. These are one-way imports, not continuous connections to those services. Use sample data when reviewing either importer.

**Purchase review notes — complete before a paid launch:** the source currently
contains the free/paid rules and unlock screen, but its purchase action is a
stub and automatic access is unlocked. Before submission, implement and test
purchase, Restore Purchases and the intended trial; replace this maintainer
note with the actual product identifiers and reviewer steps. The intended free
limits are three active projects and 30 days of completed history. Older tasks
remain in the data, backups and exports, and are searchable. No task capture is
blocked. Remove the temporary Testing control from the production review flow.

## 6. App Privacy, age rating and compliance

These are declarations to complete in App Store Connect, not marketing text.
Resolve them against the actual shipping build and the owner’s circumstances.

- **App Privacy:** review data collection, purposes, linkage and tracking,
  including any third-party code or services. The current privacy manifest
  declares no tracking and no collected data types; the reviewed app stores
  tasks locally and syncs through a user-chosen file. These are evidence for
  evaluating a possible “Data Not Collected” response, not a substitute for the
  owner checking Apple’s definitions and the final binary. Separately account
  for support/feedback handling and any future analytics or purchase changes.
- **Privacy policy:** publish the actual policy and enter its URL. The bundled
  `PrivacyInfo.xcprivacy` is a technical manifest, not a public privacy policy.
- **Age rating:** complete the current questionnaire, including any capability
  questions presented. Do not hard-code a rating from the app’s productivity category.
- **Export compliance:** the project currently declares
  `ITSAppUsesNonExemptEncryption = NO`. Verify that declaration for the release
  and answer the submission questions; do not infer the legal classification
  solely from the absence of custom encryption code.
- **Content rights / licensing:** confirm rights to the app, icon, screenshots,
  fonts and any included third-party content.
- **Regional declarations:** complete applicable trader, tax, regulatory or
  territory-specific fields shown for the chosen distribution. For EU
  availability, the owner must determine the DSA trader status and provide
  any required verified contact details in App Store Connect.
- **Agreements:** the Account Holder must review and accept any outstanding
  agreements. This document does not authorise accepting them automatically.

## 7. Accessibility information — optional listing information

Audit the submitted app on iPhone, iPad and Mac before claiming support for
Apple’s Accessibility Nutrition Labels. Consider VoiceOver, Voice Control,
Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient
Contrast and Reduced Motion where applicable. The presence of SwiftUI or
accessibility labels in source does not establish that all common tasks work.

Record per-device results before publishing claims. An Accessibility URL can
be supplied if a dedicated page is created. Do not invent one or treat these
optional labels as a substitute for testing.

## 8. Pricing, purchases and availability — owner decisions

### Current implementation and launch plan

Implemented: free/paid entitlement rules, a three-active-project limit, a
rolling 30-day completed-history limit, the unlock screen and a test switch.
Not yet implemented: the StoreKit purchase, Restore Purchases, and the
user-started 30-day trial. `Purchases.storeAccess` currently defaults to unlocked.

The launch plan in `PROMPT.md` is a free download with one non-consumable unlock,
shared across iPhone, iPad and Mac on the same Apple Account, with Family Sharing.
There is no subscription or category limit. This supersedes the earlier
four-category/five-project and paid-weekly-review proposals.

| Decision / field | Value / action |
| --- | --- |
| App download price | Free for the planned launch |
| Free allowances | Unlimited tasks, categories and groups; three active projects; 30 days of completed history |
| Included features | All task and project review helpers, notes, reminders, deadlines, sync, imports/exports and backups |
| Paid unlock | Unlimited active projects and full completed history |
| Archived projects | Do not count towards the limit; archiving frees a place |
| Purchase type | Non-consumable, single one-time purchase |
| Unlock display name | `DayHand Unlimited` — 17 characters; proposed store name |
| Unlock description | `Unlimited active projects and full completed history on all your devices.` — 73 characters |
| Product identifier | **TO COMPLETE:** configure one stable product ID shared across platforms; no identifier is wired into source yet |
| Price and storefront equivalents | **OWNER DECISION:** no price selected; public copy intentionally avoids an amount |
| Family Sharing | Planned enabled, as recorded in `PROMPT.md`; configure and test in App Store Connect |
| Restore Purchases | Required implementation work; expose in Settings and test on both platforms |
| Trial | Planned, user-started 30-day unlimited access; returns to free without a charge |
| Trial product display name | `30-day Trial` — planned separate zero-price non-consumable |
| Trial product description | `Try unlimited projects and full completed history for 30 days. No charge.` |
| Trial product identifier | **TO COMPLETE:** configure with StoreKit implementation; never invent a live identifier here |
| Trial start and expiry | Use the verified transaction date across devices; explain the end conditions before starting |
| TestFlight access | Grandfathered access is planned; confirm entitlement implementation before claiming it |
| Distribution method | Public App Store release planned |
| Countries / regions and launch date | **OWNER DECISION** |
| Release option | **OWNER DECISION:** choose the release option in App Store Connect |

For each in-app purchase, complete localisations, price, review screenshot and
review notes. The unlock’s review screenshot should show the purchase screen
and the two benefits. Trial review notes should explain initiation, expiry,
restoration and the absence of an automatic charge. Verify Apple’s current
submission requirements when configuring these products.

Do not publish trial or purchase claims until the submitted build implements
them. Verify universal purchase and restoration on iPhone/iPad and Mac, and
Family Sharing separately. The free version retains existing tasks and projects;
manual creation above the limit is restricted, while imports, sync and exports
preserve the complete data. Search can find older completed tasks.

Confirm the relevant agreements, tax and banking setup privately in App Store
Connect. Account-specific values and financial details do not belong here.

## 9. Submission record and final checks

- [ ] Record iOS version, uploaded build and source commit: **TO COMPLETE**.
- [ ] Record macOS version, uploaded build and source commit: **TO COMPLETE**.
- [ ] Verify both platforms are attached to the intended existing app record.
- [ ] Copy and save the approved metadata in every intended language/platform.
- [ ] Supply current screenshots, final icon and any chosen preview videos.
- [ ] Publish and verify support and privacy-policy URLs.
- [ ] Complete App Privacy, age rating, content rights and applicable compliance fields.
- [ ] Enter private review contact details; verify reviewer access and notes.
- [ ] Resolve pricing, availability, release timing and any purchase submissions.
- [ ] Verify the archived apps and complete the relevant device, sync,
      notification, import/export and recovery checks with demo data.
- [ ] Review known issues before claiming production readiness; repository text
      and passing model tests do not establish a release-ready binary.
- [ ] Confirm App Store Connect has no unresolved submission errors, then submit.

## 10. Apple references

Text-field limits rechecked on 31 October 2026. Remaining submission references
were collected on 25 October 2026. Apple’s current UI and documentation take precedence
if fields, limits or required assets change.

- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Required, localizable and editable properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Add platforms and universal purchase](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

For signing and archive/upload instructions, see
[CLAUDE.md](../CLAUDE.md#uploading-to-app-store-connect).
