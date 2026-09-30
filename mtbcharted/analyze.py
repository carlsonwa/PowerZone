"""Find ridden lines that aren't on the official trail network.

Pipeline:
1. Rasterize GPS traces into a grid, counting how many distinct traces touch
   each cell. Driving-speed segments are dropped.
2. Mask out cells near official trails (USFS, plus OSM ways tagged with an
   operator) and near roads, which carry lots of car traces.
3. Skeletonize what's left into centre lines and keep the long ones.
4. Label each line by what OSM already knows about it, and flag any that
   cross closed ways or protected areas.

Run:  python -m mtbcharted.analyze --area downieville --bbox -120.87,39.54,-120.79,39.60
"""

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import shapely
from pyproj import Transformer
from scipy.ndimage import binary_dilation, maximum_filter
from shapely.geometry import LineString, MultiLineString, mapping, shape
from shapely.ops import linemerge, transform, unary_union
from skimage.morphology import disk, skeletonize

# OSM highway values that are trails rather than roads. Heat on anything else
# is most likely someone driving.
TRAIL_HIGHWAYS = {"path", "footway", "bridleway", "cycleway"}
CLOSED_VALUES = {"no", "private"}
# IUCN classes for strict reserves and wilderness, where bikes are generally banned
# (US federal wilderness always bans them). Class 6 (e.g. national forests) is
# ordinary multi-use land, so it's reported as context rather than a warning.
STRICT_PROTECT_CLASSES = {"1a", "1b"}


@dataclass
class Params:
    cell_m: float = 10.0          # grid resolution
    min_traces: int = 2           # distinct traces a cell needs to count as ridden
    min_hits: int = 3             # GPS points (after densifying) a cell needs
    max_gap_m: float = 60.0       # don't join consecutive fixes further apart than this
    max_speed_ms: float = 11.0    # ~40 km/h; faster segments are treated as driving
    official_buffer_m: float = 25.0  # USFS geometry is often tens of metres off the tread
    min_length_m: float = 100.0
    on_osm_fraction: float = 0.5  # share of a line within a mapped way to call it "on OSM"


def utm_transformers(bbox):
    west, south, east, north = bbox
    lon, lat = (west + east) / 2, (south + north) / 2
    zone = int((lon + 180) // 6) + 1
    epsg = (32600 if lat >= 0 else 32700) + zone
    fwd = Transformer.from_crs(4326, epsg, always_xy=True)
    inv = Transformer.from_crs(epsg, 4326, always_xy=True)
    return fwd, inv


class Grid:
    def __init__(self, bbox, fwd, cell):
        west, south, east, north = bbox
        xs, ys = fwd.transform([west, east, west, east], [south, south, north, north])
        self.x0, self.y0 = min(xs), min(ys)
        self.cell = cell
        self.nx = int(math.ceil((max(xs) - self.x0) / cell))
        self.ny = int(math.ceil((max(ys) - self.y0) / cell))

    def index(self, x, y):
        ix = np.floor((np.asarray(x) - self.x0) / self.cell).astype(int)
        iy = np.floor((np.asarray(y) - self.y0) / self.cell).astype(int)
        ok = (ix >= 0) & (ix < self.nx) & (iy >= 0) & (iy < self.ny)
        return ix[ok], iy[ok]

    def centres(self, ix, iy):
        return self.x0 + (ix + 0.5) * self.cell, self.y0 + (iy + 0.5) * self.cell


def trace_samples(xs, ys, times, p):
    """Points to rasterize for one trace, densified along plausible riding segments."""
    xs, ys = np.asarray(xs, float), np.asarray(ys, float)
    if times is None or len(xs) < 2:
        # Untimed (private) points aren't in ride order, so they can't be joined.
        return xs, ys

    t = np.asarray(times, float)
    dx, dy, dt = np.diff(xs), np.diff(ys), np.diff(t)
    dist = np.hypot(dx, dy)
    with np.errstate(divide="ignore", invalid="ignore"):
        speed = np.where(dt > 0, dist / dt, np.inf)
    rideable = speed <= p.max_speed_ms

    # Keep a fix if either segment touching it is at riding speed.
    keep = np.zeros(len(xs), bool)
    keep[:-1] |= rideable
    keep[1:] |= rideable
    out_x, out_y = [xs[keep]], [ys[keep]]

    step = p.cell_m / 2
    for i in np.nonzero(rideable & (dist <= p.max_gap_m) & (dist > step))[0]:
        n = int(dist[i] // step)
        f = np.arange(1, n + 1) / (n + 1)
        out_x.append(xs[i] + dx[i] * f)
        out_y.append(ys[i] + dy[i] * f)
    return np.concatenate(out_x), np.concatenate(out_y)


def rasterize_traces(traces_fc, grid, fwd, p):
    hits = np.zeros((grid.ny, grid.nx), np.int32)
    n_traces = np.zeros((grid.ny, grid.nx), np.int32)
    for f in traces_fc["features"]:
        coords = f["geometry"]["coordinates"]
        lon, lat = zip(*coords)
        x, y = fwd.transform(lon, lat)
        sx, sy = trace_samples(x, y, f["properties"].get("times"), p)
        ix, iy = grid.index(sx, sy)
        if len(ix) == 0:
            continue
        np.add.at(hits, (iy, ix), 1)
        flat = np.unique(iy * grid.nx + ix)
        n_traces.flat[flat] += 1
    return hits, n_traces


def _project(fc, fwd, where=lambda props: True):
    geoms, props = [], []
    for f in fc["features"]:
        if f.get("geometry") and where(f["properties"]):
            geoms.append(transform(fwd.transform, shape(f["geometry"])))
            props.append(f["properties"])
    return geoms, props


def _is_trail(props):
    return props.get("highway") in TRAIL_HIGHWAYS


def _is_osm_official(props):
    return _is_trail(props) and bool(
        props.get("operator") or props.get("informal") == "no" or props.get("bicycle") == "designated"
    )


def _is_closed(props):
    return props.get("access") in CLOSED_VALUES or props.get("bicycle") in {"no", "dismount"}


def skeleton_lines(mask):
    """Vectorize a skeletonized boolean mask into merged pixel-centre lines (grid units)."""
    skel = skeletonize(mask)
    iy, ix = np.nonzero(skel)
    on = set(zip(ix.tolist(), iy.tolist()))
    segs = []
    for x, y in on:
        right, up = (x + 1, y) in on, (x, y + 1) in on
        if right:
            segs.append(((x, y), (x + 1, y)))
        if up:
            segs.append(((x, y), (x, y + 1)))
        # Diagonals only where there's no orthogonal path, to avoid little triangles.
        if (x + 1, y + 1) in on and not right and not up:
            segs.append(((x, y), (x + 1, y + 1)))
        if (x + 1, y - 1) in on and not right and (x, y - 1) not in on:
            segs.append(((x, y), (x + 1, y - 1)))
    if not segs:
        return []
    merged = linemerge(MultiLineString(segs))
    return list(merged.geoms) if hasattr(merged, "geoms") else [merged]


def analyze(inputs, bbox, p=None):
    p = p or Params()
    fwd, inv = utm_transformers(bbox)
    grid = Grid(bbox, fwd, p.cell_m)

    hits, n_traces = rasterize_traces(inputs["traces"], grid, fwd, p)
    ridden = (n_traces >= p.min_traces) & (hits >= p.min_hits)

    official, _ = _project(inputs["official"], fwd)
    osm_official, _ = _project(inputs["osm_ways"], fwd, _is_osm_official)
    roads, _ = _project(inputs["osm_ways"], fwd, lambda pr: not _is_trail(pr))
    excluded = unary_union(official + osm_official + roads).buffer(p.official_buffer_m)

    iy, ix = np.nonzero(ridden)
    cx, cy = grid.centres(ix, iy)
    near_known = shapely.contains_xy(excluded, cx, cy) if not excluded.is_empty else np.zeros(len(cx), bool)
    candidate_mask = np.zeros_like(ridden)
    candidate_mask[iy[~near_known], ix[~near_known]] = True
    candidate_mask = binary_dilation(candidate_mask, structure=disk(1))  # bridge one-cell gaps

    to_metres = lambda x, y, z=None: (grid.x0 + (np.asarray(x) + 0.5) * p.cell_m,
                                      grid.y0 + (np.asarray(y) + 0.5) * p.cell_m)
    lines = [
        transform(to_metres, g).simplify(p.cell_m / 2)
        for g in skeleton_lines(candidate_mask)
    ]
    lines = [g for g in lines if g.length >= p.min_length_m]

    osm_trails, osm_trail_props = _project(inputs["osm_ways"], fwd, lambda pr: _is_trail(pr) and not _is_osm_official(pr))
    closed, closed_props = _project(inputs["osm_ways"], fwd, _is_closed)
    protected, protected_props = _project(inputs["protected"], fwd)
    protected = [shapely.make_valid(g) for g in protected]
    trail_tree = shapely.STRtree([g.buffer(p.official_buffer_m) for g in osm_trails])
    closed_tree = shapely.STRtree([g.buffer(p.official_buffer_m / 2) for g in closed])
    protected_tree = shapely.STRtree(protected)
    trail_bufs = trail_tree.geometries
    heat_max = maximum_filter(n_traces, size=3)

    features = []
    for i, line in enumerate(sorted(lines, key=lambda g: -g.length)):
        near = trail_tree.query(line, predicate="intersects")
        informal = [j for j in near if osm_trail_props[j].get("informal") == "yes"]

        def share(idx):
            if len(idx) == 0:
                return 0.0
            return line.intersection(unary_union(trail_bufs[idx])).length / line.length

        if share(informal) >= p.on_osm_fraction:
            label = "osm_informal"
        elif share(near) >= p.on_osm_fraction:
            label = "osm_path"
        else:
            label = "unmapped"

        flags = []
        for j in closed_tree.query(line, predicate="intersects"):
            cp = closed_props[j]
            flags.append(f"closed_way:{cp['osm_id']} access={cp.get('access')} bicycle={cp.get('bicycle')}")
        within = []
        for j in protected_tree.query(line, predicate="intersects"):
            pp = protected_props[j]
            name = pp.get("name") or pp["osm_id"]
            if pp.get("bicycle") == "no" or pp.get("access") in CLOSED_VALUES:
                flags.append(f"protected_area:{name} (bikes/access prohibited)")
            elif pp.get("protect_class") in STRICT_PROTECT_CLASSES:
                flags.append(f"protected_area:{name} (class {pp['protect_class']}, likely no bikes)")
            else:
                within.append(name)

        samples = [line.interpolate(d) for d in np.arange(0, line.length, p.cell_m)]
        sx, sy = grid.index([s.x for s in samples], [s.y for s in samples])
        strength = float(heat_max[sy, sx].mean()) if len(sx) else 0.0

        features.append({
            "type": "Feature",
            "geometry": mapping(transform(inv.transform, line)),
            "properties": {
                "id": i,
                "label": label,
                "length_m": round(line.length),
                "mean_traces": round(strength, 1),
                "osm_names": sorted({osm_trail_props[j].get("name") for j in near} - {None}),
                "flags": flags,
                "within": sorted(within),
            },
        })

    # Heat cells for the map: [lat, lon, distinct traces].
    hy, hx = np.nonzero(n_traces)
    order = np.argsort(-n_traces[hy, hx])[:60000]
    hlon, hlat = inv.transform(*grid.centres(hx[order], hy[order]))
    heat = [[round(la, 6), round(lo, 6), int(c)] for la, lo, c in zip(hlat, hlon, n_traces[hy[order], hx[order]])]

    return {
        "candidates": {"type": "FeatureCollection", "features": features},
        "heat": heat,
        "stats": {
            "traces": len(inputs["traces"]["features"]),
            "ridden_cells": int(ridden.sum()),
            "ridden_cells_off_network": int((~near_known).sum()),
            "official_features": len(official) + len(osm_official),
            "candidates": len(features),
        },
    }


def summarize(result):
    s = result["stats"]
    print(
        f"{s['traces']} trace segments, {s['ridden_cells']} ridden cells, "
        f"{s['ridden_cells_off_network']} off the known network; "
        f"{s['official_features']} official trail features"
    )
    feats = result["candidates"]["features"]
    print(f"{len(feats)} candidate lines:")
    for f in feats:
        pr = f["properties"]
        names = f" ({', '.join(pr['osm_names'])})" if pr["osm_names"] else ""
        warn = "  ⚠ " + "; ".join(pr["flags"]) if pr["flags"] else ""
        within = f"  [in {', '.join(pr['within'])}]" if pr["within"] else ""
        print(f"  #{pr['id']:<3} {pr['label']:<13} {pr['length_m']:>6} m  ~{pr['mean_traces']} traces{names}{within}{warn}")


def main(argv=None):
    from . import fetch, map as mapmod

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--area", required=True, help="name for the cache folder, e.g. downieville")
    ap.add_argument("--bbox", required=True, help="west,south,east,north in degrees (max 0.25 sq deg)")
    ap.add_argument("--refresh", action="store_true", help="re-download instead of using the cache")
    ap.add_argument("--max-trace-pages", type=int, default=20)
    ap.add_argument("--min-traces", type=int, default=Params.min_traces)
    ap.add_argument("--min-length", type=float, default=Params.min_length_m)
    args = ap.parse_args(argv)

    bbox = tuple(float(v) for v in args.bbox.split(","))
    inputs = fetch.load_or_fetch(args.area, bbox, args.refresh, args.max_trace_pages)
    result = analyze(inputs, bbox, Params(min_traces=args.min_traces, min_length_m=args.min_length))
    summarize(result)

    out = fetch.DATA_ROOT / args.area
    (out / "candidates.geojson").write_text(json.dumps(result["candidates"]))
    html = mapmod.write_map(out / "map.html", bbox, inputs, result)
    print(f"Wrote {out / 'candidates.geojson'} and {html}")


if __name__ == "__main__":
    main()
