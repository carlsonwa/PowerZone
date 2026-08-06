# PowerZone Ride

An iPadOS app that charts your live power output against Peloton Power Zone workouts from
[Home Fitness Buddy](https://app.homefitnessbuddy.com/peloton/powerzone/).

Home Fitness Buddy's free timing tool tells you which zone you're *supposed* to be in. It
can't tell you what you're actually producing, because Safari on iPad has no Bluetooth
access. This app closes that gap: browse the same library, then ride against the target
profile with your real power drawn over it.

No Peloton subscription needed. No account, no backend — the iPad fetches and parses the
site directly, and nothing leaves the device except the rides you choose to export.

## What it does

- Browse and filter the full library (~1,500 classes) by instructor, duration and type
- Connect to a Bluetooth power meter — built and tested against a **Favero Assioma**
- Live power zone graph: target profile as coloured blocks, your output drawn over it
- The same readouts as the website: current zone, time left in it, the next three blocks,
  total remaining, and ±1s/±10s sync nudges to line up with the class
- Post-ride summary with normalized power, intensity factor, TSS and time in zones
- Export to TCX (Strava, TrainingPeaks, Garmin Connect) or Apple Health

## Building it — on the iPad, no Mac required

1. Install **Swift Playgrounds** from the App Store. Requires iPadOS 17 or later.
2. Get `PowerZoneRide.swiftpm` onto the iPad — clone with [Working Copy](https://workingcopy.app),
   or download this repo as a zip in Safari and open the `.swiftpm` from Files.
3. Open it in Swift Playgrounds. Check **App Settings → Capabilities** lists Bluetooth.
4. Press Run. Grant the Bluetooth prompt.
5. **Settings → Power Meter → Scan.** Spin the cranks first — pedal meters sleep when
   still and won't advertise until they're moving.
6. **Settings → FTP.** Every target is a percentage of this number, so it has to be right.
7. Use the ⋯ menu to build it to the Home Screen as a real app. Keep the Playgrounds
   project on the iPad so you can rebuild if it ever stops launching.

## Using it

Pick a workout, tap **Start Ride**, and start the timer when the class starts. The clock is
anchored to wall time, so it won't drift — but the class video has no way to tell the app
where it is, so the ±1s/±10s buttons are there to line the two up by hand. That mirrors how
the website's tool works.

The graph shows the whole class at once rather than scrolling. On a bike you want to see
that an 8-minute Zone 4 block is coming more than you want resolution on the last thirty
seconds.

## Two things worth knowing

**Apple Health may not work.** Writing to Health needs the `com.apple.developer.healthkit`
entitlement, and a Swift Playgrounds app project has no way to declare it. The code is
there and will start working if this ever moves to Xcode on a Mac; until then expect the
Health button to report that access wasn't granted. **TCX export is the path that always
works** and imports into Strava, TrainingPeaks, intervals.icu and Garmin Connect.

**This reads a website that could change.** There is no API — the workout structure is
extracted from JavaScript embedded in the page. Both parsers are isolated in
`PowerZoneRide.swiftpm/Data/`, every parse is validated against the class length before
it's used, and a workout that fails validation is refused rather than drawn wrong.

## When workouts stop loading

Run **Settings → Run Parser Self-Test** on the iPad. It runs the Swift parsers against
saved copies of real pages bundled with the app. If those pass, it's your network; if they
fail, the site changed its format.

From a machine with Python, `tools/verify_parsers.py` checks the same logic against ~20
live pages and is where a fix should be proven before being ported back to Swift:

```
python3 tools/verify_parsers.py           # check live pages
python3 tools/verify_parsers.py --save    # also refresh the bundled fixtures
```

## How the data is read

The site has no API. The library page returns all ~1,500 classes as one ~530 KB HTML table.
Each workout's detail page embeds its structure in JavaScript that the site's own timer
reads:

- `var intervals = [[start, duration, 'zone', ...], ...]` — the labelled blocks
- `dataWarmup.push({x: sec, y: pctFTP}, ...)` — the opening segment
- `dataFull.push({x: sec, y: pctFTP}, ...)` — everything after it

Two details are easy to get wrong and both are guarded by tests:

1. **Both curve arrays are needed.** `dataFull` starts where `dataWarmup` ends; reading
   only `dataFull` silently drops the first few minutes of target power.
2. **Their order must be preserved.** The curve is a path, not a set of samples — a step
   up is `(t,low) → (t,high) → (t+d,high) → (t+d,low)`, so two points share a timestamp
   and their order is what distinguishes the rising edge from the falling one. Sorting
   breaks the segment collapse downstream.

Older classes also *ramp* their warm-up rather than stepping it, so target segments are
modelled as trapezoids rather than rectangles. Workout id 2 is bundled as a fixture
specifically to keep that case covered.

## Etiquette

Requests go out at the same rate a browser would make them, with a descriptive
User-Agent. The catalog is cached for a day and individual workouts forever, since a class
that already aired never changes — so a repeat ride costs the site nothing and works
offline. Please keep it that way.

Peloton is a registered trademark of Peloton Interactive, Inc. TSS and Training Stress
Score are trademarks of TrainingPeaks, LLC. This project is not affiliated with Peloton,
TrainingPeaks or Home Fitness Buddy.
