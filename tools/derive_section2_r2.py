"""tools/derive_section2_r2.py -- derive the runtime layers of the revised section 2 concept.

The author's revised concept of the ventilation room (assets/art/v2/level0_r2/level0_section2_ventilation_r2.svg,
viewBox 0 0 690 450, one flat document drawn back to front) is split into the derivatives the v2
prologue draws (assets/art/v2/backgrounds/level0_section2_ventilation_r2_*.svg):

  _mid          the duct riser, beam, pipes, wires, work lamp, wall, entrance arch, fan housing with
                its dead fan, control panel, gauge cabinet, steaming duct, lockers, exit door, red
                lamp and the live cable (transparent above the beam);
  _floor        the drawn floor from row 280 down: floor marks, loose banks, track, the conveyor
                (without the parts the game animates), the cart train, the crate and the lamp's
                floor glow;
  _belt_tile    one 22x49 mockup-px period of the belt's chevron, transparent around it: the game
                tiles and scrolls this over the belt body (the moving belt);
  _run_green    the "running" indicators: the switch's green lamp, its green screen bar and the
                green dot on the drive pulley (the game blinks this while the belt runs);
  _run_red      the same three indicators in red, composed here from the concept's own shapes and
                the red it already uses for the left screen slot (lit when the belt is stopped);
  _lever        the switch's handle and knob, cropped around their hinge so the game can turn them;
  _sparks       the live cable's discharge on the floor (the game flickers it).

This room keeps the **shared far layer** of section 1 (level0_section1_mineface_r2_back.svg): a
Parallax2D tiles the far layer on one level-wide grid, so every mine room must draw the same image.
The concept's own `ceiling-detail` band (y 92..160) is therefore dropped -- the shared rock ceiling
covers those rows, and a second copy in `_mid` would slide against it as the parallax moves.
The wall filler columns also stay section 1's (`_mid_fill`, `_floor_fill`).

Godot's SVG importer (ThorVG) draws no <pattern> fills, so every pattern of the concept is replaced
by a flat fill of the pattern's average coverage, as for the earlier sections (see
backgrounds/README.md). Inline `style="..."` attributes are stripped (this concept has none).

The original is never written. Selection is by top-level index, guarded by a signature table
(tag + key attribute) so a re-exported concept with a different structure fails here instead of
being cut blindly -- extend the table when the author ships a new revision.

Run from the repo root (Python 3, stdlib only):
    python tools/derive_section2_r2.py            # writes the seven derivatives
    python tools/derive_section2_r2.py --check    # verifies the existing derivatives, writes nothing
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
SRC = ROOT / "assets" / "art" / "v2" / "level0_r2" / "level0_section2_ventilation_r2.svg"
DST_DIR = ROOT / "assets" / "art" / "v2" / "backgrounds"
STEM = "level0_section2_ventilation_r2"
FRAME = (680, 440)

# Top-level children of <svg>, in document order: (tag, key attribute value). The key is the
# element's id, else its fill, else its stroke, else "".
SIGNATURES = [
    ("title", ""), ("desc", ""), ("defs", ""),
    ("rect", "#06080d"),          # 3  background
    ("path", "#0e121a"),          # 4  rock ceiling
    ("g", "upper-ceiling"),       # 5
    ("g", "far-gallery"),         # 6
    ("path", "#131826"),          # 7  hill band
    ("path", "url(#hatch)"),      # 8  hill hatch
    ("g", "ceiling-detail"),      # 9  dropped: the shared far layer covers these rows
    ("g", "riser-duct"),          # 10
    ("g", "beam"),                # 11
    ("g", "pipes"),               # 12
    ("g", "wires"),               # 13
    ("g", "work-lamp"),           # 14 fixture and its glow on the wall
    ("rect", "#181d2b"),          # 15 wall
    ("rect", "url(#dots)"),       # 16 wall speckle
    ("g", "#20263a"),             # 17 side walls
    ("g", "url(#dots)"),          # 18 side wall speckle
    ("g", "none"),                # 19 wall cracks
    ("g", "entrance-arch"),       # 20
    ("g", "zone-dividers"),       # 21
    ("g", "top-rail"),            # 22
    ("g", "vent-housing"),        # 23 housing, louvers, dead fan
    ("g", "control-panel"),       # 24
    ("g", "gauge-cabinet"),       # 25
    ("g", "broken-duct"),         # 26 the steaming duct
    ("g", "post-feet"),           # 27
    ("g", "right-zone"),          # 28 locker, valve, exit door, red lamp
    ("g", "live-cable"),          # 29
    ("rect", "url(#floorDepth)"), # 30 floor
    ("rect", "url(#floorgrain)"), # 31
    ("g", "floor-marks"),         # 32
    ("g", "loose-batteries"),     # 33
    ("g", "track"),               # 34
    ("g", "conveyor"),            # 35 frame, belt body, drive dot, switch
    ("g", "cart-train"),          # 36
    ("g", "spark-zone"),          # 37 -> _sparks
    ("g", "crate-small"),         # 38
    ("g", "none"),                # 39 the yellow "go right" arrow
    ("ellipse", "url(#worklamp)"),# 40 the lamp's glow on the floor
    ("rect", "#000000"),          # 41 letterbox top    (dropped)
    ("rect", "#000000"),          # 42 letterbox bottom (dropped)
]

MID = list(range(10, 30))
FLOOR = [i for i in range(30, 41) if i != 37]
CONVEYOR = 35
SPARKS = 37

# Children of the conveyor group that the game draws instead (cut from _floor).
CONVEYOR_DRIVE_DOT = [18, 19]     # the green "running" dot on the drive pulley and its halo
BELT_SURFACE = 3                  # the <g id="belt-surface"> child of the conveyor
BELT_CHEVRONS = 4                 # its <g id="belt-chevrons"> child -> replaced by the scrolling tile
BELT_SWITCH = 20                  # the <g id="belt-switch"> child of the conveyor
SWITCH_TRANSFORM = "translate(-140,-54) scale(1.25)"
SWITCH_GREEN_BAR = 4              # the green screen slot
SWITCH_LEVER = [6, 7, 8, 9, 10]   # handle (dark, steel, highlight) and knob (+highlight)
SWITCH_LAMP = [13, 14, 15]        # green core, halo, highlight (the dark socket at 12 stays)
SWITCH_LAMP_SOCKET = 12           # read (not cut) to put the composed red lamp on the same centre

# Crops of the animated pieces, in mockup px: (x, y, w, h).
CROPS = {
    "run_green": (116, 272, 326, 40),
    "run_red": (116, 272, 326, 40),
    "lever": (126, 284, 24, 28),
    "sparks": (190, 256, 60, 48),
}

# The belt's chevron tile: one period of the belt surface, in mockup px.
BELT_TILE = (22, 49)              # width (the chevron spacing), height (the belt surface)
BELT_CHEVRON_PATH = "M12 7 L5 24.5 L12 42"   # the first chevron of the concept (x 214), in tile-local x and y-307
BELT_CHEVRON_STROKE = "#3a3f4a"
BELT_CHEVRON_WIDTH = "1.6"

# The switch's hinge and lamp in mockup px, after the belt-switch group's own transform
# (x' = -140 + 1.25x, y' = -54 + 1.25y): the crops' pivots and the composed red indicators.
LEVER_HINGE = (131.25, 306.0)     # circle cx 217 cy 288 of the switch group
RED = "#c9403a"
RED_HIGHLIGHT = "#ffd0cc"

# <pattern> fills -> flat fills of the average coverage. Value: (fill, fill-opacity).
FLAT_FILLS = {
    "hatch": ("#000000", "0.06"),
    "dots": ("#000000", "0.02"),
    "stripes": ("#816634", "1"),
    "grate": ("#2c3550", "0.28"),
    "grate2": ("#1c2233", "0.30"),
    "grain2": ("#0f1420", "0.12"),
    "floorgrain": ("#1f1b1b", "0.10"),
    "gravel": ("#1e1a18", "0.14"),
    "steel": ("#141a28", "1"),
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
    print("derive_section2_r2: " + msg)
    sys.exit(1)


def check_signatures(root):
    kids = list(root)
    if len(kids) != len(SIGNATURES):
        fail("expected %d top-level elements, found %d" % (len(SIGNATURES), len(kids)))
    for i, (el, (tag, key)) in enumerate(zip(kids, SIGNATURES)):
        if local(el.tag) != tag or key_of(el) != key:
            fail("top-level element %d is <%s %s>, expected <%s %s>" % (i, local(el.tag), key_of(el), tag, key))
    conveyor = list(kids[CONVEYOR])
    if len(conveyor) != 21:
        fail("the conveyor group holds %d children, expected 21" % len(conveyor))
    switch = conveyor[BELT_SWITCH]
    if switch.get("id") != "belt-switch" or switch.get("transform") != SWITCH_TRANSFORM:
        fail("the belt switch is not <g id='belt-switch' transform='%s'>" % SWITCH_TRANSFORM)
    if len(list(switch)) != 20:
        fail("the belt switch holds %d children, expected 20" % len(list(switch)))
    surface = conveyor[BELT_SURFACE]
    if surface.get("id") != "belt-surface" or list(surface)[BELT_CHEVRONS].get("id") != "belt-chevrons":
        fail("the belt surface does not end with <g id='belt-chevrons'>")
    for i in CONVEYOR_DRIVE_DOT:
        if conveyor[i].get("fill") != "#3ac96a":
            fail("conveyor child %d is not the green drive dot" % i)
    if list(switch)[SWITCH_GREEN_BAR].get("fill") != "#3ac96a":
        fail("switch child %d is not the green screen bar" % SWITCH_GREEN_BAR)
    for i in SWITCH_LAMP:
        if list(switch)[i].get("fill") not in ("#3ac96a", "#d8ffe0"):
            fail("switch child %d is not part of the green lamp" % i)
    socket = list(switch)[SWITCH_LAMP_SOCKET]
    if local(socket.tag) != "circle" or socket.get("fill") != "#0a0c14" or socket.get("cx") is None:
        fail("switch child %d is not the lamp dark socket" % SWITCH_LAMP_SOCKET)


def strip_styles(el):
    for e in el.iter():
        e.attrib.pop("style", None)


def flatten_patterns(el):
    for e in el.iter():
        for attr in ("fill", "stroke"):
            m = URL_RE.fullmatch(e.get(attr, ""))
            if m and m.group(1) in FLAT_FILLS:
                colour, alpha = FLAT_FILLS[m.group(1)]
                e.set(attr, colour)
                if alpha != "1":
                    e.set(attr + "-opacity", alpha)


def referenced_ids(elements):
    ids = set()
    for el in elements:
        for e in el.iter():
            for v in e.attrib.values():
                for m in URL_RE.finditer(v):
                    ids.add(m.group(1))
    return ids


def make_doc(title, viewbox, defs_src, elements):
    """A new document over `viewbox` (mockup px) holding deep copies of `elements`."""
    x, y, w, h = viewbox
    root = ET.Element(q("svg"), {"width": str(w), "height": str(h), "viewBox": "%s %s %s %s" % (x, y, w, h)})
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
    return ET.Element(q(tag), {k.replace("_", "-"): str(v) for k, v in attrs.items()})


def switch_group(children):
    """The picked switch children inside the switch group's own transform, so their authored coordinates hold."""
    g = el("g", transform=SWITCH_TRANSFORM)
    for c in children:
        g.append(copy.deepcopy(c))
    return g


def red_indicators(switch):
    """
    The "stopped" indicators, composed from the concept's own geometry: the switch lamp and the
    drive dot in the red the concept already uses for the left screen slot, plus that slot lit.
    """
    kids = list(switch)
    socket_x = float(kids[SWITCH_LAMP_SOCKET].get("cx"))
    socket_y = float(kids[SWITCH_LAMP_SOCKET].get("cy"))
    lamp = el("g", transform=SWITCH_TRANSFORM)
    # The left screen slot (the concept draws it dim, at opacity 0.45); lit here.
    slot = copy.deepcopy(kids[3])
    slot.attrib.pop("opacity", None)
    lamp.append(slot)
    lamp.append(el("circle", cx=socket_x, cy=socket_y, r="1.4", fill=RED))
    lamp.append(el("circle", cx=socket_x, cy=socket_y, r="4.5", fill=RED, opacity="0.3"))
    lamp.append(el("circle", cx=socket_x - 0.4, cy=socket_y - 0.4, r="0.5", fill=RED_HIGHLIGHT))
    dot = el("g")
    dot.append(el("circle", cx="435", cy="305", r="1.6", fill=RED))
    dot.append(el("circle", cx="435", cy="305", r="4", fill=RED, opacity="0.28"))
    return [lamp, dot]


def belt_tile():
    """One period of the belt's chevron, transparent around it, in its own 22x49 frame."""
    g = el("g", fill="none", stroke=BELT_CHEVRON_STROKE, stroke_width=BELT_CHEVRON_WIDTH)
    g.append(el("path", d=BELT_CHEVRON_PATH))
    return [g]


def derive():
    tree = ET.parse(SRC)
    root = tree.getroot()
    check_signatures(root)
    kids = list(root)
    defs_src = list(kids[2])
    full = (0, 0, FRAME[0], FRAME[1])

    # The floor, with the animated conveyor parts taken out of its conveyor group.
    floor_elements = [copy.deepcopy(kids[i]) for i in FLOOR]
    conveyor = next(e for e in floor_elements if e.get("id") == "conveyor")
    conveyor_kids = list(conveyor)
    for i in sorted(CONVEYOR_DRIVE_DOT, reverse=True):
        conveyor.remove(conveyor_kids[i])
    surface = conveyor_kids[BELT_SURFACE]
    surface.remove(list(surface)[BELT_CHEVRONS])
    switch = conveyor_kids[BELT_SWITCH]
    switch_kids = list(switch)
    for i in sorted([SWITCH_GREEN_BAR] + SWITCH_LEVER + SWITCH_LAMP, reverse=True):
        switch.remove(switch_kids[i])

    src_conveyor = list(kids[CONVEYOR])
    src_switch = list(src_conveyor[BELT_SWITCH])
    green = [switch_group([src_switch[SWITCH_GREEN_BAR]] + [src_switch[i] for i in SWITCH_LAMP]),
             copy.deepcopy(src_conveyor[CONVEYOR_DRIVE_DOT[0]]),
             copy.deepcopy(src_conveyor[CONVEYOR_DRIVE_DOT[1]])]

    docs = {
        "mid": make_doc("section 2 r2 — mid", full, defs_src, [kids[i] for i in MID]),
        "floor": make_doc("section 2 r2 — floor", full, defs_src, floor_elements),
        "belt_tile": make_doc("section 2 r2 — belt chevron tile", (0, 0, BELT_TILE[0], BELT_TILE[1]), defs_src, belt_tile()),
        "run_green": make_doc("section 2 r2 — running indicators", CROPS["run_green"], defs_src, green),
        "run_red": make_doc("section 2 r2 — stopped indicators", CROPS["run_red"], defs_src, red_indicators(src_conveyor[BELT_SWITCH])),
        "lever": make_doc("section 2 r2 — switch lever", CROPS["lever"], defs_src, [switch_group([src_switch[i] for i in SWITCH_LEVER])]),
        "sparks": make_doc("section 2 r2 — live cable discharge", CROPS["sparks"], defs_src, [kids[SPARKS]]),
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
                print("derive_section2_r2: %s differs from the derivation" % path.relative_to(ROOT))
                bad += 1
            else:
                print("derive_section2_r2: %s matches" % path.relative_to(ROOT))
        else:
            path.write_text(text, encoding="utf-8")
            print("derive_section2_r2: wrote %s (%d bytes)" % (path.relative_to(ROOT), len(text.encode("utf-8"))))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
