"""Download the three inputs for one area and cache them as GeoJSON.

- GPS traces: OpenStreetMap public GPS trackpoints API (ODbL).
- Official trails: USFS National Forest System trails layer (public domain).
- Mapped ways and protected areas: OpenStreetMap via Overpass (ODbL).

Everything is written to mtbcharted/data/<area>/ and reused on later runs
unless --refresh is given.
"""

import json
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path


USER_AGENT = "MTBcharted/0.1 (trail discovery prototype; https://github.com/carlsonwa/PowerZone)"
OSM_API = "https://api.openstreetmap.org/api/0.6/trackpoints"
# Public Overpass instances, tried in order.
OVERPASS_APIS = [
    "https://overpass-api.de/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
USFS_TRAILS = (
    "https://apps.fs.usda.gov/arcx/rest/services/EDW/"
    "EDW_TrailNFSPublish_01/MapServer/0/query"
)

# The trackpoints API rejects boxes larger than 0.25 square degrees and
# returns 5,000 points per page.
MAX_TRACKPOINT_AREA = 0.25
TRACKPOINTS_PER_PAGE = 5000

USFS_FIELDS = [
    "trail_name", "trail_no", "trail_type", "trail_class", "managing_org",
    "bicycle_managed", "bicycle_accpt", "bicycle_restricted",
]

GPX_NS = {"g": "http://www.topografix.com/GPX/1/0"}

DATA_ROOT = Path(__file__).parent / "data"


def _request(url, params=None, data=None, timeout=60, retries=5):
    """GET (or POST form data) and return the body, backing off on rate limits."""
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    body = urllib.parse.urlencode(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers={"User-Agent": USER_AGENT})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            if e.code not in (429, 502, 503, 504) or attempt == retries - 1:
                raise
            wait, why = int(e.headers.get("Retry-After") or 0) or 2 ** (attempt + 1), e.code
        except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
            if attempt == retries - 1:
                raise
            wait, why = 2 ** (attempt + 1), e
        print(f"  {why} from {urllib.parse.urlsplit(url).hostname}, retrying in {wait}s")
        time.sleep(wait)


def _feature_collection(features):
    return {"type": "FeatureCollection", "features": features}


def parse_trackpoints_gpx(text, page, first_id=0):
    """Turn one page of trackpoints GPX into LineString features.

    Each <trkseg> becomes one feature. Segments from identifiable traces carry
    timestamps; private ones don't, and their points are not in ride order.
    """
    root = ET.fromstring(text)
    features = []
    seg_id = first_id
    for trk in root.findall("g:trk", GPX_NS):
        url = trk.findtext("g:url", default=None, namespaces=GPX_NS)
        for seg in trk.findall("g:trkseg", GPX_NS):
            coords, times = [], []
            for pt in seg.findall("g:trkpt", GPX_NS):
                coords.append([float(pt.get("lon")), float(pt.get("lat"))])
                t = pt.findtext("g:time", default=None, namespaces=GPX_NS)
                times.append(
                    datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp() if t else None
                )
            if not coords:
                continue
            timed = all(t is not None for t in times)
            features.append({
                "type": "Feature",
                "geometry": {"type": "LineString", "coordinates": coords},
                "properties": {
                    "trace": seg_id,
                    "source_url": url,
                    "page": page,
                    "timed": timed,
                    "times": times if timed else None,
                },
            })
            seg_id += 1
    return features


def fetch_traces(bbox, max_pages=20):
    west, south, east, north = bbox
    if (east - west) * (north - south) > MAX_TRACKPOINT_AREA:
        raise ValueError(
            f"bbox is {(east - west) * (north - south):.3f} sq deg; the OSM "
            f"trackpoints API allows at most {MAX_TRACKPOINT_AREA}"
        )
    features = []
    for page in range(max_pages):
        text = _request(
            OSM_API,
            params={"bbox": f"{west},{south},{east},{north}", "page": page},
            timeout=60,
        )
        page_features = parse_trackpoints_gpx(text, page, first_id=len(features))
        features.extend(page_features)
        n_points = sum(len(f["geometry"]["coordinates"]) for f in page_features)
        print(f"  traces page {page}: {n_points} points")
        if n_points < TRACKPOINTS_PER_PAGE:
            break
        time.sleep(1)  # be polite to the OSM API
    return _feature_collection(features)


def fetch_usfs_trails(bbox):
    west, south, east, north = bbox
    features = []
    offset = 0
    while True:
        data = json.loads(_request(
            USFS_TRAILS,
            params={
                "geometry": f"{west},{south},{east},{north}",
                "geometryType": "esriGeometryEnvelope",
                "inSR": 4326,
                "spatialRel": "esriSpatialRelIntersects",
                "outFields": ",".join(USFS_FIELDS),
                "outSR": 4326,
                "resultOffset": offset,
                "resultRecordCount": 1000,
                "f": "geojson",
            },
            timeout=120,
        ))
        if "error" in data:
            raise RuntimeError(f"USFS query failed: {data['error']}")
        batch = data.get("features", [])
        for f in batch:
            f["properties"]["source"] = "usfs"
        features.extend(batch)
        if not data.get("exceededTransferLimit") and not data.get("properties", {}).get("exceededTransferLimit"):
            break
        offset += len(batch)
        if not batch:
            break
    return _feature_collection(features)


OVERPASS_QUERY = """
[out:json][timeout:120];
(
  way["highway"]({s},{w},{n},{e});
  way["boundary"="protected_area"]({s},{w},{n},{e});
  way["leisure"="nature_reserve"]({s},{w},{n},{e});
  relation["boundary"="protected_area"]({s},{w},{n},{e});
  relation["leisure"="nature_reserve"]({s},{w},{n},{e});
);
out geom;
"""


def _overpass_ring_polygons(element):
    """Build polygons from an Overpass way or multipolygon relation."""
    from shapely.geometry import LineString, mapping
    from shapely.ops import polygonize, unary_union

    if element["type"] == "way":
        lines = [element.get("geometry", [])]
    else:
        lines = [
            m.get("geometry", []) for m in element.get("members", [])
            if m.get("type") == "way" and m.get("role") in ("outer", "")
        ]
    segs = [
        LineString([(p["lon"], p["lat"]) for p in g]) for g in lines if len(g) >= 2
    ]
    if not segs:
        return None
    polys = list(polygonize(unary_union(segs)))
    if not polys:
        return None
    return mapping(unary_union(polys))


def fetch_osm(bbox):
    """Return (ways, protected) FeatureCollections from Overpass."""
    west, south, east, north = bbox
    q = OVERPASS_QUERY.format(w=west, s=south, e=east, n=north)
    for i, api in enumerate(OVERPASS_APIS):
        try:
            elements = json.loads(_request(api, data={"data": q}, timeout=180, retries=2))["elements"]
            break
        except (urllib.error.URLError, ConnectionError, TimeoutError, KeyError) as e:
            if i == len(OVERPASS_APIS) - 1:
                raise
            print(f"  {urllib.parse.urlsplit(api).hostname} failed ({e}); trying the next Overpass server")
    ways, protected = [], []
    for el in elements:
        tags = el.get("tags", {})
        if tags.get("boundary") == "protected_area" or tags.get("leisure") == "nature_reserve":
            geom = _overpass_ring_polygons(el)
            if geom:
                protected.append({
                    "type": "Feature",
                    "geometry": geom,
                    "properties": {
                        "osm_id": f"{el['type']}/{el['id']}",
                        "name": tags.get("name"),
                        "protect_class": tags.get("protect_class"),
                        "access": tags.get("access"),
                        "bicycle": tags.get("bicycle"),
                    },
                })
        elif el["type"] == "way" and "highway" in tags and len(el.get("geometry", [])) >= 2:
            ways.append({
                "type": "Feature",
                "geometry": {
                    "type": "LineString",
                    "coordinates": [[p["lon"], p["lat"]] for p in el["geometry"]],
                },
                "properties": {
                    "osm_id": f"way/{el['id']}",
                    **{k: tags.get(k) for k in (
                        "highway", "name", "access", "bicycle", "mtb:scale",
                        "informal", "operator", "surface",
                    )},
                },
            })
    return _feature_collection(ways), _feature_collection(protected)


def load_or_fetch(area, bbox, refresh=False, max_trace_pages=20):
    """Fetch every input for an area, reusing cached files when present."""
    out = DATA_ROOT / area
    out.mkdir(parents=True, exist_ok=True)
    paths = {name: out / f"{name}.geojson" for name in ("traces", "official", "osm_ways", "protected")}

    def cached(name):
        return not refresh and paths[name].exists()

    if not cached("traces"):
        print("Fetching OSM GPS traces...")
        _write(paths["traces"], fetch_traces(bbox, max_trace_pages))
    if not cached("official"):
        print("Fetching USFS official trails...")
        _write(paths["official"], fetch_usfs_trails(bbox))
    if not (cached("osm_ways") and cached("protected")):
        print("Fetching OSM ways and protected areas from Overpass...")
        ways, protected = fetch_osm(bbox)
        _write(paths["osm_ways"], ways)
        _write(paths["protected"], protected)

    return {name: json.loads(p.read_text()) for name, p in paths.items()}


def _write(path, fc):
    path.write_text(json.dumps(fc))
    print(f"  wrote {len(fc['features'])} features to {path}")
