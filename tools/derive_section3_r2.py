"""tools/derive_section3_r2.py -- derive the runtime layers of the revised section 3 concept.

The author's revised concept of the exit hall (assets/art/v2/level0_r2/level0_section3_exit_r2.svg,
viewBox 0 0 690 450, one flat document drawn back to front) is split into the derivatives the v2
prologue draws (assets/art/v2/backgrounds/level0_section3_exit_r2_*.svg):

  _back         rock ceiling, upper ceiling bands, far gallery, the hill band and the ceiling
                detail that carries the boulders and the two far cables (mockup rows <= 160);
                opaque, tiled by the far-layer parallax;
  _mid          the room itself: wall 160..280, beam and pillars, pipes and conduits, the entry
                door, the LED board (without its text), the control box, the lift frame with its
                winch and ropes, the shaft, the lift lamp, the shaft shading, the call box, the
                right wall column, the camera bracket (without its red LED), the two spotlights
                and the confiscated-power-bank locker (without its three cell indicators);
  _floor        the drawn floor from row 280 down: floor plate and grain, floor marks, the two
                loose power banks (without their charge readouts), the track and the spotlight
                pools on the floor;
  _camera_lamp  the red LED of the surveillance camera with its glow (the game blinks it);
  _cell_a/_b/_c the three cell indicators of the confiscated locker, one crop each so the game can
                blink them out of phase with one another;
  _bank_a/_bank_b the charge readouts of the two loose power banks on the floor, one crop each;
  _cage_gate    the grate that closes the lift cage (the grate field, the two warning bands, the
                centre mullion, the cross bar and its two bolts), cut out of the mid layer so the
                game can open the cage by hiding or sliding this one sprite and reveal the shaft.

Removed from every derivative: **the two drawn guards** (the two `<g transform="translate(-156,-96)">`
and `<g transform="translate(-58,-96)">` blocks). The game puts two real Guard actors there, and a
painted duplicate standing next to a real one is what the author rejected before; the derivation
asserts both blocks were found, and that no output still carries their skin/limb colours.

Godot's SVG importer (ThorVG) draws no <pattern> fills and no <text>, so every pattern of the
concept is replaced by a flat fill of the pattern's average coverage, as for the earlier sections
(see backgrounds/README.md), and the three <text> lines of `<g id="led-board">` are dropped -- the
game draws that board with Godot Labels. Inline `style="..."` attributes are stripped (this concept
has none). Gradients ThorVG does draw, so they are carried into the derivatives' own <defs>.

The far layer is tiled from column 240 to 680 (SectionBackdrop.BackSlice), so the three strokes
that cross that cut at different heights are bent to meet (BACK_SEAM_EDITS) -- the same three
strokes, with the same edit, as tools/derive_section1_r2.py: this concept draws the gallery rail
and the two far cables exactly as section 1 does.

The original is never written. Selection is by top-level index, guarded by a signature table
(tag + key attribute) so a re-exported concept with a different structure fails here instead of
being cut blindly -- extend the table when the author ships a new revision.

Run from the repo root (Python 3, stdlib only):
    python tools/derive_section3_r2.py            # writes the ten derivatives
    python tools/derive_section3_r2.py --check    # verifies the existing derivatives, writes nothing
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
SRC = ROOT / "assets" / "art" / "v2" / "level0_r2" / "level0_section3_exit_r2.svg"
DST_DIR = ROOT / "assets" / "art" / "v2" / "backgrounds"
STEM = "level0_section3_exit_r2"
FRAME = (680, 440)

# Top-level children of <svg>, in document order: (tag, key attribute value). The key is the
# element's id, else its fill, else its stroke, else "" -- exactly what a structural diff needs to
# notice a moved or missing element.
SIGNATURES = [
    ("title", ""), ("desc", ""), ("defs", ""),
    ("rect", "#06080d"),          # 3  background
    ("path", "#0e121a"),          # 4  rock ceiling
    ("g", "upper-ceiling"),       # 5
    ("g", "far-gallery"),         # 6
    ("path", "#131826"),          # 7  hill band
    ("path", "url(#hatch)"),      # 8  hill hatch
    ("g", "ceiling-detail"),      # 9  ceiling grain, boulders, the two far cables
    ("rect", "#181d2b"),          # 10 wall
    ("rect", "url(#dots)"),       # 11 wall speckle
    ("g", "#1a2030"),             # 12 pillars
    ("g", "#0a0d14"),             # 13 pillar caps
    ("rect", "#242c40"),          # 14 beam
    ("g", "#0a0d14"),             # 15 beam bolts
    ("g", "none"),                # 16 pipe, dark core
    ("g", "none"),                # 17 pipe, light
    ("g", "pipe-clamps"),         # 18
    ("g", "none"),                # 19 conduits
    ("path", "none"),             # 20 red conduit
    ("g", "#4a3a2a"),             # 21 conduit brackets
    ("g", "entry-door"),          # 22
    ("g", "led-board"),           # 23 the tariff board; its three <text> lines are dropped
    ("rect", "#232a3e"),          # 24 control box on the pillar
    ("rect", "#1a1f2e"),          # 25
    ("rect", "#0a0c14"),          # 26 screen recess
    ("rect", "#f2c451"),          # 27 screen
    ("rect", "#3a2a10"),          # 28
    ("circle", "#0a0c14"),        # 29 button socket
    ("circle", "#f2c451"),        # 30 button
    ("circle", "#f2c451"),        # 31 button halo
    ("path", "#0a0c14"),          # 32 box conduit down
    ("rect", "#1a1f2e"),          # 33 box foot
    ("path", "#0a0c14"),          # 34 box conduit right
    ("rect", "#080a10"),          # 35 lift shaft opening
    ("g", "#1a2030"),             # 36 lift frame
    ("g", "#0a0d14"),             # 37 frame bolts
    ("g", "none"),                # 38 frame braces
    ("rect", "#1a2030"),          # 39 winch housing
    ("circle", "#0a0c14"),        # 40 winch drum
    ("circle", "#3a4462"),        # 41 drum hub
    ("g", "none"),                # 42 drum marks
    ("rect", "#0a0c14"),          # 43 left rope guide
    ("rect", "#0a0c14"),          # 44 right rope guide
    ("path", "#6b7080"),          # 45 the two ropes
    ("path", "#0a0c14"),          # 46 rope ties
    ("rect", "#10131c"),          # 47 shaft interior
    ("rect", "url(#hatch)"),      # 48 shaft hatch
    ("g", "lift-lamp"),           # 49 the cage lamp and its glow
    ("g", "#e0b45a"),             # 50 warm tint over the cage
    ("g", ""),                    # 51 GUARD, translate(-156,-96)  -> removed everywhere
    ("g", ""),                    # 52 GUARD, translate(-58,-96)   -> removed everywhere
    ("g", "#000000"),             # 53 shaft shading (stays: it is behind the gate)
    ("g", "url(#grate)"),         # 54 cage grate        -> _cage_gate
    ("rect", "url(#stripes)"),    # 55 warning band, top -> _cage_gate
    ("rect", "url(#stripes)"),    # 56 warning band, foot-> _cage_gate
    ("g", "#1a2030"),             # 57 mullion + cross bar -> _cage_gate
    ("g", "#3a4462"),             # 58 cross-bar bolts     -> _cage_gate
    ("rect", "#232a3e"),          # 59 call box
    ("circle", "#4a1c20"),        # 60 call indicator (dead)
    ("rect", "#0a0c14"),          # 61 button recess
    ("rect", "#3a4462"),          # 62 call button
    ("g", "#5a3a2a"),             # 63 rust
    ("rect", "#131826"),          # 64 right wall column
    ("rect", "url(#hatch)"),      # 65
    ("g", "none"),                # 66 cable on the right wall
    ("rect", "#1a2030"),          # 67 right pillar strip
    ("g", "camera-bracket"),      # 68 the camera; its red LED -> _camera_lamp
    ("g", "spotlight"),           # 69
    ("g", "spotlight-2"),         # 70
    ("g", "confiscated-locker"),  # 71 its three cell indicators -> _cell_a/_cell_b/_cell_c
    ("rect", "url(#floorDepth)"), # 72 floor
    ("rect", "url(#floorgrain)"), # 73
    ("g", "floor-marks"),         # 74
    ("g", "loose-batteries"),     # 75 their charge readouts -> _bank_a/_bank_b
    ("g", "track"),               # 76
    ("ellipse", "#f2e8c0"),       # 77 spotlight pool on the floor
    ("ellipse", "#f2e8c0"),       # 78
    ("ellipse", "#f2e8c0"),       # 79
    ("ellipse", "#f2e8c0"),       # 80
    ("rect", "#000000"),          # 81 letterbox top    (dropped)
    ("rect", "#000000"),          # 82 letterbox bottom (dropped)
]

GUARDS = [51, 52]                 # the two painted guards: the game puts real actors here
GUARD_TRANSFORMS = ["translate(-156,-96)", "translate(-58,-96)"]
# Colours only the two guard figures use (skin and limb steel), asserted absent from every output.
GUARD_MARKERS = ["#d8a878", "#20242e"]
GUARD_MARKER_COUNT = 2            # strokes per guard carrying each marker colour
CAGE_GATE = [54, 55, 56, 57, 58]  # the grate that closes the cage -> _cage_gate

BACK = list(range(3, 10))
MID = [i for i in range(10, 72) if i not in GUARDS and i not in CAGE_GATE]
FLOOR = list(range(72, 81))

LED_BOARD = 23
LED_BOARD_TEXTS = 3               # the game draws these three lines with Godot Labels

# The camera's red LED: the last two children of the bracket's tilted head. Their authored
# coordinates only hold inside that head's own rotation, so the crop carries the same <g>.
CAMERA_BRACKET = 68
CAMERA_HEAD = 4                   # <g transform="rotate(22 90 158)"> inside <g id="camera-bracket">
CAMERA_HEAD_TRANSFORM = "rotate(22 90 158)"
CAMERA_LAMP = [5, 6]              # the #c9403a core (r 1) and its glow (r 2.5, opacity 0.3)
CAMERA_LAMP_CENTRE = ("86", "155")

# The locker's three cell indicators, as (child index, x, y, fill). Two charged cells and one dead
# one; the game blinks each on its own schedule, so each is cut as its own crop.
LOCKER = 71
LOCKER_CELLS = [
    ("cell_a", 39, "303", "223", "#e8b23a"),
    ("cell_b", 40, "327", "255", "#e8b23a"),
    ("cell_c", 41, "315", "239", "#4a1c20"),
]

# The two loose power banks on the floor, as (crop name, child index of the bank, its transform,
# child index of the readout the game blinks). The author drew bank A with a lit charge strip
# (`#e8b23a`) inside its readout window and bank B **without one** -- an empty bank. There is no
# lit strip to cut for B and this script draws nothing of its own, so B's crop is its readout
# window (the inset with the light rim); the game blinks the readout instead of a charge strip.
# BANK_B_HAS_NO_STRIP below fails the derivation the moment the author gives bank B a strip, so
# that the crop can be narrowed to it then.
BANKS = 75
BANK_CROPS = [
    ("bank_a", 0, "rotate(-8 90 320)", 3),    # the lit charge strip, #e8b23a
    ("bank_b", 1, "rotate(14 560 372)", 2),   # the readout window (this bank is drawn unlit)
]
BANK_A_STRIP = ("83", "320", "#e8b23a")
BANK_B_WINDOW = ("553", "371", "#1a1c22")

# The far layer is tiled from column 240 to 680 (SectionBackdrop.BackSlice: the ceiling polyline is
# at y 96 at both), so the three strokes that cross the cut at different heights are bent to meet:
# the gallery rail (y 82->78, made level at 80) and the two far cables (their right ends raised to
# the height they have at x 240). The same three edits as section 1, on the same three strokes.
# (old `d` fragment, new `d` fragment), each matching exactly one element.
BACK_SEAM_EDITS = [
    ("M0 82 L680 78", "M0 80 L680 80"),
    ("T480 124 T680 118", "T480 124 T680 120"),
    ("T500 134 T680 128", "T500 134 T680 132"),
]

# <pattern> fills -> flat fills of the average coverage. Value: (fill, fill-opacity). This concept
# ships the same <defs> as section 2, so the table is the same.
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

# Crops of the animated pieces, in mockup px: (x, y, w, h). Each is a few px larger than the ink it
# holds, so a glow or a stroke edge is never clipped; the overlay is placed by its own CropOrigin,
# so the margin costs nothing.
CROPS = {
    "camera_lamp": (82, 148, 12, 12),     # LED at (87.4, 153.7) after the head's rotate, glow r 2.5
    "cell_a": (301, 221, 6, 6),
    "cell_b": (325, 253, 6, 6),
    "cell_c": (313, 237, 6, 6),
    "bank_a": (80, 316, 12, 10),          # the strip at (85.7, 321.5) after the bank's rotate
    "bank_b": (551, 367, 16, 12),         # the window at (558.4, 372.1) after the bank's rotate
    "cage_gate": (380, 98, 224, 184),     # the gate block x 382..602, y 100..280, plus its strokes
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
    print("derive_section3_r2: " + msg)
    sys.exit(1)


def check_signatures(root):
    kids = list(root)
    if len(kids) != len(SIGNATURES):
        fail("expected %d top-level elements, found %d" % (len(SIGNATURES), len(kids)))
    for i, (el, (tag, key)) in enumerate(zip(kids, SIGNATURES)):
        if local(el.tag) != tag or key_of(el) != key:
            fail("top-level element %d is <%s %s>, expected <%s %s>" % (i, local(el.tag), key_of(el), tag, key))

    # The two painted guards, by their own transforms: the blocks this derivation must drop.
    for i, transform in zip(GUARDS, GUARD_TRANSFORMS):
        if kids[i].get("transform") != transform:
            fail("top-level element %d is not the guard <g transform='%s'> (found %r)" % (i, transform, kids[i].get("transform")))
    for marker in GUARD_MARKERS:
        for i in GUARDS:
            hits = sum(1 for e in kids[i].iter() for v in e.attrib.values() if v == marker)
            if hits != GUARD_MARKER_COUNT:
                fail("guard colour %s appears %d times inside guard %d, expected %d" % (marker, hits, i, GUARD_MARKER_COUNT))

    # The board's text: dropped, because ThorVG draws no <text> and the game uses Labels.
    texts = list(kids[LED_BOARD].iter(q("text")))
    if len(texts) != LED_BOARD_TEXTS:
        fail("the LED board holds %d <text> lines, expected %d" % (len(texts), LED_BOARD_TEXTS))

    # The camera's head and its red LED.
    bracket = list(kids[CAMERA_BRACKET])
    if len(bracket) != 5 or bracket[CAMERA_HEAD].get("transform") != CAMERA_HEAD_TRANSFORM:
        fail("the camera bracket does not hold the tilted head <g transform='%s'>" % CAMERA_HEAD_TRANSFORM)
    head = list(bracket[CAMERA_HEAD])
    if len(head) != 7:
        fail("the camera head holds %d children, expected 7" % len(head))
    for i in CAMERA_LAMP:
        c = head[i]
        if local(c.tag) != "circle" or c.get("fill") != "#c9403a" or (c.get("cx"), c.get("cy")) != CAMERA_LAMP_CENTRE:
            fail("camera head child %d is not the red LED at (%s, %s)" % (i, CAMERA_LAMP_CENTRE[0], CAMERA_LAMP_CENTRE[1]))

    # The locker's three cell indicators.
    locker = list(kids[LOCKER])
    if len(locker) != 56:
        fail("the confiscated locker holds %d children, expected 56" % len(locker))
    for name, index, x, y, fill in LOCKER_CELLS:
        c = locker[index]
        if local(c.tag) != "rect" or c.get("x") != x or c.get("y") != y or c.get("fill") != fill:
            fail("locker child %d is not the %s indicator <rect x=%s y=%s fill=%s>" % (index, name, x, y, fill))

    # The two loose power banks and the readouts the game blinks.
    banks = list(kids[BANKS])
    if len(banks) != len(BANK_CROPS):
        fail("the loose batteries group holds %d banks, expected %d" % (len(banks), len(BANK_CROPS)))
    for (name, index, transform, child), spec in zip(BANK_CROPS, (BANK_A_STRIP, BANK_B_WINDOW)):
        bank = banks[index]
        if bank.get("transform") != transform:
            fail("loose bank %d is not <g transform='%s'> (found %r)" % (index, transform, bank.get("transform")))
        part = list(bank)[child]
        if local(part.tag) != "rect" or (part.get("x"), part.get("y"), part.get("fill")) != spec:
            fail("bank %s child %d is not <rect x=%s y=%s fill=%s>" % (name, child, spec[0], spec[1], spec[2]))
    # Bank B is drawn unlit; the moment it gains a charge strip, cut that instead of its window.
    lit = [e for e in banks[1].iter() if e.get("fill") == "#e8b23a"]
    if lit:
        fail("the second loose bank now has a lit charge strip -- cut it into _bank_b instead of the readout window")

    # The cage gate: the block the game slides away to open the cage.
    gate = [kids[i] for i in CAGE_GATE]
    if gate[0].get("fill") != "url(#grate)" or len(list(gate[0])) != 1:
        fail("cage element 54 is not the single-rect grate overlay")
    for i, band in ((1, gate[1]), (2, gate[2])):
        if band.get("x") != "382" or band.get("width") != "220" or band.get("fill") != "url(#stripes)":
            fail("cage element %d is not a 382..602 warning band" % CAGE_GATE[i])
    mullion, crossbar = list(gate[3])
    if mullion.get("x") != "488" or crossbar.get("y") != "186":
        fail("the cage frame is not the mullion x=488 with the cross bar y=186")
    if len(list(gate[4])) != 2 or gate[4].get("fill") != "#3a4462":
        fail("the cage cross bar does not carry its two #3a4462 bolts")


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


def in_group(transform, children):
    """The picked children inside their own group's transform, so their authored coordinates hold."""
    g = el("g", transform=transform)
    for c in children:
        g.append(copy.deepcopy(c))
    return g


def cut(parent, indices):
    """Removes `indices` (of the *original* child order) from `parent` and returns the copies."""
    kids = list(parent)
    taken = [copy.deepcopy(kids[i]) for i in indices]
    for i in sorted(indices, reverse=True):
        parent.remove(kids[i])
    return taken


def check_no_guards(docs):
    """Neither guard may survive anywhere: no guard transform, none of their own colours."""
    for name, doc in docs.items():
        for e in doc.iter():
            if e.get("transform") in GUARD_TRANSFORMS:
                fail("_%s still holds a guard block (transform %s)" % (name, e.get("transform")))
            for v in e.attrib.values():
                if v in GUARD_MARKERS:
                    fail("_%s still holds guard ink (%s) -- the painted figures must not survive" % (name, v))


def derive():
    tree = ET.parse(SRC)
    root = tree.getroot()
    check_signatures(root)
    kids = list(root)
    defs_src = list(kids[2])
    full = (0, 0, FRAME[0], FRAME[1])

    # The far layer, with the three strokes that cross the tile cut bent to one height.
    back_elements = [copy.deepcopy(kids[i]) for i in BACK]
    for old, new in BACK_SEAM_EDITS:
        hits = [e for b in back_elements for e in b.iter() if old in e.get("d", "")]
        if len(hits) != 1:
            fail("seam edit %r matches %d back elements, expected 1" % (old, len(hits)))
        hits[0].set("d", hits[0].get("d").replace(old, new))

    # The room, with the board's text dropped and the animated pieces taken out.
    mid_elements = [copy.deepcopy(kids[i]) for i in MID]
    board = next(e for e in mid_elements if e.get("id") == "led-board")
    for holder in list(board.iter(q("g"))):
        for text in [c for c in list(holder) if local(c.tag) == "text"]:
            holder.remove(text)
    if list(board.iter(q("text"))):
        fail("the LED board still holds <text> after the cut")

    bracket = next(e for e in mid_elements if e.get("id") == "camera-bracket")
    lamp = cut(list(bracket)[CAMERA_HEAD], CAMERA_LAMP)

    locker = next(e for e in mid_elements if e.get("id") == "confiscated-locker")
    cells = cut(locker, [index for _, index, _, _, _ in LOCKER_CELLS])

    # The floor, with each bank's charge readout taken out.
    floor_elements = [copy.deepcopy(kids[i]) for i in FLOOR]
    banks = next(e for e in floor_elements if e.get("id") == "loose-batteries")
    readouts = [cut(list(banks)[index], [child])[0] for _, index, _, child in BANK_CROPS]

    docs = {
        "back": make_doc("section 3 r2 — back", full, defs_src, back_elements),
        "mid": make_doc("section 3 r2 — mid", full, defs_src, mid_elements),
        "floor": make_doc("section 3 r2 — floor", full, defs_src, floor_elements),
        "camera_lamp": make_doc("section 3 r2 — camera lamp", CROPS["camera_lamp"], defs_src,
                                [in_group(CAMERA_HEAD_TRANSFORM, lamp)]),
        "cage_gate": make_doc("section 3 r2 — cage gate", CROPS["cage_gate"], defs_src,
                              [kids[i] for i in CAGE_GATE]),
    }
    for (name, _, _, _, _), cell in zip(LOCKER_CELLS, cells):
        docs[name] = make_doc("section 3 r2 — locker %s" % name[-1].upper(), CROPS[name], defs_src, [cell])
    for (name, _, transform, _), readout in zip(BANK_CROPS, readouts):
        docs[name] = make_doc("section 3 r2 — power bank %s" % name[-1].upper(), CROPS[name], defs_src,
                              [in_group(transform, [readout])])

    check_no_guards(docs)
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
                print("derive_section3_r2: %s differs from the derivation" % path.relative_to(ROOT))
                bad += 1
            else:
                print("derive_section3_r2: %s matches" % path.relative_to(ROOT))
        else:
            path.write_text(text, encoding="utf-8")
            print("derive_section3_r2: wrote %s (%d bytes)" % (path.relative_to(ROOT), len(text.encode("utf-8"))))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
