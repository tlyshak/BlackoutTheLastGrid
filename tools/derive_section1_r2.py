"""tools/derive_section1_r2.py -- derive the runtime layers of the revised section 1 concept.

The author's revised concept of the mine face room (assets/art/v2/level0_r2/level0_section1_mineface_r2.svg,
viewBox 0 0 690 450, one flat document drawn back to front) is split into the derivatives the v2
prologue draws (assets/art/v2/backgrounds/level0_section1_mineface_r2_*.svg, all in the 680x440
mockup frame the other section derivatives use):

  _back           rock ceiling, far gallery, hill band, far cables (y <= 160; opaque);
  _mid            pillar stubs, beam, wall, mine face, props on the wall (transparent above the beam);
  _floor          the drawn floor from row 280 down: plates, track, loose batteries, crates;
  _mid_fill       a repeatable wall column (wall, beam, one pillar stub, pipe, top rail, one crack)
                  composed here, not cut from the section -- the section has no prop-free bay;
  _floor_fill     the floor base plus the track (sleepers every 100 px) for the same columns;
  _alarm          the two alarm lamps, their halos and the red spill on the left wall (animated);
  _worklamp_wall  the work lamp's bulb and its glow on the wall (animated, cut at the floor row);
  _worklamp_floor the same lamp's glow on the floor (animated, above the floor layer);
  _fan_blades     the fan's blades and hub, 68x68 around the hub (rotated in game).

Godot's SVG importer (ThorVG) draws no <pattern> fills and no <text>, so every pattern of the
concept (and the two undefined `grate`/`stripes` references) is replaced by a flat fill of the
pattern's average coverage, as for the first three sections (see backgrounds/README.md); the
graffiti text is dropped from the mid layer. Inline `style="..."` attributes duplicate the
presentation attributes and are stripped. Deliberate edits of the picture: the beam is extended
from x 616 to the frame's right edge so the wall column tiled right of the section continues it,
and in the far layer the gallery rail and the two far cables are bent to the same height at
x 240 and x 680 (BACK_SEAM_EDITS) so the tile SectionBackdrop repeats has no step at its seam.

The original is never written. Selection is by top-level index, guarded by a signature table
(tag + key attribute) so a re-exported concept with a different structure fails here instead of
being cut blindly -- extend the table when the author ships a new revision.

Run from the repo root (Python 3, stdlib only):
    python tools/derive_section1_r2.py            # writes the nine derivatives
    python tools/derive_section1_r2.py --check    # verifies the existing derivatives, writes nothing
Exit 0 when every derivative was written (or, with --check, matches), 1 on any violation.
Afterwards: godot --headless --path . --import (the .import sidecars pin svg/scale=3.0).
"""
import copy
import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "art" / "v2" / "level0_r2" / "level0_section1_mineface_r2.svg"
DST_DIR = ROOT / "assets" / "art" / "v2" / "backgrounds"
STEM = "level0_section1_mineface_r2"
FRAME = (680, 440)

# Top-level children of <svg>, in document order: (tag, key attribute value). The key is the
# element's id, else its fill, else its stroke, else "" -- exactly what a structural diff needs to
# notice a moved or missing element.
SIGNATURES = [
    ("title", ""), ("desc", ""), ("defs", ""),
    ("rect", "#06080d"),          # 3  background
    ("path", "#0e121a"),          # 4  rock ceiling
    ("g", "upper-ceiling"),       # 5
    ("path", "#131826"),          # 6  hill band
    ("path", "url(#hatch)"),      # 7  hill hatch
    ("g", "far-gallery"),         # 8
    ("g", "#0e121a"),             # 9  boulders
    ("g", "none"),                # 10 far cables (stroke #2a3148)
    ("g", "#1a2030"),             # 11 pillars
    ("g", "#0a0d14"),             # 12 pillar caps
    ("rect", "#242c40"),          # 13 beam
    ("g", "#0a0d14"),             # 14 beam bolts
    ("rect", "#181d2b"),          # 15 wall
    ("g", "#20263a"),             # 16 side walls
    ("g", "url(#dots)"),          # 17 side wall dots
    ("g", "none"),                # 18 wall cracks
    ("g", "mine-face"),           # 19
    ("circle", "#0c0f18"),        # 20 fan disc
    ("circle", "none"),           # 21 fan inner ring
    ("g", "#3a4462"),             # 22 fan blades          -> _fan_blades
    ("g", "#1a2030"),             # 23 fan bolts
    ("circle", "none"),           # 24 fan ring r30
    ("g", "url(#grate)"),         # 25 fan grate
    ("g", "#1e2538"),             # 26 blade shadows       -> _fan_blades
    ("g", "#4a5678"),             # 27 blade highlights    -> _fan_blades
    ("circle", "#3a4462"),        # 28 hub                 -> _fan_blades
    ("circle", "#232a3e"),        # 29 hub inner           -> _fan_blades
    ("g", "#0a0c14"),             # 30 hub dots            -> _fan_blades
    ("path", "#0a0c14"),          # 31 fan stem
    ("g", "none"),                # 32 pipes dark
    ("g", "none"),                # 33 pipes light
    ("g", "pipe-detail"),         # 34
    ("g", "#6b4a2a"),             # 35 rust
    ("g", "none"),                # 36 wires
    ("path", "none"),             # 37 centre wire dark
    ("path", "none"),             # 38 centre wire light
    ("g", "wire-detail"),         # 39
    ("g", "none"),                # 40 red cable
    ("g", "work-lamp"),           # 41 fixture; bulb + wall glow -> _worklamp_wall
    ("g", "breaker-board"),       # 42
    ("g", "drip-barrel"),         # 43
    ("g", "pipe-valve"),          # 44
    ("g", "left-zone"),           # 45
    ("g", "right-extra"),         # 46
    ("g", "zone-dividers"),       # 47
    ("g", "top-rail"),            # 48
    ("rect", "url(#floorDepth)"), # 49 floor
    ("rect", "url(#floorgrain)"), # 50
    ("rect", "#231f1f"),          # 51 floor near the wall
    ("rect", "url(#dots)"),       # 52
    ("g", "track"),               # 53
    ("g", "floor-marks"),         # 54
    ("g", "floor-detail"),        # 55
    ("g", "pick-ground"),         # 56
    ("g", "hose-coil"),           # 57
    ("g", "puddle"),              # 58
    ("ellipse", "url(#worklamp)"),# 59 floor glow          -> _worklamp_floor
    ("g", "#5a3a2a"),             # 60 rust on the floor
    ("g", "loose-batteries"),     # 61
    ("g", "crates"),              # 62
    ("g", "#c9403a"),             # 63 alarm bulbs         -> _alarm
    ("g", "#c9403a"),             # 64 alarm halos         -> _alarm
    ("g", "#c9403a"),             # 65 alarm spill         -> _alarm
    ("rect", "#000000"),          # 66 letterbox top        (dropped)
    ("rect", "#000000"),          # 67 letterbox bottom     (dropped)
]

BACK = list(range(3, 11))
FAN = [22, 26, 27, 28, 29, 30]
MID = [i for i in range(11, 49) if i not in FAN]
FLOOR = [i for i in range(49, 63) if i != 59]
ALARM = [63, 64, 65]
WORK_LAMP_GROUP = 41
WORK_LAMP_BULB_INDEX = 6          # children of the work-lamp group: 0..5 fixture, 6 bulb, 7 wall glow
WORK_LAMP_GLOW_INDEX = 7
FLOOR_GLOW = 59
BEAM = 13
BEAM_WIDTH_ORIGINAL = "560"       # x 56..616 in the concept
BEAM_WIDTH_EXTENDED = "624"       # x 56..680: continues into the tiled wall column
GRAFFITI_ID = "graffiti"          # <text> is not drawn by ThorVG; the two lines are dropped
GRAFFITI_TEXT_COUNT = 2

# The far layer is tiled from column 240 to 680 (SectionBackdrop.BackSlice: the ceiling polyline
# is at y 96 at both), so the three strokes that cross the cut at different heights are bent to
# meet: the gallery rail (y 82→78, made level at 80) and the two far cables (their right ends
# raised to the height they have at x 240). (old `d` fragment, new `d` fragment), each exactly once.
BACK_SEAM_EDITS = [
    ("M0 82 L680 78", "M0 80 L680 80"),
    ("T480 124 T680 118", "T480 124 T680 120"),
    ("T500 134 T680 128", "T500 134 T680 132"),
]

# <pattern> fills (and the two references the concept never defines) -> flat fills of the average
# coverage. Value: (fill, fill-opacity).
FLAT_FILLS = {
    "hatch": ("#000000", "0.06"),
    "dots": ("#000000", "0.02"),
    "gravel": ("#1e1a18", "0.14"),
    "grain": ("#111726", "1"),
    "grain2": ("#0f1420", "0.12"),
    "floorgrain": ("#1f1b1b", "0.10"),
    "grate": ("#2c3550", "0.28"),
    "stripes": ("#816634", "1"),
}

# Crops of the animated pieces, in mockup px: (x, y, w, h). The fan crop is centred on the hub
# (330, 140) so the sprite's centre is its axis.
CROPS = {
    "alarm": (0, 154, 650, 126),
    "worklamp_wall": (0, 92, 300, 188),
    "worklamp_floor": (30, 296, 240, 68),
    "fan_blades": (296, 106, 68, 68),
}

URL_RE = re.compile(r"url\(#([A-Za-z0-9_-]+)\)")


def q(tag):
    return "{%s}%s" % (SVG_NS, tag)


def local(tag):
    return tag.split("}", 1)[1] if "}" in tag else tag


def key_of(el):
    a = el.attrib
    return a.get("id") or a.get("fill") or a.get("stroke") or ""


def fail(msg):
    print("derive_section1_r2: " + msg)
    sys.exit(1)


def check_signatures(root):
    kids = list(root)
    if len(kids) != len(SIGNATURES):
        fail("expected %d top-level elements, found %d" % (len(SIGNATURES), len(kids)))
    for i, (el, (tag, key)) in enumerate(zip(kids, SIGNATURES)):
        if local(el.tag) != tag or key_of(el) != key:
            fail("top-level element %d is <%s %s>, expected <%s %s>" % (i, local(el.tag), key_of(el), tag, key))
    beam = kids[BEAM]
    if beam.get("x") != "56" or beam.get("width") != BEAM_WIDTH_ORIGINAL:
        fail("beam rect is not x=56 width=%s" % BEAM_WIDTH_ORIGINAL)
    lamp = list(kids[WORK_LAMP_GROUP])
    if len(lamp) != 8 or local(lamp[WORK_LAMP_BULB_INDEX].tag) != "ellipse" or lamp[WORK_LAMP_GLOW_INDEX].get("fill") != "url(#worklamp)":
        fail("work-lamp group does not end with the bulb ellipse and the glow ellipse")


def strip_styles(el):
    for e in el.iter():
        e.attrib.pop("style", None)


def flatten_patterns(el):
    for e in el.iter():
        fill = e.get("fill", "")
        m = URL_RE.fullmatch(fill)
        if m and m.group(1) in FLAT_FILLS:
            colour, alpha = FLAT_FILLS[m.group(1)]
            e.set("fill", colour)
            if alpha != "1":
                e.set("fill-opacity", alpha)


def referenced_ids(elements):
    ids = set()
    for el in elements:
        for e in el.iter():
            for v in e.attrib.values():
                for m in URL_RE.finditer(v):
                    ids.add(m.group(1))
    return ids


def make_doc(title, viewbox, defs_src, elements):
    """A new 680x440-frame document (or a crop of it) holding deep copies of `elements`."""
    x, y, w, h = viewbox
    root = ET.Element(q("svg"), {"width": str(w), "height": str(h), "viewBox": "%d %d %d %d" % (x, y, w, h)})
    t = ET.SubElement(root, q("title"))
    t.text = title
    copies = [copy.deepcopy(e) for e in elements]
    for c in copies:
        strip_styles(c)
        flatten_patterns(c)
    needed = referenced_ids(copies)
    if needed:
        defs = ET.SubElement(root, q("defs"))
        for d in defs_src:
            if d.get("id") in needed and local(d.tag) != "pattern":
                dc = copy.deepcopy(d)
                strip_styles(dc)
                defs.append(dc)
        missing = needed - {d.get("id") for d in defs}
        if missing:
            fail("%s references undefined ids %s" % (title, sorted(missing)))
    root.extend(copies)
    return root


def el(tag, **attrs):
    e = ET.Element(q(tag), {k.replace("_", "-"): str(v) for k, v in attrs.items()})
    return e


def mid_fill_elements():
    """Wall column: plain wall, beam, one pillar stub (x 228..244, the cut of the tiles lands on its
    right edge), pipe at the height of the section's right pipe, top rail, one crack."""
    pillar = el("g", fill="#1a2030", stroke="#0a0d14", stroke_width="1.5")
    pillar.append(el("rect", x=228, y=90, width=16, height=72))
    cap = el("g", fill="#0a0d14")
    cap.append(el("rect", x=228, y=90, width=16, height=6))
    beam = el("rect", x=0, y=102, width=680, height=10, fill="#242c40", stroke="#0a0d14", stroke_width="1.5")
    bolts = el("g", fill="#0a0d14")
    bolts.append(el("circle", cx=236, cy=107, r=2))
    wall = el("rect", x=0, y=160, width=680, height=120, fill="#20263a")
    dots = el("rect", x=0, y=160, width=680, height=120, fill="#000000", fill_opacity="0.02")
    crack = el("g", fill="none", stroke="#2a3148", stroke_width="2")
    crack.append(el("path", d="M220 170 L252 220 L230 266"))
    pipe_dark = el("g", fill="none", stroke="#3a3040", stroke_width="5", stroke_linecap="round")
    pipe_dark.append(el("path", d="M0 146 L680 146"))
    pipe_light = el("g", fill="none", stroke="#5a4a3a", stroke_width="2")
    pipe_light.append(el("path", d="M0 146 L680 146"))
    pipe_shade = el("g", fill="none", stroke="#050608", stroke_width="1.5", opacity="0.6")
    pipe_shade.append(el("path", d="M0 149 L680 149"))
    pipe_gloss = el("g", fill="none", stroke="#7a5a3a", stroke_width="1", opacity="0.6")
    pipe_gloss.append(el("path", d="M0 143 L680 143"))
    bracket = el("g", fill="#4a3a2a", stroke="#0a0d14", stroke_width="1")
    bracket.append(el("rect", x=232, y=141, width=8, height=10, rx=1))
    rail = el("g")
    rail.append(el("rect", x=0, y=157, width=680, height=3, fill="#242c40", stroke="#0a0d14", stroke_width="0.8"))
    rail.append(el("rect", x=0, y=157, width=680, height=1, fill="#2e3850"))
    shade = el("g", fill="#0a0d14", opacity="0.5")
    shade.append(el("rect", x=0, y=160, width=680, height=2))
    return [pillar, cap, beam, bolts, wall, dots, crack, pipe_dark, pipe_light, pipe_shade, pipe_gloss, bracket, rail, shade]


def floor_fill_elements(kids):
    """Floor base and the track, minus the one-off marks (rust streaks, loose gravel) that would
    repeat with every tile; the wall-base shadow of floor-detail is full-width and kept."""
    base = [copy.deepcopy(kids[i]) for i in (49, 50, 51, 52)]
    track = copy.deepcopy(kids[53])
    for child in list(track):
        if child.get("stroke") == "#5a3a2a" or (child.get("fill") == "#2c2727" and child.get("stroke") == "#0e0b0b"):
            track.remove(child)
    detail = list(kids[55])
    shadow = [copy.deepcopy(detail[0]), copy.deepcopy(detail[1])]
    for s in shadow:
        if not (s.get("fill") == "#000000" and s.get("d", "").startswith("M0 2")):
            fail("floor-detail does not start with the two wall-base shadow bands")
    return base + shadow + [track]


def derive():
    tree = ET.parse(SRC)
    root = tree.getroot()
    check_signatures(root)
    kids = list(root)
    defs_src = list(kids[2])
    full = (0, 0, FRAME[0], FRAME[1])

    mid_elements = [kids[i] for i in MID]
    mid_elements = [copy.deepcopy(e) for e in mid_elements]
    graffiti_found = False
    for e in mid_elements:
        if local(e.tag) == "rect" and e.get("x") == "56" and e.get("width") == BEAM_WIDTH_ORIGINAL:
            e.set("width", BEAM_WIDTH_EXTENDED)
        if e.get("id") == "work-lamp":
            for child in list(e)[WORK_LAMP_BULB_INDEX:]:
                e.remove(child)
        for g in list(e.iter(q("g"))):
            for child in list(g):
                if child.get("id") == GRAFFITI_ID:
                    texts = list(child.iter(q("text")))
                    if len(texts) != GRAFFITI_TEXT_COUNT:
                        fail("graffiti group holds %d <text> elements, expected %d" % (len(texts), GRAFFITI_TEXT_COUNT))
                    for text in texts:
                        child.remove(text)
                    graffiti_found = True
    if not any(e.get("id") == "mine-face" for e in mid_elements):
        fail("mine-face group missing from the mid layer")
    if not graffiti_found:
        fail("graffiti group not found under mine-face")

    back_elements = [copy.deepcopy(kids[i]) for i in BACK]
    for old, new in BACK_SEAM_EDITS:
        hits = [e for b in back_elements for e in b.iter() if e.get("d") == old or old in e.get("d", "")]
        if len(hits) != 1:
            fail("seam edit %r matches %d back elements, expected 1" % (old, len(hits)))
        hits[0].set("d", hits[0].get("d").replace(old, new))

    lamp = list(kids[WORK_LAMP_GROUP])
    docs = {
        "back": make_doc("section 1 r2 — back", full, defs_src, back_elements),
        "mid": make_doc("section 1 r2 — mid", full, defs_src, mid_elements),
        "floor": make_doc("section 1 r2 — floor", full, defs_src, [kids[i] for i in FLOOR]),
        "mid_fill": make_doc("section 1 r2 — wall column", full, defs_src, mid_fill_elements()),
        "floor_fill": make_doc("section 1 r2 — floor column", full, defs_src, floor_fill_elements(kids)),
        "alarm": make_doc("section 1 r2 — alarm lamps", CROPS["alarm"], defs_src, [kids[i] for i in ALARM]),
        "worklamp_wall": make_doc("section 1 r2 — work lamp, wall glow", CROPS["worklamp_wall"], defs_src, lamp[WORK_LAMP_BULB_INDEX:]),
        "worklamp_floor": make_doc("section 1 r2 — work lamp, floor glow", CROPS["worklamp_floor"], defs_src, [kids[FLOOR_GLOW]]),
        "fan_blades": make_doc("section 1 r2 — fan blades", CROPS["fan_blades"], defs_src, [kids[i] for i in FAN]),
    }
    return {name: ET.tostring(doc, encoding="unicode") + "\n" for name, doc in docs.items()}


def main(argv):
    check = "--check" in argv
    if not SRC.exists():
        fail("missing %s" % SRC)
    outputs = derive()
    bad = 0
    for name, text in outputs.items():
        path = DST_DIR / ("%s_%s.svg" % (STEM, name))
        if check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                print("derive_section1_r2: %s differs from the derivation" % path.relative_to(ROOT))
                bad += 1
            else:
                print("derive_section1_r2: %s matches" % path.relative_to(ROOT))
        else:
            path.write_text(text, encoding="utf-8")
            print("derive_section1_r2: wrote %s (%d bytes)" % (path.relative_to(ROOT), len(text.encode("utf-8"))))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
