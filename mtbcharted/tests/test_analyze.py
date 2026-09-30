import numpy as np

from mtbcharted.analyze import Params, analyze, trace_samples
from mtbcharted.fetch import parse_trackpoints_gpx

BBOX = (-120.850, 39.550, -120.840, 39.560)
LAT_OFFICIAL = 39.5550
LAT_OFF = 39.5560  # ~110 m north of the official trail


def fc(features):
    return {"type": "FeatureCollection", "features": features}


def line(coords, **props):
    return {"type": "Feature", "geometry": {"type": "LineString", "coordinates": coords}, "properties": props}


def ride(lat, trace_id, speed_ms=3.0, lon0=-120.848, lon1=-120.842, n=60):
    """A timed trace riding east along a line of latitude."""
    lons = np.linspace(lon0, lon1, n)
    step_m = (lon1 - lon0) * 111_320 * np.cos(np.radians(lat)) / (n - 1)
    times = [1_700_000_000 + i * step_m / speed_ms for i in range(n)]
    return line([[lo, lat] for lo in lons], trace=trace_id, timed=True, times=times)


def inputs(traces, official=None, osm_ways=None, protected=None):
    return {
        "traces": fc(traces),
        "official": fc(official or [line([[-120.849, LAT_OFFICIAL], [-120.841, LAT_OFFICIAL]], source="usfs")]),
        "osm_ways": fc(osm_ways or []),
        "protected": fc(protected or []),
    }


def test_offset_trace_is_one_unmapped_candidate():
    result = analyze(inputs([ride(LAT_OFF, i) for i in range(3)]), BBOX)
    feats = result["candidates"]["features"]
    assert len(feats) == 1
    props = feats[0]["properties"]
    assert props["label"] == "unmapped"
    assert 400 < props["length_m"] < 560  # ride is ~515 m long
    assert props["flags"] == []


def test_trace_on_official_trail_gives_nothing():
    result = analyze(inputs([ride(LAT_OFFICIAL, i) for i in range(3)]), BBOX)
    assert result["candidates"]["features"] == []


def test_single_trace_is_below_threshold():
    result = analyze(inputs([ride(LAT_OFF, 0)]), BBOX)
    assert result["candidates"]["features"] == []


def test_driving_speed_is_ignored():
    result = analyze(inputs([ride(LAT_OFF, i, speed_ms=25) for i in range(3)]), BBOX)
    assert result["candidates"]["features"] == []


def test_heat_on_a_road_is_excluded():
    road = line([[-120.849, LAT_OFF], [-120.841, LAT_OFF]], highway="unclassified", osm_id="way/1")
    result = analyze(inputs([ride(LAT_OFF, i) for i in range(3)], osm_ways=[road]), BBOX)
    assert result["candidates"]["features"] == []


def test_labels_and_flags_from_osm():
    informal = line([[-120.849, LAT_OFF], [-120.841, LAT_OFF]], highway="path", informal="yes",
                    name="Secret Squirrel", bicycle="no", osm_id="way/2")
    park = {
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [[
            [-120.846, 39.555], [-120.844, 39.555], [-120.844, 39.557], [-120.846, 39.557], [-120.846, 39.555],
        ]]},
        "properties": {"osm_id": "relation/3", "name": "Test Reserve", "bicycle": "no"},
    }
    result = analyze(inputs([ride(LAT_OFF, i) for i in range(3)], osm_ways=[informal], protected=[park]), BBOX)
    (feat,) = result["candidates"]["features"]
    props = feat["properties"]
    assert props["label"] == "osm_informal"
    assert props["osm_names"] == ["Secret Squirrel"]
    assert any(f.startswith("closed_way:way/2") for f in props["flags"])
    assert "protected_area:Test Reserve (bikes/access prohibited)" in props["flags"]


def test_untimed_points_are_not_joined():
    xs, ys = trace_samples([0, 50], [0, 0], None, Params())
    assert list(xs) == [0, 50]


def test_parse_gpx_segments():
    gpx = """<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.0" creator="OpenStreetMap.org" xmlns="http://www.topografix.com/GPX/1/0">
  <trk><name>a.gpx</name><url>/user/x/traces/1</url>
    <trkseg>
      <trkpt lat="39.1" lon="-120.1"><time>2022-10-12T19:22:25Z</time></trkpt>
      <trkpt lat="39.2" lon="-120.2"><time>2022-10-12T19:22:31Z</time></trkpt>
    </trkseg>
  </trk>
  <trk><trkseg><trkpt lat="39.3" lon="-120.3"/></trkseg></trk>
</gpx>"""
    feats = parse_trackpoints_gpx(gpx, page=0)
    assert [f["properties"]["trace"] for f in feats] == [0, 1]
    assert feats[0]["properties"]["timed"] and feats[0]["properties"]["times"][1] - feats[0]["properties"]["times"][0] == 6
    assert not feats[1]["properties"]["timed"]
    assert feats[1]["geometry"]["coordinates"] == [[-120.3, 39.3]]


def test_osm_designated_bike_trail_counts_as_official():
    designated = line([[-120.849, LAT_OFF], [-120.841, LAT_OFF]], highway="path", bicycle="designated", osm_id="way/4")
    result = analyze(inputs([ride(LAT_OFF, i) for i in range(3)], osm_ways=[designated]), BBOX)
    assert result["candidates"]["features"] == []


def test_multi_use_land_is_context_not_a_warning():
    forest = {
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [[
            [-120.85, 39.55], [-120.84, 39.55], [-120.84, 39.56], [-120.85, 39.56], [-120.85, 39.55],
        ]]},
        "properties": {"osm_id": "relation/5", "name": "Test National Forest", "protect_class": "6"},
    }
    result = analyze(inputs([ride(LAT_OFF, i) for i in range(3)], protected=[forest]), BBOX)
    (feat,) = result["candidates"]["features"]
    assert feat["properties"]["flags"] == []
    assert feat["properties"]["within"] == ["Test National Forest"]
