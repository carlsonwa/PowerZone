"""Write a self-contained Leaflet map of the heat, official trails and candidates."""

import json
from pathlib import Path

from .analyze import TRAIL_HIGHWAYS

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MTBcharted candidates</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.css">
<style>
  html, body, #map { height: 100%; margin: 0; }
  body { font: 14px/1.4 system-ui, -apple-system, sans-serif; }
  .legend { background: #fff; padding: 8px 10px; border-radius: 6px; box-shadow: 0 1px 4px #0004; }
  .legend i { display: inline-block; width: 18px; height: 4px; margin-right: 6px; vertical-align: middle; }
  .legend .note { max-width: 220px; margin-top: 6px; color: #555; font-size: 12px; }
  .warn { color: #b00020; font-weight: 600; }
</style>
</head>
<body>
<div id="map"></div>
<script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet.heat/0.2.0/leaflet-heat.js"></script>
<script>
const DATA = __DATA__;
const COLORS = { unmapped: "#e6007e", osm_path: "#ff8c00", osm_informal: "#7b2ff7" };
const LABELS = { unmapped: "Not mapped anywhere", osm_path: "On OSM, status unknown", osm_informal: "On OSM as informal" };

const map = L.map("map");
const [w, s, e, n] = DATA.bbox;
map.fitBounds([[s, w], [n, e]]);

const base = L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19,
  attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors (ODbL); trails: USDA Forest Service',
}).addTo(map);

const maxHeat = Math.max(1, ...DATA.heat.map(h => h[2]));
const heat = L.heatLayer(DATA.heat, { radius: 6, blur: 6, max: Math.min(maxHeat, 10), minOpacity: 0.3 }).addTo(map);

const official = L.geoJSON(DATA.official, {
  style: { color: "#1b7f3b", weight: 3, opacity: 0.8 },
  onEachFeature: (f, l) => l.bindPopup(`<b>${f.properties.trail_name || "Official trail"}</b><br>USFS ${f.properties.trail_no || ""}<br>Bicycles managed: ${f.properties.bicycle_managed || "—"}`),
}).addTo(map);

const osmTrails = L.geoJSON(DATA.osm_trails, {
  style: f => ({ color: "#555", weight: 1.5, dashArray: "4 4", opacity: 0.7 }),
  onEachFeature: (f, l) => l.bindPopup(`<b>${f.properties.name || "OSM " + f.properties.highway}</b><br>${f.properties.osm_id}<br>access=${f.properties.access || "—"}, bicycle=${f.properties.bicycle || "—"}, informal=${f.properties.informal || "—"}`),
});

const protectedAreas = L.geoJSON(DATA.protected, {
  style: { color: "#b00020", weight: 1, fillOpacity: 0.06 },
  onEachFeature: (f, l) => l.bindPopup(`<b>${f.properties.name || "Protected area"}</b><br>bicycle=${f.properties.bicycle || "—"}, access=${f.properties.access || "—"}`),
});

const candidates = L.geoJSON(DATA.candidates, {
  style: f => ({ color: COLORS[f.properties.label], weight: 5, opacity: 0.9,
                 dashArray: f.properties.flags.length ? "8 6" : null }),
  onEachFeature: (f, l) => {
    const p = f.properties;
    const flags = p.flags.length ? `<div class="warn">⚠ ${p.flags.join("<br>⚠ ")}</div>` : "";
    l.bindPopup(`<b>Candidate #${p.id}</b> — ${LABELS[p.label]}<br>${p.length_m} m, ~${p.mean_traces} traces` +
      (p.osm_names.length ? `<br>OSM: ${p.osm_names.join(", ")}` : "") +
      (p.within.length ? `<br>Land: ${p.within.join(", ")}` : "") + flags +
      `<div class="note">Unverified. Check land manager rules before riding.</div>`);
  },
}).addTo(map);

L.control.layers(null, {
  "GPS heat (OSM traces)": heat,
  "Official trails (USFS)": official,
  "OSM paths": osmTrails,
  "Protected areas": protectedAreas,
  "Candidates": candidates,
}, { collapsed: false }).addTo(map);

const legend = L.control({ position: "bottomleft" });
legend.onAdd = () => {
  const d = L.DomUtil.create("div", "legend");
  d.innerHTML = `<b>MTBcharted</b> · ${DATA.candidates.features.length} candidates<br>` +
    Object.entries(LABELS).map(([k, v]) => `<i style="background:${COLORS[k]}"></i>${v}`).join("<br>") +
    `<br><i style="background:#1b7f3b"></i>Official trail` +
    `<div class="note">Dashed candidates cross closed ways or protected areas. Candidates are unverified — respect closures and private land.</div>`;
  return d;
};
legend.addTo(map);
</script>
</body>
</html>
"""


def write_map(path, bbox, inputs, result):
    osm_trails = {
        "type": "FeatureCollection",
        "features": [f for f in inputs["osm_ways"]["features"] if f["properties"].get("highway") in TRAIL_HIGHWAYS],
    }
    data = {
        "bbox": list(bbox),
        "heat": result["heat"],
        "official": inputs["official"],
        "osm_trails": osm_trails,
        "protected": inputs["protected"],
        "candidates": result["candidates"],
    }
    path = Path(path)
    path.write_text(TEMPLATE.replace("__DATA__", json.dumps(data).replace("</", "<\\/")))
    return path
