"""Generate Flutter cubic vector outlines & animation centerlines for B1 Macintosh-Skeletal-Filled titles."""

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np


Pt = tuple[float, float]
Cubic = tuple[Pt, Pt, Pt, Pt]


@dataclass(frozen=True)
class WeightedStroke:
    segments: tuple[Cubic, ...]
    seg_scales: tuple[float, ...]
    start_taper: float = 1.0
    end_taper: float = 1.0


def sample_cubic(c: Cubic, n: int = 36) -> np.ndarray:
    p0, p1, p2, p3 = [np.asarray(p, dtype=np.float64) for p in c]
    t = np.linspace(0.0, 1.0, n)[:, None]
    u = 1.0 - t
    return (u**3) * p0 + 3.0 * (u**2) * t * p1 + 3.0 * u * (t**2) * p2 + (t**3) * p3


def sample_weighted_stroke(ws: WeightedStroke, per_seg: int = 40) -> tuple[np.ndarray, np.ndarray]:
    pts_list = []
    scale_list = []
    n_segs = len(ws.segments)
    for idx, (seg, sc) in enumerate(zip(ws.segments, ws.seg_scales)):
        raw = sample_cubic(seg, per_seg)
        prev_sc = ws.seg_scales[idx - 1] if idx > 0 else sc
        next_sc = ws.seg_scales[idx + 1] if idx + 1 < n_segs else sc
        t = np.linspace(0.0, 1.0, len(raw))
        seg_w = np.full(len(raw), sc, dtype=np.float64)
        if idx > 0:
            w_in = np.clip(t / 0.28, 0.0, 1.0)
            mid_in = 0.5 * (prev_sc + sc)
            seg_w = mid_in + (sc - mid_in) * (3 * w_in**2 - 2 * w_in**3)
        if idx + 1 < n_segs:
            w_out = np.clip((1.0 - t) / 0.28, 0.0, 1.0)
            mid_out = 0.5 * (next_sc + sc)
            blend_out = mid_out + (sc - mid_out) * (3 * w_out**2 - 2 * w_out**3)
            seg_w = np.minimum(seg_w, blend_out) if sc > mid_out else np.maximum(seg_w, blend_out)
        if idx > 0:
            raw = raw[1:]
            seg_w = seg_w[1:]
        pts_list.append(raw)
        scale_list.append(seg_w)

    poly = np.vstack(pts_list)
    scales = np.concatenate(scale_list)
    n = len(poly)
    t_all = np.linspace(0.0, 1.0, n)
    if ws.start_taper < 1.0:
        w = np.clip(t_all / 0.14, 0.0, 1.0)
        scales *= ws.start_taper + (1.0 - ws.start_taper) * (3 * w**2 - 2 * w**3)
    if ws.end_taper < 1.0:
        w = np.clip((1.0 - t_all) / 0.16, 0.0, 1.0)
        scales *= ws.end_taper + (1.0 - ws.end_taper) * (3 * w**2 - 2 * w**3)
    return poly, scales


def apply_transform(poly: np.ndarray, slant_deg: float = 9.0, squash_y: float = 0.97) -> np.ndarray:
    p = poly.copy()
    cx, cy = 50.0, 50.0
    dx = p[:, 0] - cx
    dy = (p[:, 1] - cy) * squash_y
    tan_s = math.tan(math.radians(slant_deg))
    p[:, 0] = cx + dx - dy * tan_s
    p[:, 1] = cy + dy
    return p


def polyline_sdf(gx: np.ndarray, gy: np.ndarray, poly: np.ndarray, radii: np.ndarray) -> np.ndarray:
    a = poly[:-1]
    b = poly[1:]
    ra = radii[:-1]
    rb = radii[1:]
    ab = b - a
    ab_len2 = np.sum(ab * ab, axis=1) + 1e-12
    px = gx[..., None]
    py = gy[..., None]
    best = np.full(gx.shape, 1e6, dtype=np.float64)
    step = 16
    for start in range(0, len(a), step):
        end = min(start + step, len(a))
        ax = a[start:end, 0][None, None, :]
        ay = a[start:end, 1][None, None, :]
        abx = ab[start:end, 0][None, None, :]
        aby = ab[start:end, 1][None, None, :]
        l2 = ab_len2[start:end][None, None, :]
        apx = px - ax
        apy = py - ay
        h = np.clip((apx * abx + apy * aby) / l2, 0.0, 1.0)
        dx = apx - abx * h
        dy = apy - aby * h
        r_interp = ra[start:end][None, None, :] + (rb[start:end] - ra[start:end])[None, None, :] * h
        d = np.sqrt(dx * dx + dy * dy) - r_interp
        best = np.minimum(best, np.min(d, axis=2))
    return best


def smin(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


# Approved B1 glyph centerlines (exact match to B1 preview)
B1_GLYPHS: dict[str, list[WeightedStroke]] = {
    "今": [
        WeightedStroke(
            segments=(((48.5, 12.0), (38.5, 26.5), (24.5, 39.0), (11.5, 47.5)),),
            seg_scales=(1.0,),
            start_taper=0.94,
            end_taper=0.84,
        ),
        WeightedStroke(
            segments=(((48.5, 15.0), (59.5, 27.5), (73.5, 37.5), (88.5, 42.2)),),
            seg_scales=(1.0,),
            start_taper=0.94,
            end_taper=0.84,
        ),
        WeightedStroke(
            segments=(
                ((44.8, 32.5), (48.5, 35.8), (51.0, 38.8), (49.5, 41.2)),
                ((49.5, 41.2), (43.5, 47.0), (29.5, 52.0), (27.2, 54.5)),
                ((27.2, 54.5), (41.0, 52.2), (58.0, 49.5), (67.8, 49.6)),
                ((67.8, 49.6), (72.2, 50.0), (68.5, 58.2), (59.5, 67.5)),
                ((59.5, 67.5), (51.5, 76.2), (42.8, 82.8), (37.2, 86.8)),
                ((37.2, 86.8), (41.5, 85.2), (47.5, 81.8), (53.2, 78.2)),
            ),
            seg_scales=(0.95, 0.56, 0.96, 0.95, 0.94, 0.60),
            end_taper=0.78,
        ),
    ],
    "日": [
        WeightedStroke(
            segments=(((31.0, 23.0), (29.8, 41.5), (28.5, 60.0), (29.0, 78.5)),),
            seg_scales=(0.98,),
            end_taper=0.88,
        ),
        WeightedStroke(
            segments=(
                ((31.2, 25.0), (45.0, 22.8), (59.5, 21.4), (69.0, 22.2)),
                ((69.0, 22.2), (74.2, 22.8), (74.0, 29.0), (72.6, 40.0)),
                ((72.6, 40.0), (71.2, 53.5), (69.8, 67.0), (68.0, 78.5)),
            ),
            seg_scales=(0.98, 0.96, 0.98),
            end_taper=0.90,
        ),
        WeightedStroke(
            segments=(
                ((32.2, 51.0), (43.5, 49.2), (55.0, 47.6), (62.8, 47.4)),
                ((62.8, 47.4), (54.0, 56.5), (38.0, 69.5), (30.2, 77.6)),
                ((30.2, 77.6), (44.0, 76.0), (58.0, 74.8), (70.5, 75.5)),
            ),
            seg_scales=(0.92, 0.52, 0.96),
            end_taper=0.88,
        ),
    ],
    "课": [
        WeightedStroke(
            segments=(
                ((19.0, 20.0), (22.5, 23.5), (25.8, 26.8), (27.8, 29.5)),
                ((27.8, 29.5), (22.0, 36.2), (14.0, 43.2), (11.8, 46.2)),
                ((11.8, 46.2), (17.5, 44.5), (22.5, 43.2), (25.8, 43.4)),
                ((25.8, 43.4), (27.8, 43.8), (26.8, 49.5), (26.0, 58.0)),
                ((26.0, 58.0), (25.0, 68.5), (24.4, 75.2), (25.5, 77.2)),
                ((25.5, 77.2), (27.8, 78.8), (35.5, 65.5), (43.2, 46.2)),
            ),
            seg_scales=(0.98, 0.44, 0.96, 0.96, 0.96, 0.62),
            end_taper=0.78,
        ),
        WeightedStroke(
            segments=(((43.5, 21.0), (44.0, 30.0), (44.6, 39.0), (45.4, 47.5)),),
            seg_scales=(0.95,),
        ),
        WeightedStroke(
            segments=(
                ((43.8, 22.2), (57.5, 20.4), (70.5, 19.0), (79.0, 19.4)),
                ((79.0, 19.4), (83.2, 19.8), (82.8, 24.5), (81.8, 30.8)),
                ((81.8, 30.8), (80.8, 37.2), (79.5, 42.5), (78.2, 47.2)),
            ),
            seg_scales=(0.95, 0.95, 0.95),
        ),
        WeightedStroke(
            segments=(
                ((46.0, 34.2), (57.5, 33.0), (68.0, 31.8), (74.8, 31.8)),
                ((74.8, 31.8), (65.0, 37.8), (52.0, 43.2), (46.2, 46.5)),
                ((46.2, 46.5), (58.0, 45.2), (69.5, 44.2), (77.5, 44.5)),
            ),
            seg_scales=(0.90, 0.50, 0.92),
        ),
        WeightedStroke(
            segments=(((36.5, 61.4), (53.5, 59.2), (71.0, 57.2), (87.5, 55.2)),),
            seg_scales=(0.96,),
        ),
        WeightedStroke(
            segments=(((61.8, 21.2), (61.5, 43.0), (61.2, 65.5), (61.0, 88.8)),),
            seg_scales=(0.96,),
            end_taper=0.92,
        ),
        WeightedStroke(
            segments=(
                ((60.2, 59.5), (52.5, 69.2), (43.8, 77.6), (34.2, 84.0)),
                ((34.2, 84.0), (41.5, 80.5), (53.5, 70.0), (62.8, 59.8)),
                ((62.8, 59.8), (70.5, 68.5), (79.2, 76.2), (90.5, 79.8)),
            ),
            seg_scales=(0.95, 0.50, 0.96),
            end_taper=0.80,
        ),
    ],
    "表": [
        WeightedStroke(
            segments=(
                ((27.0, 25.4), (42.5, 23.4), (58.5, 21.8), (73.5, 20.6)),
                ((73.5, 20.6), (59.0, 28.2), (40.0, 34.5), (31.2, 38.4)),
                ((31.2, 38.4), (44.0, 36.8), (57.5, 35.6), (69.5, 34.8)),
            ),
            seg_scales=(0.94, 0.52, 0.92),
        ),
        WeightedStroke(
            segments=(((15.5, 52.8), (38.0, 50.4), (62.5, 48.4), (85.5, 46.8)),),
            seg_scales=(0.96,),
        ),
        WeightedStroke(
            segments=(
                ((50.5, 11.5), (50.2, 24.5), (50.0, 38.0), (49.4, 51.0)),
                ((49.4, 51.0), (40.0, 61.5), (27.8, 70.2), (14.5, 76.8)),
                ((14.5, 76.8), (23.5, 73.2), (33.5, 66.2), (39.5, 61.2)),
                ((39.5, 61.2), (39.0, 71.0), (38.8, 79.8), (39.2, 85.2)),
                ((39.2, 85.2), (39.6, 88.4), (45.0, 85.2), (61.5, 74.5)),
                ((61.5, 74.5), (69.5, 68.5), (75.5, 60.5), (77.8, 54.0)),
                ((77.8, 54.0), (73.5, 58.0), (65.5, 61.2), (53.2, 56.0)),
                ((53.2, 56.0), (62.0, 67.5), (74.2, 77.2), (90.8, 80.5)),
            ),
            seg_scales=(0.96, 0.94, 0.48, 0.94, 0.94, 0.48, 0.88, 0.97),
            end_taper=0.78,
        ),
    ],
}


def marching_squares_contours(field: np.ndarray) -> list[np.ndarray]:
    """Extract sub-pixel zero-level closed contours in unit [0, 100] space."""
    H, W = field.shape
    dx = 100.0 / (W - 1)
    dy = 100.0 / (H - 1)

    def interp(v1: float, v2: float) -> float:
        dv = v2 - v1
        if abs(dv) < 1e-12:
            return 0.5
        return float(np.clip(-v1 / dv, 0.0, 1.0))

    # Build oriented directed segments around interior (< 0) region
    # Edge table per 4-bit corner inside (< 0) mask: TL(8), TR(4), BR(2), BL(1)
    edge_pairs: dict[int, list[tuple[int, int]]] = {
        0: [],
        1: [(3, 2)],
        2: [(2, 1)],
        3: [(3, 1)],
        4: [(1, 0)],
        5: [(3, 0), (1, 2)],
        6: [(2, 0)],
        7: [(3, 0)],
        8: [(0, 3)],
        9: [(0, 2)],
        10: [(0, 1), (2, 3)],
        11: [(0, 1)],
        12: [(1, 3)],
        13: [(1, 2)],
        14: [(2, 3)],
        15: [],
    }

    adj: dict[tuple[int, int, int], list[tuple[int, int, int]]] = {}
    pts_map: dict[tuple[int, int, int], tuple[float, float]] = {}

    for r in range(H - 1):
        for c in range(W - 1):
            v_tl = float(field[r, c])
            v_tr = float(field[r, c + 1])
            v_br = float(field[r + 1, c + 1])
            v_bl = float(field[r + 1, c])
            mask = (
                (8 if v_tl < 0 else 0)
                | (4 if v_tr < 0 else 0)
                | (2 if v_br < 0 else 0)
                | (1 if v_bl < 0 else 0)
            )
            pairs = edge_pairs[mask]
            if not pairs:
                continue
            # Canonical edge key (row, col, orientation: 0=horiz, 1=vert)
            # Local edges: 0=top, 1=right, 2=bottom, 3=left
            keys = {
                0: (r, c, 0),
                1: (r, c + 1, 1),
                2: (r + 1, c, 0),
                3: (r, c, 1),
            }
            coords = {
                0: ((c + interp(v_tl, v_tr)) * dx, r * dy),
                1: ((c + 1) * dx, (r + interp(v_tr, v_br)) * dy),
                2: ((c + interp(v_bl, v_br)) * dx, (r + 1) * dy),
                3: (c * dx, (r + interp(v_tl, v_bl)) * dy),
            }
            for e_a, e_b in pairs:
                ka, kb = keys[e_a], keys[e_b]
                pts_map[ka] = coords[e_a]
                pts_map[kb] = coords[e_b]
                adj.setdefault(ka, []).append(kb)

    contours: list[np.ndarray] = []
    while adj:
        start = next(iter(adj))
        loop = [pts_map[start]]
        cur = start
        while True:
            nxts = adj.get(cur)
            if not nxts:
                adj.pop(cur, None)
                break
            nxt = nxts.pop(0)
            if not nxts:
                adj.pop(cur, None)
            if nxt == start:
                break
            loop.append(pts_map[nxt])
            cur = nxt
        if len(loop) >= 6:
            contours.append(np.asarray(loop, dtype=np.float64))
    return contours


def taubin_smooth(poly: np.ndarray, iters: int = 4, lam: float = 0.45, mu: float = -0.47) -> np.ndarray:
    p = poly.copy()
    for _ in range(iters):
        avg = 0.5 * (np.roll(p, 1, axis=0) + np.roll(p, -1, axis=0))
        p = p + lam * (avg - p)
        avg2 = 0.5 * (np.roll(p, 1, axis=0) + np.roll(p, -1, axis=0))
        p = p + mu * (avg2 - p)
    return p


def rdp_closed(poly: np.ndarray, tol: float) -> np.ndarray:
    """Simplify closed polygon while keeping rounded curve fidelity."""
    # Split at furthest pair of points so open RDP handles loop seamlessly
    n = len(poly)
    if n <= 8:
        return poly
    p0 = poly[0]
    d2 = np.sum((poly - p0) ** 2, axis=1)
    idx_far = int(np.argmax(d2))

    def rdp_open(pts: np.ndarray) -> np.ndarray:
        if len(pts) <= 2:
            return pts
        a, b = pts[0], pts[-1]
        ab = b - a
        ab2 = float(np.dot(ab, ab))
        if ab2 < 1e-12:
            dists = np.linalg.norm(pts - a, axis=1)
        else:
            t = np.clip(np.dot(pts - a, ab) / ab2, 0.0, 1.0)[:, None]
            proj = a + t * ab
            dists = np.linalg.norm(pts - proj, axis=1)
        i_max = int(np.argmax(dists))
        if dists[i_max] <= tol:
            return np.vstack([pts[0], pts[-1]])
        left = rdp_open(pts[: i_max + 1])
        right = rdp_open(pts[i_max:])
        return np.vstack([left[:-1], right])

    arc1 = rdp_open(poly[: idx_far + 1])
    arc2 = rdp_open(np.vstack([poly[idx_far:], poly[:1]]))
    out = np.vstack([arc1[:-1], arc2[:-1]])
    return out


def catmull_rom_cubics(poly: np.ndarray, tension: float = 0.5) -> list[tuple[float, float, float, float, float, float]]:
    """Convert closed polygon to smooth cubic Bezier segments `(c1x, c1y, c2x, c2y, p2x, p2y)`."""
    n = len(poly)
    cubics = []
    for i in range(n):
        p0 = poly[(i - 1) % n]
        p1 = poly[i]
        p2 = poly[(i + 1) % n]
        p3 = poly[(i + 2) % n]
        c1 = p1 + (p2 - p0) * (tension / 3.0)
        c2 = p2 - (p3 - p1) * (tension / 3.0)
        cubics.append((float(c1[0]), float(c1[1]), float(c2[0]), float(c2[1]), float(p2[0]), float(p2[1])))
    return cubics


def build_char_data(ch: str) -> tuple[list[tuple[float, float, list[tuple[float, float, float, float, float, float]]]], list[list[Pt]]]:
    """Compute SDF outlines (in 0..100 grid) + transformed animation centerlines."""
    strokes = B1_GLYPHS[ch]
    grid_n = 360
    xs = np.linspace(0.0, 100.0, grid_n)
    ys = np.linspace(0.0, 100.0, grid_n)
    gx, gy = np.meshgrid(xs, ys)

    radius = 3.95
    blend_k = 2.15
    combined: np.ndarray | None = None
    centerlines: list[list[Pt]] = []

    for ws in strokes:
        raw_poly, scale = sample_weighted_stroke(ws, per_seg=36)
        poly = apply_transform(raw_poly, slant_deg=9.0, squash_y=0.97)
        # Compact polyline for Flutter draw-on animation (~28 pts per stroke)
        step_pts = max(2, len(poly) // 36)
        anim_poly = poly[::step_pts]
        if not np.allclose(anim_poly[-1], poly[-1]):
            anim_poly = np.vstack([anim_poly, poly[-1:]])
        centerlines.append([(float(p[0]), float(p[1])) for p in anim_poly])

        radii = scale * radius
        d = polyline_sdf(gx, gy, poly, radii)
        combined = d if combined is None else smin(combined, d, blend_k)

    assert combined is not None
    raw_loops = marching_squares_contours(combined)
    outlines = []
    for lp in raw_loops:
        sm = taubin_smooth(lp, iters=4)
        simp = rdp_closed(sm, tol=0.22)
        if len(simp) < 5:
            continue
        cubics = catmull_rom_cubics(simp, tension=0.45)
        outlines.append((float(simp[0][0]), float(simp[0][1]), cubics))
    return outlines, centerlines


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    out_dart = root / "mobile/lib/ui/macintosh_hello_glyphs.g.dart"

    lines: list[str] = [
        "// GENERATED CODE - DO NOT EDIT BY HAND.",
        "// Generated by scripts/generate_macintosh_hello_glyphs.py.",
        "// Original B1 skeletal cursive vector outlines inspired by Apple Macintosh Skeletal Filled.",
        "import 'dart:ui';",
        "",
        "class HelloGlyphContour {",
        "  const HelloGlyphContour(this.startX, this.startY, this.cubics);",
        "  final double startX;",
        "  final double startY;",
        "  // Flattened [c1x, c1y, c2x, c2y, x, y, ...] in 0..100 character space.",
        "  final List<double> cubics;",
        "}",
        "",
        "class HelloGlyphData {",
        "  const HelloGlyphData(this.contours, this.strokes);",
        "  final List<HelloGlyphContour> contours;",
        "  // Sequential pen strokes, flattened [x0, y0, x1, y1, ...] in 0..100 space.",
        "  final List<List<double>> strokes;",
        "",
        "  Path buildOutlinePath({double offsetX = 0, double scale = 1}) {",
        "    final path = Path()..fillType = PathFillType.evenOdd;",
        "    for (final c in contours) {",
        "      path.moveTo((c.startX + offsetX) * scale, c.startY * scale);",
        "      final k = c.cubics;",
        "      for (var i = 0; i + 5 < k.length; i += 6) {",
        "        path.cubicTo(",
        "          (k[i] + offsetX) * scale,",
        "          k[i + 1] * scale,",
        "          (k[i + 2] + offsetX) * scale,",
        "          k[i + 3] * scale,",
        "          (k[i + 4] + offsetX) * scale,",
        "          k[i + 5] * scale,",
        "        );",
        "      }",
        "      path.close();",
        "    }",
        "    return path;",
        "  }",
        "}",
        "",
        "const Map<String, HelloGlyphData> macintoshHelloB1Glyphs = {",
    ]

    for ch in ("今", "日", "课", "表"):
        outlines, strokes = build_char_data(ch)
        print(f"Char {ch}: {len(outlines)} contours, {[len(c[2]) for c in outlines]} cubics, {len(strokes)} strokes")
        lines.append(f"  '{ch}': HelloGlyphData(")
        lines.append("    [")
        for sx, sy, cubics in outlines:
            flat = ", ".join(f"{v:.2f}" for seg in cubics for v in seg)
            lines.append(f"      HelloGlyphContour({sx:.2f}, {sy:.2f}, [{flat}]),")
        lines.append("    ],")
        lines.append("    [")
        for st in strokes:
            flat_s = ", ".join(f"{v:.2f}" for p in st for v in p)
            lines.append(f"      [{flat_s}],")
        lines.append("    ],")
        lines.append("  ),")

    lines.append("};")
    out_dart.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Wrote", out_dart)


if __name__ == "__main__":
    main()
