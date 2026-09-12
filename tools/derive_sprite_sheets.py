"""tools/derive_sprite_sheets.py -- derive runtime sprite sheets from the author's keyframe sheets.

The author's sheets (assets/art/v2/keyframes/<name>_keyframes.svg, 680x800) are review boards:
a full-canvas background <rect fill="#0d1018">, one 8 px "floor" stripe <rect fill="#151212">
per row and <text> labels are drawn *around* the poses, which all live in one trailing
<g stroke="#0b0909">. Imported as a texture that board chrome becomes a dark card behind
every AtlasTexture region, so the runtime reads derived copies instead:
assets/art/v2/sprites/<same name>.svg = the same document with only the pose group (and the
<title>) kept. The pose group is copied verbatim, so the region maps
assets/art/v2/keyframes/<name>.frames.json stay valid for both files.

The originals are never written. Selection is structural and guarded: every top-level element
must be one of the known chrome shapes or the pose group, otherwise the script fails instead
of guessing -- when the artist ships a new sheet that breaks the layout, extend the rules here.

Run from the repo root (Python 3, stdlib only):
    python tools/derive_sprite_sheets.py            # writes assets/art/v2/sprites/*.svg
    python tools/derive_sprite_sheets.py --check    # verifies the existing derivatives, writes nothing
Exit 0 when every sheet was derived (or, with --check, matches), 1 on any violation.
Afterwards: godot --headless --path . --import, then godot --headless --path . -s tools/build_spriteframes.gd.
"""
import copy
import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "assets" / "art" / "v2" / "keyframes"
DST_DIR = ROOT / "assets" / "art" / "v2" / "sprites"
SHEETS = ["rey_unarmed_keyframes", "rey_crowbar_keyframes", "dan_keyframes", "guard_keyframes"]

CANVAS = ("680", "800")
BACKGROUND_FILL = "#0d1018"
FLOOR_STRIPE_FILL = "#151212"
FLOOR_STRIPE_HEIGHT = "8"
POSE_GROUP_STROKE = "#0b0909"
TITLE_SUFFIX = " — sprite sheet without the board background"


def tag(el):
    return el.tag.split("}")[-1]


def classify(el):
    """Name the role of a top-level element, or raise when it is not a known one."""
    t = tag(el)
    a = el.attrib
    if t in ("title", "metadata", "desc"):
        return t
    if t == "text":
        return "label"
    if t == "rect":
        if a.get("fill") == BACKGROUND_FILL and (a.get("width"), a.get("height")) == CANVAS and a.get("x", "0") == "0" and a.get("y", "0") == "0":
            return "background"
        if a.get("fill") == FLOOR_STRIPE_FILL and a.get("width") == CANVAS[0] and a.get("height") == FLOOR_STRIPE_HEIGHT and a.get("x") == "0":
            return "floor_stripe"
        raise ValueError("unknown top-level <rect> %s" % dict(a))
    if t == "g" and a.get("stroke") == POSE_GROUP_STROKE:
        if any(tag(d) == "text" for d in el.iter()):
            raise ValueError("the pose group contains <text>; labels are expected outside it")
        return "poses"
    raise ValueError("unknown top-level <%s> %s" % (t, dict(a)))


def load(path):
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"<metadata>.*?</metadata>", "", text, flags=re.S)   # c2pa manifest: binary, not art
    return ET.fromstring(text)


def derive(root):
    """The document with only <title> and the pose group; returns (element, cut summary)."""
    out = ET.Element(root.tag, dict(root.attrib))
    assert (root.get("width"), root.get("height")) == CANVAS and root.get("viewBox") == "0 0 %s %s" % CANVAS, \
        "canvas is %s x %s viewBox %s, expected %s" % (root.get("width"), root.get("height"), root.get("viewBox"), CANVAS)
    cut = {}
    pose_groups = 0
    for child in root:
        role = classify(child)
        if role == "title":
            title = copy.deepcopy(child)
            title.text = (title.text or "") + TITLE_SUFFIX
            out.append(title)
        elif role == "poses":
            out.append(copy.deepcopy(child))
            pose_groups += 1
        else:
            cut[role] = cut.get(role, 0) + 1
    assert pose_groups == 1, "expected exactly one pose group, found %d" % pose_groups
    assert cut.get("background") == 1, "expected exactly one background rect, found %s" % cut.get("background", 0)
    return out, cut


def serialize(el):
    return ET.tostring(el, encoding="unicode") + "\n"


def pose_group_text(root):
    groups = [c for c in root if tag(c) == "g" and c.get("stroke") == POSE_GROUP_STROKE]
    return ET.tostring(groups[0], encoding="unicode") if len(groups) == 1 else None


def main(argv):
    check_only = "--check" in argv
    failures = []
    DST_DIR.mkdir(exist_ok=True)
    for name in SHEETS:
        src = SRC_DIR / (name + ".svg")
        dst = DST_DIR / (name + ".svg")
        try:
            root = load(src)
            derived, cut = derive(root)
            text = serialize(derived)
            if pose_group_text(derived) != pose_group_text(root):
                raise ValueError("pose group changed during derivation")
            if check_only:
                current = dst.read_text(encoding="utf-8") if dst.exists() else None
                if current != text:
                    raise ValueError("%s does not match the derivation of %s (re-run without --check)" % (dst, src))
                print("OK   %s matches %s" % (dst.relative_to(ROOT), src.relative_to(ROOT)))
            else:
                dst.write_text(text, encoding="utf-8", newline="\n")
                summary = ", ".join("%d %s" % (n, role) for role, n in sorted(cut.items()))
                print("WROTE %s (cut %s; pose group verbatim)" % (dst.relative_to(ROOT), summary))
        except (AssertionError, ValueError, OSError, ET.ParseError) as exc:
            failures.append("%s: %s" % (src.relative_to(ROOT), exc))
            print("FAIL %s: %s" % (src.relative_to(ROOT), exc))
    if failures:
        print("derive_sprite_sheets: FAILED (%d)" % len(failures))
        return 1
    print("derive_sprite_sheets: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
