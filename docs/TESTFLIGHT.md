# DayHand — TestFlight information

Last reviewed: 25 October 2026. English master copy.

For the production App Store listing, see [APP_STORE.md](APP_STORE.md).

This file is the source for TestFlight text and submission notes. Copy only
an individual field’s text into App Store Connect, without its heading or the
maintainer instructions. Editing this file does not update App Store Connect.

The descriptions below reflect the current repository. Before using them,
check that the build offered to testers actually includes these features.
TestFlight’s currently distributed build has not been verified here.

## Where each field belongs

| Information | Destination | Update when |
| --- | --- | --- |
| Beta App Description | DayHand → TestFlight → Test Information → selected language | The app’s behaviour or positioning changes |
| Feedback Email | Test Information | The public feedback address changes |
| Marketing URL / Privacy Policy URL | Corresponding test-information fields, where shown | A published URL changes |
| Contact information, sign-in requirements and review notes | TestFlight App Review information | Review access or contact details change |
| What to Test | The selected build’s testing information | Every build distributed to testers |

Keep the website, this file and the public TestFlight description consistent.
Use additional localisations only after translating the current English text;
UI language support does not mean TestFlight metadata has been translated.

## Beta App Description — ready to paste

Organise your tasks around your life and your objectives, not the calendar.

Preparing a talk, writing a manuscript, building a feature, renovating a room — real work often takes several days. DayHand lets a task stay active for as long as it takes. Leaving it unticked tonight does not mean you have failed to finish today’s list.

Inspired by Kanban, DayHand gives every task a place:

• Inbox — capture it now and decide where it belongs later, or choose its stack as you add it.
• Now — what you’re actively working on, even if it takes days or weeks.
• Next — what you intend to pick up next.
• Later — ideas and tasks you’re keeping for the future.
• Waiting — work held up by a reply, a delivery, feedback, or something else you need before you can continue.

You decide when a task moves. Nothing rolls over automatically. Tick it off when the work is finished and it goes to Completed.

Reminders bring a task back to your attention on a chosen day, with a notification and a coloured edge. Add an optional deadline alongside a reminder when there is a genuine finish date. Neither date moves or completes the task; the deadline does not send a separate alert.

Keep related tasks in projects, organise broad areas of your life with categories, and gather related projects into groups. Search task titles, projects and groups, filter the work you want to see, and archive finished projects while keeping their tasks accessible.

Look back at what you finished this week or last week. Browse your all-time completion timeline by month and day, or open a project’s History to see its completed work.

One app across iPhone, iPad and Mac. A shared file in your own iCloud Drive keeps your tasks in sync without a DayHand account or server. Choose that same file on each device once, then work on your tasks wherever you are.

Automatic backups are taken on days you open the app. Manual backups, sharing backups, and CSV import/export are also available.

Available in English, French, Dutch, German, Spanish, Italian and Portuguese. Please send feedback through TestFlight.

## What to Test — baseline text, adapt for each build

Please try DayHand with a small set of example tasks and tell us whether the workflow feels natural on your devices.

• Capture tasks in Inbox or choose another stack when adding them. Move tasks through Now, Next, Later and Waiting; check that dates never move them automatically. Complete and reopen a task.
• Create and rename categories, projects and groups. Try project suggestions, filtering, and searching by task title, project or group. Check the Filter’s project scopes and archiving. On iPad or Mac, also try folding the sidebar and moving projects by their drag handles.
• Edit a task, change its project or group, and check that the explanation of changes affecting other tasks is clear. Cancel an edit and check that it leaves your data unchanged.
• Set a reminder and a deadline. Allow notifications if you want to test alerts. Check the coloured edge, attention filter, snooze and clear actions. The deadline is a displayed finish date, not a separate notification.
• Complete example tasks and check This week, Last week, All time, and a project’s History under More or the project editor. Timelines show completed work, not time spent or a log of task movements.
• On two devices, choose the same shared file in iCloud Drive. Try adding, editing and deleting different example tasks on each device, making an edit while offline, reconnecting, and reopening the app. Check that the devices agree afterwards. If they do not, note the devices, actions, network state and whether Sync Now changes the result.
• Take and share a manual backup; export and reimport a CSV. Use disposable test data for replacement imports and backup restoration because they replace the current task collection. Use a separate shared sync file for these tests so changes do not reach your everyday tasks.

Please report confusing labels or gestures, layout or translation problems, missing or duplicated tasks, unexpected notifications, sync problems and crashes. Include the device, OS, DayHand version/build, steps to reproduce and expected result. A screenshot is useful, but avoid including private task contents.

### Per-build record — fill before distributing

- App version / build: **TO COMPLETE from the actual uploaded build**.
- Source commit: **TO COMPLETE**.
- Platforms included: **TO CONFIRM — iPhone/iPad, Mac**.
- Main changes since the previous distributed build: **TO COMPLETE**.
- Testing priorities specific to this build: **TO COMPLETE**.
- Known issues and available workarounds: **TO COMPLETE after checking this build**.
- Devices / OS versions actually checked: **TO COMPLETE**.

This baseline covers the app broadly. Trim it and put a build’s main changes
first when a shorter testing brief would help. Do not present every existing
feature as newly added, or claim that there are no known issues without
checking the selected build.

## Feedback Email — owner action required

**TO COMPLETE in App Store Connect:** the email address you want testers to
use. Do not substitute the GitHub author email without confirming that it is
the intended public feedback address.

This is also the reply-to address on tester invitation emails. No approved
feedback email is recorded in this repository.

## URLs and invitation reference

| Item | Value / action |
| --- | --- |
| Marketing URL | https://amouraux.github.io/DayHand/ |
| Public TestFlight invitation | https://testflight.apple.com/join/37FbdQp6 |
| Source repository | https://github.com/amouraux/DayHand |
| Issue reporting | https://github.com/amouraux/DayHand/issues |
| Privacy Policy URL | **TO COMPLETE:** no dedicated published policy was found in this repository. Add the actual policy URL; do not use the homepage or the app’s privacy manifest as a substitute. |
| Custom license agreement, if used | **TO CONFIRM in App Store Connect:** no custom agreement is supplied here. |

The invitation and source links are references, not additional TestFlight
form fields. Not every URL field appears in every platform’s interface.

## TestFlight App Review information

### Contact information — enter privately in App Store Connect

- First name: **TO COMPLETE**.
- Last name: **TO COMPLETE**.
- Phone number, with country code: **TO COMPLETE**.
- Contact email: **TO COMPLETE**.

Use a contact who can answer Apple’s review questions. Enter real contact
details in App Store Connect; do not commit private phone numbers, credentials,
API keys or two-factor codes to this public repository.

### Sign-in information

- App sign-in required: **No**.
- Demo account username/password: **Not applicable**.
- Basic task management works without a DayHand account or an iCloud sync file.
- Testing cross-device sync requires the reviewer’s own iCloud Drive access
  and choosing the same shared file on both devices. No developer Apple Account
  or iCloud credentials are needed or provided.

### Review Notes — ready to paste after checking the submitted build

DayHand is a personal task manager for iPhone, iPad and Mac. No app login or demo account is required. Core functionality can be reviewed without setting up sync.

Tap + to create a task. It starts in Inbox unless another stack is chosen. Tap a task to move it between stacks; Edit opens its title, category, project and date controls. The circular checkbox completes a task. Stacks are stored choices: dates never move tasks automatically.

Set a reminder to request a notification on the selected day. Notification permission is requested when reminders are scheduled. A deadline is an additional displayed finish date; it does not create a separate notification. Choose a future day to test a scheduled reminder.

Filter opens categories, groups and projects. On iPad and Mac it appears as a sidebar when space allows. A project’s information button opens its editor and History. More (the ellipsis button) contains weekly reviews, All time completion history, category settings, sync, CSV import/export and backups.

To test sync, open More → Create Sync File on one device and save the file in your iCloud Drive. On another device signed in to the same iCloud Drive, choose More → Use Existing Sync File and select that file. Use Merge With This Device to keep the example tasks on both devices. Sync uses the user-selected file, with no DayHand account or server.

If moving from an older self-built Mac version, the TestFlight app may open with an empty local collection because its storage location differs. The old file is untouched. Selecting the previous shared sync file brings its tasks into the TestFlight app.

## Maintainer checks before using this copy

- Confirm each advertised feature is in the uploaded build, not only on main.
- Review and update known issues; use sample data to test notifications, sync,
  and recovery. Do not use personal data for screenshots or destructive tests.
- Confirm that each platform is available to the intended tester group.
- Verify minimum system requirements against the build: currently documented
  as iOS/iPadOS 17+ and macOS 14+.
- The proposed paid unlock and free-tier limits are not implemented in the
  reviewed source. Do not advertise them as current behaviour.
- Supply the feedback email, review contact details and actual privacy policy URL.
- Check invitation screenshots against the current build. The website’s existing
  sample screenshots predate recent features; they are not a verified current
  set of App Store Connect assets.
- Update the text and save it in App Store Connect. Repository edits alone do
  not change the public invitation or TestFlight app.

## Build and upload instructions

See [CLAUDE.md — Uploading to App Store Connect](../CLAUDE.md#uploading-to-app-store-connect)
for the released Xcode requirement, signing, build-number stamping and iPad
orientation requirements. Keep build instructions there rather than maintaining
a second copy here.

## Apple references

Field locations and workflow were checked on 25 October 2026:

- [Provide test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [TestFlight App Review information](https://developer.apple.com/help/app-store-connect/reference/app-information/testflight-app-review-information/)
