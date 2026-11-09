# Kinboard

A family organizer for iPhone and iPad. The family calendar, the to-dos, the kids' trackers,
the spending, and every message from school, daycare and coaches go into one app, so the
details stop living in five inboxes and somebody's head.

No account, no backend, no subscription. Everything stays on the device.

## What it does

**Today** is the dashboard: today's and tomorrow's schedule, to-dos that are due or
overdue, messages waiting for review, one-tap tracker buttons, this month's spending
against budget, and what's coming up this week, birthdays included. Tap a child's
picture for their page.

**Calendar** shows a month grid with coloured dots per person, and the chosen day's
events and to-dos below it. Events can repeat ("soccer on Tuesdays and Thursdays",
"every other week", "the 1st of every month"), and you can delete one occurrence without
losing the series. Reminders arrive as notifications. **Add to Apple Calendar** opens
Apple's own new-event sheet, already filled in, so you can put the event on a shared
iCloud family calendar.

**Tasks** groups to-dos into Overdue, Today, Tomorrow, Next 7 days, Later and Anytime. Each
to-do has who's doing it and who it's for, so "sign Maya's permission slip" is assigned
to a parent and filed under Maya. Repeating chores add the next one when they're
checked off. If one is done late, the next due date counts from when it was finished,
so the chore doesn't reappear already overdue.

**Inbox** is where messages come in. See below.

**Spending** has the month's total against budget, a breakdown by category, a six-month
trend, and budget bars per category. Each expense records which child it was for and who
paid. Receipt photos attach to expenses. **Reimbursement status** (to submit → submitted →
reimbursed) tracks FSA, HSA and insurance claims, and the dashboard shows how much is
still owed back.

**Family** (top-left on Today) holds:
- **People**: each child's page shows their trackers, the next two weeks, their to-dos,
  important info and contacts.
- **Trackers** for anything you count or time. Presets cover bottles, nursing, diapers,
  sleep, medicine, temperature, weight, height, reading, screen time, tummy time and
  potty. A quantity gets a number and unit, a duration gets start and stop, and an
  event just records when. Each tracker has a chart and its history.
- **Contacts**: the pediatrician, teachers, coaches and sitters, with tap-to-call,
  tap-to-text and tap-to-email.
- **Important Info**: shoe sizes, allergies, insurance numbers, the school's room number.
- **Settings**: currency, reminders, export and backup, the sample family, and the
  self-check.

## How messages become events and to-dos

Tap **Capture** in the Inbox, or **+ → Capture a message** on Today, and bring the message
in one of three ways:

- **Paste** an email or text you've copied.
- Pick a **screenshot or photo**. A screenshot of a group text, a ClassDojo post or the
  daycare app all work. Kinboard reads the text on the device.
- **Scan a paper note.** The system document scanner finds the page edges, so the flyer
  from the backpack comes out flat and readable.

Kinboard then reads the message sentence by sentence and suggests:

| The message says | Kinboard suggests |
|---|---|
| "Picture day is November 13!" | **Event:** Picture day, all day Nov 13 |
| "Please return the signed permission slip by Friday." | **To-do:** Return the signed permission slip, due Friday |
| "The field trip costs $12, due by Nov 20." | **To-do:** Pay for field trip, due Nov 20 · **Expense:** Field trip, $12 |
| "The winter concert is Dec 10 at 6:30 PM in the gym." | **Event:** Winter concert in the gym, Dec 10, 6:30 PM |
| "Please bring a change of clothes." | **To-do:** Bring a change of clothes |

Each suggestion has **Add**, which adds it as it is, and **×**, which dismisses it. Tap a
suggestion to check or change the details before adding. Nothing goes on the calendar
until you tap. A child named in the message is tagged automatically. Whatever gets
added keeps a link back to the message it came from.

This is pattern matching, not AI. Dates are found by Apple's `NSDataDetector`, the same
engine that underlines dates in Mail. Around those dates Kinboard looks for deadline
words ("by", "due", "RSVP"), requests ("please", "bring", "sign"), event words
("concert", "practice", "picture day") and dollar amounts. It handles typical school and
coach messages well, and a wordy newsletter may need a dismiss or two. Suggestions are
stored when a message is captured, because "this Friday" means the Friday after the
message arrived, not the Friday after you happen to reopen it.

**Why it can't read your email or texts by itself:** iOS doesn't let any app read
Messages, and reading Gmail would mean signing in to Google through a server. Copy and
paste, screenshots and scanning keep all of it on the phone.

## Building it

### On an iPad (no Mac required)

1. Install **Swift Playgrounds** from the App Store (iPadOS 17 or later).
2. Get `Kinboard.swiftpm` onto the iPad: clone with [Working Copy](https://workingcopy.app),
   or download the repository as a zip and open `Kinboard.swiftpm` from Files.
3. Open it in Swift Playgrounds and press **Run**.
4. On first launch, add your family. Or tap **Explore with a sample family** to look
   around with made-up data first. You can replace it later in Settings.
5. Give it an icon in **App Settings** if you like. Playgrounds adds your choice to
   `Package.swift`.
6. To keep it as a real app on the Home Screen, use the project's ⋯ menu. Keep the
   project in Playgrounds so you can rebuild.

### On an iPhone

Swift Playgrounds can't install an app straight onto an iPhone. There are two ways:

- **TestFlight:** with a paid Apple Developer account ($99/year), Swift Playgrounds can
  upload the app to App Store Connect from the project's App Settings. Then install it
  on any family iPhone through TestFlight.
- **Xcode on a Mac:** open the `.swiftpm` in Xcode and run it on a plugged-in iPhone.
  A free Apple ID works, but the app has to be re-signed every 7 days.

## Things worth knowing

**Each device keeps its own data.** Syncing between two parents' phones needs iCloud
(CloudKit). That requires an entitlement Swift Playgrounds can't declare — the same
limitation as Apple Health in PowerZone Ride. Until then:
- Use **Add to Apple Calendar** to put events on a shared iCloud calendar, so everyone
  sees them in the Calendar app.
- **Settings → Export & Back Up → Full backup**, then **Restore from Backup** on the other
  device, moves everything across. It replaces, it doesn't merge.

Moving the project to Xcode on a Mac would make real sync possible.

**Back it up.** Deleting the app deletes its data. **Settings → Export & Back Up** writes:
- a full backup (`.json`), for restoring
- the calendar as `.ics`, for Apple, Google or Outlook Calendar, with repeats
- expenses as `.csv`, for a spreadsheet, taxes or FSA claims
- the tracker log as `.csv`, for the pediatrician

Kinboard also keeps the previous version of its data file as a safety net. If its save
file is ever unreadable, it starts fresh but keeps the old file beside the new one rather
than overwriting it.

**Reminders** need notification permission, which Kinboard asks for the first time you
set a reminder. iOS allows an app 64 pending notifications, so Kinboard schedules the
next two weeks and refreshes the list every time something changes.

## Checking that it works

**Settings → Run Self-Check** runs 36 checks on the device. They cover repeats across a
daylight-saving change, months without a 31st, chores done late, money parsing, calendar
and CSV file formats, saving and loading, and message reading against this iPhone's own
date detection.

The same checks run on any Mac or Linux machine with Swift. That's where to prove a fix to
the logic before rebuilding on the iPad:

```
tools/check_kinboard_core.sh                 # run the checks
tools/check_kinboard_core.sh --show-sample   # also print what the sample messages turn into
```

## How it's put together

```
Kinboard.swiftpm/
  Core/       Plain Swift + Foundation: the data model, repeats, message reading,
              exports, sample family, self-checks. No UI, so it compiles on Linux.
  Services/   The store (JSON file in Application Support), Apple's date detector,
              on-device text recognition, reminder scheduling.
  Views/      SwiftUI, one file per area: Today, Calendar, Tasks, Inbox, Spending,
              Family, Trackers, Settings.
tools/check_kinboard_core.sh   Builds Core/ with a stand-in date detector and runs the checks.
```

All data is one `FamilyData` value saved as a single JSON file. A family produces
thousands of records, not millions, so one file keeps saves atomic and makes a backup a
plain copy. Money is stored as whole cents. A skipped occurrence of a repeating event is
stored as a calendar day ("2026-11-14"), not a timestamp, so it survives the save file's
round trip.

## Ideas for later

- **iCloud sync** between parents' devices (needs Xcode, see above).
- **Smarter message reading** with Apple's on-device language model on iPhones that
  support Apple Intelligence, kept alongside the current rules as a fallback.
- **Home Screen widgets** for today's schedule and quick tracker logging (also needs Xcode).
- **A shared allowance / chore-points system** for the kids.
