# DayHand — App Store submission information

Last reviewed: 31 October 2026. Source reviewed: `fdd1dcd` (main). English master copy.

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
| Privacy Policy URL | https://amouraux.github.io/DayHand/privacy.html — verify after deployment from main |

The first version and the Mac platform need their own version information and
assets where App Store Connect requests them. Sharing an app record does not
mean every field or screenshot is automatically copied to both platforms.

## 2. Public product-page text

Use this English copy for each platform where it accurately describes the
selected build. Translate metadata separately for other storefront languages;
the app's languages do not automatically create translated store listings.

### Promotional Text — 156 characters; limit 170

A familiar task manager with a refreshing approach: organise work into Now, Next, Later and Waiting, with guided reviews to help you decide what comes next.

### Description — 3,489 characters; limit 4,000

Your task manager asks which day. Your work takes as long as it takes.

Preparing a talk, planning a trip, building a feature, renovating a room — much of what matters cannot fit neatly into a daily checklist. Yet many task managers encourage you to assign a date before you know when the work will happen. When that day passes, unfinished tasks become overdue. You reschedule them and feel behind, even when the work is progressing as it should.

DayHand lets a task stay active for as long as it takes, without having to assign it a new day each morning. Organise your life and work around what you are doing Now, what comes Next, and what belongs Later. Capture new tasks in Inbox until you are ready to decide.

Some work depends on someone else. Waiting gives tasks awaiting feedback, a delivery or a decision a place of their own.

And when your lists need a rethink, guided reviews help you make decisions. Where does this task belong? Am I still working on this? Can this move forward? Is it still relevant? Review tasks one at a time, or walk through your projects to check that each has a clear next step.

If you already use a task manager, DayHand will feel familiar: tasks, projects, notes and reminders. What feels refreshing is organising work around your intentions, with room for tasks to take several days and guided reviews to help you reconsider what matters. Inspired by Kanban, adapted to your life and work.

A PLACE FOR EVERY TASK

• Inbox: capture first, decide when you are ready.
• Now: what you are actively working on, for as long as it takes.
• Next: what you intend to pick up next.
• Later: ideas and tasks you are keeping for the future.
• Waiting: work that needs someone or something else before you can continue.

On Mac and iPad, a sidebar lets you browse categories, groups and projects and focus on the work you want to see. You decide when tasks move and when they are complete.

DATES WITH A PURPOSE

Sometimes a task does need a date. A reminder brings a task back to your attention with a notification and a coloured edge, and tapping the notification opens the task. A deadline shows a genuine finish date without a separate alert. The flag button gathers every task with a coloured edge, from any stack. Dates never move tasks automatically.

KEEP RELATED WORK TOGETHER

Use projects for related tasks, categories for broad areas of your life, and groups to gather projects. Add notes, search and filter your work, and archive finished projects while retaining their tasks.

Review a single stack or all your tasks without repeating tasks you have moved during that pass. Project reviews let you add a next step, review related tasks, or archive a finished project.

SEE WHAT YOU HAVE ACCOMPLISHED

Browse completed tasks in a timeline organised by month and day, or open a project’s History.

ONE APP ACROSS YOUR DEVICES

Designed for iPhone, iPad and Mac from the start. Choose the same file in your own iCloud Drive on each device to keep your tasks in sync. Your data stays in your own files, with no DayHand account or server.

BRING YOUR TASKS WITH YOU

Import from Apple Reminders or Todoist CSV exports, or use DayHand’s CSV import and export. Imports copy tasks into DayHand without ongoing sync to the original app. Automatic local backups and manual backups help you keep a recoverable copy.

Available in English, French, Dutch, German, Spanish, Italian, Portuguese, Japanese, Korean, Swedish, Danish, Norwegian, Finnish and Polish.

### Free and paid paragraph — append only when purchases are ready

Free to use with unlimited tasks, categories and groups, up to three active projects, and the last 30 days of completed history. Review helpers, notes, reminders, imports, exports, backups and sync are included. A single one-time purchase unlocks unlimited active projects and full completed history across your iPhone, iPad and Mac using the same Apple Account. No subscription. Archived projects do not count towards the free limit, and nothing is deleted if you choose not to upgrade.

**Maintainer note — not listing copy:** the main description above describes
implemented features. Append the free/paid paragraph only after StoreKit
purchase and restoration work on both platforms. The combined description and paragraph total 3,978 characters, including
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
| Support URL | https://amouraux.github.io/DayHand/help/ — the single Help and support page; verify after it is deployed from main |
| Privacy Policy URL | https://amouraux.github.io/DayHand/privacy.html — verify after deployment from main |
| User Privacy Choices URL | Optional: https://amouraux.github.io/DayHand/privacy.html#choices — verify after deployment |
| Copyright | **TO COMPLETE:** `2026 [confirmed rights holder]`; do not assume the rights holder from Git author details |
| Public App Store link | **TO COMPLETE after the record’s numeric Apple ID and availability are confirmed**; this is distinct from the TestFlight link |

### Localised URLs

The homepage, the privacy policy and the help page exist in every app
language. App Store Connect takes a Marketing URL, a Support URL and a Privacy
Policy URL per localisation, so enter the matching one for each (the marketing
URL is `…/DayHand/<folder>/`); a language without its own falls back to the English
pages above. Folders are the same for both pages:

| App Store localisation | Folder | Privacy Policy URL | Support URL |
| --- | --- | --- | --- |
| German | `de` | …/DayHand/de/privacy.html | …/DayHand/de/help.html |
| Spanish | `es` | …/DayHand/es/privacy.html | …/DayHand/es/help.html |
| French | `fr` | …/DayHand/fr/privacy.html | …/DayHand/fr/help.html |
| Italian | `it` | …/DayHand/it/privacy.html | …/DayHand/it/help.html |
| Dutch | `nl` | …/DayHand/nl/privacy.html | …/DayHand/nl/help.html |
| Portuguese (Portugal) | `pt-pt` | …/DayHand/pt-pt/privacy.html | …/DayHand/pt-pt/help.html |
| Portuguese (Brazil) | `pt-br` | …/DayHand/pt-br/privacy.html | …/DayHand/pt-br/help.html |
| Japanese | `ja` | …/DayHand/ja/privacy.html | …/DayHand/ja/help.html |
| Korean | `ko` | …/DayHand/ko/privacy.html | …/DayHand/ko/help.html |
| Swedish | `sv` | …/DayHand/sv/privacy.html | …/DayHand/sv/help.html |
| Danish | `da` | …/DayHand/da/privacy.html | …/DayHand/da/help.html |
| Norwegian | `nb` | …/DayHand/nb/privacy.html | …/DayHand/nb/help.html |
| Finnish | `fi` | …/DayHand/fi/privacy.html | …/DayHand/fi/help.html |
| Polish | `pl` | …/DayHand/pl/privacy.html | …/DayHand/pl/help.html |

(`…` is `https://amouraux.github.io`.) The translations say that the English
page prevails; verify each URL after the pages are deployed from main.

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

**Screenshot sets in the repository** (English interface, invented demo data from
`Tests/make_demo.py`, status bar at 9:41, taken on the simulator):

- `docs/screenshots/appstore/iphone-6.3/` — seven iPhone shots at 1206 × 2622, taken
  on an iPhone 17. **This is the set App Store Connect requires**: the
  "iPhone with Dynamic Island (medium display)" slot, 6.1″/6.3″, accepts 1179 × 2556
  or 1206 × 2622 (and the landscape equivalents). Same seven screens and order as
  below; alpha removed.
- `docs/screenshots/appstore/iphone-6.9/` — the same seven at 1320 × 2868, taken on an
  iPhone 17 Pro Max. Optional: the large-display slot is not required when the
  medium one is supplied, and a medium set is not scaled up from it by hand.
- `docs/screenshots/appstore/ipad-13/` — seven iPad shots at 2752 × 2064
  (landscape, the layout with the Organise sidebar), in the same order: Now with
  the project sidebar, reminders (the flag filter), task actions, the review
  helper, the timeline, the project review, and dark mode. Apple accepts
  2752 × 2064 or 2064 × 2752 for the 13-inch iPad slot.

- `docs/screenshots/appstore/mac-2560x1600/` — seven Mac shots at 2560 × 1600
  (a 1280 × 800 pt window at 2×; one of the sizes the Mac App Store accepts),
  same story and order, taken from the real Mac Catalyst app, not the simulator.
  The window's rounded corners are flattened onto a plain background because
  screenshots may not carry transparency.

None of these sets shows the More sheet's root (it held the temporary Testing control when they were taken; it now shows Purchases). The `-EN` in the iPad file names marks the
language of the interface; localised sets would carry their own suffix.

The website's `docs/screenshots/web/` holds resized JPEG copies of these three
sets (21 files). They are for the page only; submit the full-size PNGs above.

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

### Review Notes — iOS (iPhone and iPad)

Paste into the iOS version's App Review Information. Written for the current
implementation. The in-app purchase paragraph is accurate for the build in the
repository; confirm the product names against App Store Connect before submitting.

```text
DayHand is a task manager for iPhone and iPad. No account or sign-in is required, and no developer credentials are needed. Core features work without setting up sync.

Tap + to create a task. Tasks can be placed in Inbox, Now, Next, Later or Waiting. Tap a task to move it, set a reminder, complete it or edit it. Dates never move tasks automatically. Use the circular checkbox to complete a task.

More (the ellipsis button) contains guided task and project reviews, the completion timeline, imports, exports and backups. On iPad in landscape, a sidebar lists categories, groups and projects.

Reminders ask for notification permission when you set one. A reminder notifies at 9 a.m. on the chosen day, so to see a notification choose tomorrow or later: a reminder set for today after 9 a.m. is shown as due but sends no notification. Tapping the notification opens the task. The flag button gathers every task with a red or orange edge. Deadlines are displayed finish dates and do not generate separate notifications.

Import from Apple Reminders asks permission to read your reminders; Import from Todoist reads a CSV export. Both are one-time copies, not ongoing connections.

To test sync, choose More > Sync > Create Sync File on one device and save it in iCloud Drive. On another device using the same iCloud Drive, choose More > Sync > Use Existing Sync File, select Merge With This Device, and choose the same file. No DayHand account or server is involved.

IN-APP PURCHASES: DayHand is free to download. One non-consumable purchase, "DayHand Unlimited" (com.andremouraux.tnt.unlock), unlocks unlimited active projects and the full history of finished tasks. The free version keeps up to three active projects and shows the last 30 days of finished tasks; nothing is ever deleted, and every task can still be added and edited. A free non-consumable, "30-day Trial" (com.andremouraux.tnt.trial), lets the user try everything for 30 days; it starts only when the user chooses it and ends by returning to the free version, with no charge. To see the limits, create a fourth active project (the Filter button, under Organise). To buy or start the trial, use the unlock screen that appears, or More > Purchases. Restore Purchases is in More > Purchases.
```

### Review Notes — macOS

Paste into the macOS version's App Review Information. Reviewed against the
Mac screenshots, not against a running Mac build: confirm the right-click on backups
and the sidebar before submitting.

```text
DayHand is a task manager for Mac (also available for iPhone and iPad). No account or sign-in is required, and no developer credentials are needed. Core features work without setting up sync.

Click + to create a task. Tasks can be placed in Inbox, Now, Next, Later or Waiting. Click a task to move it, set a reminder, complete it or edit it. Dates never move tasks automatically. Use the circular checkbox to complete a task.

A sidebar lists categories, groups and projects; use it, or the Filter and Search buttons, to focus on part of your work. More (the ellipsis button) contains guided task and project reviews, the completion timeline, imports, exports and backups. In More > Backups, right-click a backup to restore, share or delete it.

Reminders ask for notification permission when you set one. A reminder notifies at 9 a.m. on the chosen day, so to see a notification choose tomorrow or later: a reminder set for today after 9 a.m. is shown as due but sends no notification. Clicking the notification opens the task. The flag button gathers every task with a red or orange edge. Deadlines are displayed finish dates and do not generate separate notifications.

Import from Apple Reminders asks permission to read your reminders; Import from Todoist and DayHand CSV import read a file you choose. These are one-time copies, not ongoing connections.

To test sync, choose More > Sync > Create Sync File on one device and save it in iCloud Drive. On another device using the same iCloud Drive, choose More > Sync > Use Existing Sync File, select Merge With This Device, and choose the same file. DayHand is sandboxed and can only read the file you pick. No DayHand account or server is involved.

IN-APP PURCHASES: DayHand is free to download. One non-consumable purchase, "DayHand Unlimited" (com.andremouraux.tnt.unlock), unlocks unlimited active projects and the full history of finished tasks. The free version keeps up to three active projects and shows the last 30 days of finished tasks; nothing is ever deleted, and every task can still be added and edited. A free non-consumable, "30-day Trial" (com.andremouraux.tnt.trial), lets the user try everything for 30 days; it starts only when the user chooses it and ends by returning to the free version, with no charge. To see the limits, create a fourth active project (the Filter button, under Organise). To buy or start the trial, use the unlock screen that appears, or More > Purchases. Restore Purchases is in More > Purchases.
```

**Purchase review notes.** The source now implements the purchase (StoreKit 2),
Restore Purchases and the user-started trial; there is no test switch and
nothing is unlocked by environment, so the reviewer sees the real limits and
buys in the sandbox. Before submission, create both products in App Store
Connect with the identifiers above and attach each product's review screenshot
(the unlock screen is in More > Purchases, or by creating a fourth active
project). The free limits are three active projects and 30 days of completed
history; older tasks remain in the data, backups and exports, and are
searchable. No task capture is blocked.

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
- **Privacy policy:** `docs/privacy.html` covers storage, sync, imports, notifications,
  support, retention and deletion. Publish it from main and verify its URL before
  entering it in App Store Connect. The app links to it from More → Help. The bundled
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

Implemented for 1.0: free/paid entitlement rules, a three-active-project limit, a
rolling 30-day completed-history limit, the unlock screen, the StoreKit purchase,
Restore Purchases and the user-started 30-day trial (a free non-consumable).
`Purchases.storeAccess` starts as free. Still to do outside the code: create the
two products in App Store Connect and choose the price.

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
| Product identifiers | `com.andremouraux.tnt.unlock` (paid) and `com.andremouraux.tnt.trial` (free, display name "30-day Trial"), both non-consumable and wired into `Purchases.swift`; create them with exactly these IDs. **Status (1 November 2026):** the trial exists in App Store Connect at a price of 0 EUR, which confirms a free non-consumable can be created. The unlock is still to create |
| Price and storefront equivalents | **OWNER DECISION:** no price selected; public copy intentionally avoids an amount |
| Family Sharing | Planned enabled, as recorded in `PROMPT.md`; configure and test in App Store Connect |
| Restore Purchases | Required implementation work; expose in Settings and test on both platforms |
| Trial | Planned, user-started 30-day unlimited access; returns to free without a charge |
| Trial product display name | `30-day Trial` — planned separate zero-price non-consumable |
| Trial product description | `Try unlimited projects and full completed history for 30 days. No charge.` |
| Trial product identifier | **TO COMPLETE:** configure with StoreKit implementation; never invent a live identifier here |
| Trial start and expiry | Use the verified transaction date across devices; explain the end conditions before starting |
| TestFlight access | Grandfathered access is planned (`PROMPT.md`, rule 4); confirm entitlement implementation before claiming it. **Caution:** App Review also runs in a non-production sandbox, so a rule of “non-production environment means unlocked” would hide the limits from the reviewer and the purchase from the review screenshots. Settle how testers are recognised (for example Apple’s offer codes for in-app purchases — **TO CONFIRM** availability) before relying on environment detection |
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
