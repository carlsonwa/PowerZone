#!/usr/bin/env python3
"""Reference implementation of the two homefitnessbuddy parsers.

The Swift parsers in PowerZoneRide.swiftpm/Data/ use the same regexes. There is no
Swift toolchain on a plain iPad, so this script is where the extraction logic gets
proven against real pages before it is ported. Run it whenever the site might have
changed:

    python3 tools/verify_parsers.py            # sample of workout ids
    python3 tools/verify_parsers.py --save     # also refresh Swift test fixtures

The load-bearing assertion is the invariant that the last interval's end equals the
class length. A parse that drifts silently would still produce a plausible-looking
graph, so we check structure rather than eyeballing output.
"""

import argparse
import os
import re
import sys
import time
import urllib.request

BASE = "https://app.homefitnessbuddy.com/peloton/powerzone"
UA = "PowerZoneRide/1.0 (personal use; contact via github.com/carlsonwa)"

FIXTURE_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "PowerZoneRide.swiftpm", "Data", "Fixtures",
)

# Workout ids chosen to span every class length and type code seen in the catalog.
SAMPLE_IDS = [2, 233, 272, 332, 375, 425, 511, 640, 720, 851,
              864, 903, 1002, 1120, 1240, 1357, 1450, 1557, 1595, 1599]

# Ids saved as Swift test fixtures: shortest, longest, most intervals, odd zone codes,
# and — id 2 — an older class whose warm-up ramps instead of stepping.
FIXTURE_IDS = [2, 375, 864, 851, 1595]

INTERVALS_RE = re.compile(r"var intervals\s*=\s*\[(.*?)\n\s*\];", re.S)
INTERVAL_ROW_RE = re.compile(r"\[\s*(\d+)\s*,\s*(\d+)\s*,\s*'([^']*)'")
DATAFULL_RE = re.compile(r"dataFull\.push\((.*?)\);", re.S)
DATAWARMUP_RE = re.compile(r"dataWarmup\.push\((.*?)\);", re.S)
POINT_RE = re.compile(r"\{\s*x:\s*(\d+)\s*,\s*y:\s*(\d+)")
CLASSLENGTH_RE = re.compile(r"classLength\s*=\s*(\d+)\s*\*\s*1000")
ROW_RE = re.compile(r"<TR>(.*?)</TR>", re.S)
CELL_RE = re.compile(r"<TD>(.*?)</TD>", re.S)


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def _points(html, call_re):
    pts = []
    for call in call_re.findall(html):
        pts += [(int(x), int(y)) for x, y in POINT_RE.findall(call)]
    return pts


def parse_workout(html):
    """-> (intervals, curve, class_length). Mirrors WorkoutParser.swift.

    The target curve is split across two JS arrays: dataWarmup holds the opening
    segment and dataFull picks up from where it ends. Using dataFull alone silently
    drops the first few minutes of target power, so both are concatenated.

    Emission order is load-bearing and must not be sorted. The curve is a path, not a
    set of samples: a step up is drawn as (t,low) -> (t,high) -> (t+d,high) -> (t+d,low),
    so two points can share a timestamp and their order is what distinguishes the rising
    edge from the falling one. Sorting by (time, percent) reorders those pairs and the
    block collapse downstream then reads the wrong runs as flat.
    """
    m = INTERVALS_RE.search(html)
    intervals = []
    if m:
        for start, dur, zone in INTERVAL_ROW_RE.findall(m.group(1)):
            intervals.append((int(start), int(dur), zone))

    raw = _points(html, DATAWARMUP_RE) + _points(html, DATAFULL_RE)
    curve = [p for i, p in enumerate(raw) if i == 0 or p != raw[i - 1]]

    cl = CLASSLENGTH_RE.search(html)
    return intervals, curve, int(cl.group(1)) if cl else None


def target_segments(curve):
    """Split the polyline into trapezoids. Mirrors Workout.targetSegments in Swift.

    Every consecutive pair that advances in time is one segment. Most are flat runs
    (same percent at both ends), but older classes ramp the warm-up — 45% climbing to
    90% and back down over 13 minutes — and a flat-rectangle model silently drops those,
    leaving a quarter of the class with no target drawn. Pairs that share a timestamp are
    the vertical connectors between blocks and carry no duration.
    """
    return [(a[0], b[0], a[1], b[1])
            for a, b in zip(curve, curve[1:]) if b[0] > a[0]]


def parse_catalog(html):
    """-> list of dicts. Mirrors CatalogParser.swift."""
    out = []
    for row in ROW_RE.findall(html):
        c = CELL_RE.findall(row)
        if len(c) < 21 or not c[20].strip().isdigit():
            continue
        out.append({
            "id": int(c[20]), "title": c[1], "date": c[11], "instructor": c[4],
            "minutes": c[6], "tss": c[7], "type_name": c[8], "type_code": c[9],
            "zones": c[10],
        })
    return out


def check_workout(cid, save=False):
    html = fetch(f"{BASE}/details/{cid}")
    intervals, curve, class_len = parse_workout(html)

    problems = []
    if not intervals:
        problems.append("no intervals")
    if not curve:
        problems.append("no curve points")
    if class_len is None:
        problems.append("no classLength")

    end = intervals[-1][0] + intervals[-1][1] if intervals else 0
    if class_len is not None and intervals and end != class_len:
        problems.append(f"end {end} != classLength {class_len}")

    # Intervals must tile the timeline with no gaps or overlaps.
    for i in range(1, len(intervals)):
        if intervals[i][0] != intervals[i - 1][0] + intervals[i - 1][1]:
            problems.append(f"gap before interval {i}")
            break

    if curve and not all(0 < y < 250 for _, y in curve):
        problems.append("curve %FTP outside 0-250")

    # The merged curve must span the whole class; a gap means a stretch of the ride
    # would render with no target block at all.
    if curve and class_len is not None:
        if curve[0][0] != 0:
            problems.append(f"curve starts at {curve[0][0]}, not 0")
        if curve[-1][0] != class_len:
            problems.append(f"curve ends at {curve[-1][0]}, not {class_len}")

        # The segments are what the chart actually draws, so check they tile the class
        # exactly rather than trusting the endpoints. This is the assertion that catches
        # both a reordered curve and a dropped ramp.
        segs = target_segments(curve)
        covered = sum(e - s for s, e, _, _ in segs)
        if covered != class_len:
            problems.append(f"target segments cover {covered}/{class_len}s, not all of it")
        for i in range(len(segs) - 1):
            if segs[i][1] != segs[i + 1][0]:
                problems.append(f"target segments break at {segs[i][1]}s")
                break

    if save and cid in FIXTURE_IDS:
        os.makedirs(FIXTURE_DIR, exist_ok=True)
        with open(os.path.join(FIXTURE_DIR, f"workout_{cid}.html"), "w") as f:
            f.write(html)

    zones = ",".join(sorted({z for _, _, z in intervals}))
    ramps = sum(1 for _, _, y1, y2 in target_segments(curve) if y1 != y2)
    status = "FAIL" if problems else "ok"
    print(f"  {status:4} id={cid:<5} intervals={len(intervals):<3} curve={len(curve):<4} "
          f"len={class_len or '?':<5} ramps={ramps:<2} zones={zones}")
    for p in problems:
        print(f"         ! {p}")
    return not problems


def check_catalog(save=False):
    html = fetch(f"{BASE}/")
    entries = parse_catalog(html)
    print(f"\nCatalog: {len(entries)} workouts parsed ({len(html)//1024} KB)")
    if not entries:
        print("  FAIL no rows parsed")
        return False
    ids = [e["id"] for e in entries]
    if len(set(ids)) != len(ids):
        print("  FAIL duplicate ids")
        return False
    e = entries[0]
    print(f"  newest: id={e['id']} {e['minutes']}min {e['instructor']} "
          f"{e['type_code']} zones={e['zones']}")
    print(f"  id range: {min(ids)}-{max(ids)}")
    if save:
        os.makedirs(FIXTURE_DIR, exist_ok=True)
        # Only the first rows: the full page is 545 KB and would bloat the repo.
        head = html[:html.find("</TR>", html.find("<TR>") ) ]
        rows = ROW_RE.findall(html)[:50]
        with open(os.path.join(FIXTURE_DIR, "catalog_sample.html"), "w") as f:
            f.write("".join(f"<TR>{r}</TR>" for r in rows))
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--save", action="store_true", help="refresh Swift fixtures")
    ap.add_argument("--ids", type=int, nargs="*", help="override sample ids")
    args = ap.parse_args()

    ids = args.ids or SAMPLE_IDS
    print(f"Checking {len(ids)} workouts against {BASE}/details/")
    passed = 0
    for cid in ids:
        try:
            if check_workout(cid, args.save):
                passed += 1
        except Exception as exc:
            print(f"  FAIL id={cid} {type(exc).__name__}: {exc}")
        time.sleep(0.5)  # be a polite guest on someone else's free tool

    cat_ok = check_catalog(args.save)
    print(f"\nWorkouts: {passed}/{len(ids)} passed. Catalog: {'ok' if cat_ok else 'FAIL'}")
    return 0 if passed == len(ids) and cat_ok else 1


if __name__ == "__main__":
    sys.exit(main())
