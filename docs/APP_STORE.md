# DayHand — App Store submission information

Last reviewed: 25 October 2026. English master copy.

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
| Subtitle | `Tasks for your life and work` — 28 characters; limit 30 |
| Primary language | English; **TO CONFIRM** the existing App Store Connect locale |
| Primary category | Productivity; matches the Mac category declared in the project |
| Secondary category | **OWNER DECISION:** leave unset unless another category genuinely fits |
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

### Promotional Text — draft, limit 170 characters

Keep tasks in Now, Next, Later and Waiting. Set purposeful reminders and deadlines, and work across iPhone, iPad and Mac through your own iCloud Drive.

### Description — draft, limit 4,000 characters

Organise your tasks around your life and your objectives, not the calendar.

Preparing a talk, writing a manuscript, building a feature, renovating a room — real work often takes several days. DayHand lets a task stay active for as long as it takes. Leaving it unticked tonight does not mean you have failed to finish today’s list.

Inspired by Kanban, DayHand adapts the simplicity of cards and stacks to managing your life and work.

A PLACE FOR EVERY TASK

• Inbox: capture a task and decide where it belongs when you are ready, or choose its stack as you add it.
• Now: what you are actively working on, even if it takes days or weeks.
• Next: what you intend to pick up next.
• Later: ideas and tasks you are keeping for the future.
• Waiting: work held up by a reply, a delivery, feedback, or something else you need before you can continue.

You decide when a task moves. Nothing rolls over automatically. Tick it off when the work is finished and it goes to Completed.

DATES WITH A PURPOSE

Reminders bring a task back to your attention on a chosen day, with a notification and a coloured edge. Add an optional deadline alongside a reminder when there is a genuine finish date. Neither moves a task or marks it completed. The deadline stays visible as a finish date; it does not send a separate alert.

KEEP RELATED WORK TOGETHER

Give tasks a project, organise broad areas of your life with categories, and gather related projects into groups. Search task titles, project names and group names. Filter the work you want to see, and archive finished projects while keeping their tasks accessible.

SEE WHAT YOU HAVE ACCOMPLISHED

Review completed work from this week or last week. Browse your all-time completion timeline by month and day, or open an individual project’s History. Keep a record of what you finished alongside the work still ahead.

ONE APP ACROSS YOUR DEVICES

Built for iPhone, iPad and Mac from the start. A shared file in your own iCloud Drive keeps your tasks in sync without a DayHand account or server. Choose that same file on each device once, then work on your tasks wherever you are.

YOUR TASKS STAY YOURS

Keep automatic backups on days you open the app, take extra backups by hand, and share a copy somewhere safer. CSV import and export let you bring tasks in or take them with you.

Available in English, French, Dutch, German, Spanish, Italian and Portuguese.

### Keywords — draft, limit 100 bytes

```text
todo,tasks,kanban,projects,reminders,deadlines,organise,work,personal,planner,checklist
```

This is a starting proposal, not keyword research or a ranking guarantee.
Use commas, avoid duplicate terms already covered by the app name, and do not
include competitors’ names. Recheck the byte count after translation.

### What’s New in This Version

For a first App Store release, do not invent an update history; use the field
only if App Store Connect requests it. For subsequent releases, write actual
changes since the previous public release, within the 4,000-character limit.
TestFlight changes are not automatically changes since the last App Store release.

Template — replace before use:

```text
[The main user-visible change in this release.]

• [Another change actually included in this build.]
• [A specific fix or improvement, if applicable.]
```

### URLs and copyright

| Field | Value / action |
| --- | --- |
| Marketing URL | https://amouraux.github.io/DayHand/ |
| Support URL | **TO CONFIRM:** publish a reachable support page with a clear contact route. The current homepage links to GitHub issue reporting; verify that it meets the intended support needs before using it. |
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

1. **Your tasks are not a daily deadline:** show Now, Next, Later and Waiting.
2. **Capture first, decide when ready:** show Inbox and new-task creation.
3. **Keep work together:** show projects, categories, groups and filtering.
4. **Give dates a purpose:** show a reminder and a genuine deadline.
5. **See what you finished:** show the weekly review or completion timeline.
6. **One app across your devices:** show the appropriate interface for each
   platform without implying an iPad screenshot is the Mac app.

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

Filter opens projects, categories and groups. A project’s information button opens its editor and History. More (the ellipsis button) contains weekly reviews, All time completion history, category settings, sync, CSV import/export and backups.

To test sync, use More → Create Sync File on one device and save the file in your iCloud Drive. On another device using the same iCloud Drive, use More → Use Existing Sync File and select that file. Choose Merge With This Device to retain tasks from both devices. No DayHand account or server is used.

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

### Current implementation versus proposed business model

The reviewed source has no implemented purchase flow or paid limits. The
session’s proposed model is a free download with one non-consumable purchase
that unlocks the app across iPhone, iPad and Mac on the same Apple Account.
It is a plan, not a feature of the current build.

| Decision / field | Status |
| --- | --- |
| Launch with or without the paid unlock | **OWNER DECISION** |
| Free allowances | Proposed: 4 categories, 5 unarchived projects; unlimited tasks |
| Review access | Proposed: This week free; Last week paid. **OWNER DECISION:** where All time and project History belong |
| Unlock name / product identifier | **TO COMPLETE** if implemented; use one shared product across platform versions |
| Purchase type | Proposed non-consumable, one-time purchase; no subscription |
| Price and storefront equivalents | **OWNER DECISION**; no price has been selected |
| Family Sharing for the purchase | **OWNER DECISION**; distinct from the purchaser restoring on their own devices |
| App download price | Proposed free if the in-app unlock is adopted; **TO CONFIRM** |
| Distribution method | **OWNER DECISION:** public App Store distribution for the intended launch |
| Countries / regions and launch date | **OWNER DECISION** |
| Release option | **OWNER DECISION:** manual, automatic after approval, or scheduled option where available |

If the unlock is included, also complete its display name, description,
localisations, price, review screenshot and review notes in App Store Connect.
Implement and test purchase, restoration and cross-device entitlement handling;
include the first in-app purchase with the app submission as required by Apple.
Update the product description and review notes to explain the exact free/paid
boundary before submitting. Do not advertise the upgrade while it is unimplemented.

If charging for the app or an in-app purchase, confirm the relevant agreements,
tax and banking setup in App Store Connect. Do not enter financial or private
contact details into this public file.

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

Checked on 25 October 2026. Apple’s current UI and documentation take precedence
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
