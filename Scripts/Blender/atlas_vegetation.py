"""Atlas de textures de la végétation du désert, peint par programme (numpy, sans dépendance) : feuilles, palmes, écorces,
touffes d'herbe, fruits et fleurs, dans le style peint du jeu (formes nettes cernées d'un trait plus sombre, valeurs
modelées à la main plutôt que photographiques).

L'atlas est une texture de détail : la couleur de chaque pixel multiplie la couleur de sommet du modèle (0,5 = neutre,
soit un facteur 1). Les teintes de chaque espèce restent donc dans le manifeste (couleurs de sommets) et le shader garde
ses repères (rouge de sommet supérieur à 0,8 pour fleurs et fruits, vert dominant pour les palmes). L'alpha porte la
découpe des feuilles (alpha scissor dans le shader).

Tout est piloté par la section « atlas » du manifeste (desert_props.json) : disposition des tuiles et paramètres de
peinture. Le résultat est déterministe (graine du manifeste).
"""

import math
import struct
import zlib

import numpy as np

# Lumière de peinture (venue du haut à gauche de la tuile) : un côté de chaque feuille est plus clair.
LIGHT = np.array([-0.6, -0.8], dtype=np.float32)


class Canvas:
    """Toile RVBA en couleurs prémultipliées (float32), peinte par superposition « par-dessus »."""

    def __init__(self, width: int, height: int) -> None:
        self.w = width
        self.h = height
        self.rgb = np.zeros((height, width, 3), np.float32)
        self.a = np.zeros((height, width), np.float32)

    def window(self, x0: float, y0: float, x1: float, y1: float):
        """Fenêtre de pixels entiers couvrant le rectangle, rognée à la toile ; None si vide."""
        ix0 = max(0, int(math.floor(x0)))
        iy0 = max(0, int(math.floor(y0)))
        ix1 = min(self.w, int(math.ceil(x1)) + 1)
        iy1 = min(self.h, int(math.ceil(y1)) + 1)
        if ix0 >= ix1 or iy0 >= iy1:
            return None
        ys, xs = np.mgrid[iy0:iy1, ix0:ix1].astype(np.float32)
        return ix0, iy0, ix1, iy1, xs + 0.5, ys + 0.5

    def put(self, win, coverage: np.ndarray, color: np.ndarray) -> None:
        ix0, iy0, ix1, iy1 = win[:4]
        c = np.clip(coverage, 0.0, 1.0)[..., None]
        self.rgb[iy0:iy1, ix0:ix1] = color * c + self.rgb[iy0:iy1, ix0:ix1] * (1.0 - c)
        self.a[iy0:iy1, ix0:ix1] = c[..., 0] + self.a[iy0:iy1, ix0:ix1] * (1.0 - c[..., 0])


def _profile(name: str, t: np.ndarray) -> np.ndarray:
    """Demi-largeur relative d'une feuille le long de son axe (t de 0 à la base à 1 à la pointe)."""
    s = np.sin(np.pi * t)
    if name == "lanceolate":
        return np.power(np.maximum(s, 0.0), 0.75) * (1.0 - 0.3 * t)
    if name == "oblong":
        return np.power(np.maximum(s, 0.0), 0.42)
    if name == "round":
        return np.sqrt(np.maximum(0.0, 1.0 - (2.0 * t - 1.0) ** 2))
    if name == "needle":
        return 1.0 - t
    if name == "blade":
        return np.power(np.maximum(1.0 - t, 0.0), 0.8) * np.minimum(1.0, t * 10.0 + 0.3)
    raise ValueError(f"profil de feuille inconnu : {name}")


def leaf(cv: Canvas, x: float, y: float, angle: float, length: float, width: float, color, profile: str, style: dict, wrap: tuple = (False, False)) -> None:
    """Feuille droite de la base (x, y) vers la pointe : nervure, côté éclairé, cerne sombre, pointe plus claire."""
    for ox, oy in _wrap_offsets(cv, wrap):
        _leaf(cv, x + ox, y + oy, angle, length, width, np.asarray(color, np.float32), profile, style)


def _leaf(cv: Canvas, x: float, y: float, angle: float, length: float, width: float, color: np.ndarray, profile: str, style: dict) -> None:
    dx, dy = math.cos(angle), math.sin(angle)
    nx, ny = -dy, dx
    pad = width + 2.0
    xs_c = [x, x + dx * length]
    ys_c = [y, y + dy * length]
    win = cv.window(min(xs_c) - pad, min(ys_c) - pad, max(xs_c) + pad, max(ys_c) + pad)
    if win is None:
        return
    px = win[4] - x
    py = win[5] - y
    u = (px * dx + py * dy) / max(length, 1e-3)
    v = px * nx + py * ny
    t = np.clip(u, 0.0, 1.0)
    half = width * _profile(profile, t)
    edge = half - np.abs(v)
    coverage = np.clip(edge + 0.5, 0.0, 1.0) * np.clip(u * length + 0.5, 0.0, 1.0) * np.clip((1.0 - u) * length + 0.5, 0.0, 1.0)
    if not np.any(coverage > 0.0):
        return
    ndotl = nx * LIGHT[0] + ny * LIGHT[1]
    shade = 1.0 + style.get("side_contrast", 0.12) * np.sign(v) * ndotl
    rib = np.where(np.abs(v) < np.maximum(0.6, style.get("midrib_width", 0.1) * half), style.get("midrib", 0.86), 1.0)
    rim = np.where(edge < style.get("outline_px", 1.1), style.get("outline", 0.74), 1.0)
    tip = 1.0 + style.get("tip_gain", 0.08) * (t - 0.5)
    cv.put(win, coverage, color * (shade * rib * rim * tip)[..., None])


def stroke(cv: Canvas, points, widths, colors, outline: float = 0.8, wrap: tuple = (False, False)) -> None:
    """Trait épais le long d'une ligne brisée (largeur et couleur interpolées), bouts arrondis, cerne léger."""
    pts = np.asarray(points, np.float32)
    wid = np.asarray(widths, np.float32)
    col = np.asarray(colors, np.float32)
    for ox, oy in _wrap_offsets(cv, wrap):
        _stroke(cv, pts + np.array([ox, oy], np.float32), wid, col, outline)


def _stroke(cv: Canvas, pts: np.ndarray, wid: np.ndarray, col: np.ndarray, outline: float) -> None:
    pad = float(wid.max()) + 2.0
    win = cv.window(pts[:, 0].min() - pad, pts[:, 1].min() - pad, pts[:, 0].max() + pad, pts[:, 1].max() + pad)
    if win is None:
        return
    px, py = win[4], win[5]
    best = np.full(px.shape, -1e9, np.float32)
    best_color = np.zeros(px.shape + (3,), np.float32)
    for i in range(len(pts) - 1):
        a = pts[i]
        b = pts[i + 1]
        ab = b - a
        denominator = float(ab[0] * ab[0] + ab[1] * ab[1]) or 1e-6
        t = np.clip(((px - a[0]) * ab[0] + (py - a[1]) * ab[1]) / denominator, 0.0, 1.0)
        qx = px - (a[0] + ab[0] * t)
        qy = py - (a[1] + ab[1] * t)
        edge = wid[i] + (wid[i + 1] - wid[i]) * t - np.sqrt(qx * qx + qy * qy)
        better = edge > best
        best = np.where(better, edge, best)
        segment_color = col[i][None, None, :] * (1.0 - t[..., None]) + col[i + 1][None, None, :] * t[..., None]
        best_color = np.where(better[..., None], segment_color, best_color)
    coverage = np.clip(best + 0.5, 0.0, 1.0)
    if not np.any(coverage > 0.0):
        return
    rim = np.where(best < 1.0, outline, 1.0)
    cv.put(win, coverage, best_color * rim[..., None])


def _wrap_offsets(cv: Canvas, wrap: tuple) -> list:
    xs = (0.0, -cv.w, cv.w) if wrap[0] else (0.0,)
    ys = (0.0, -cv.h, cv.h) if wrap[1] else (0.0,)
    return [(ox, oy) for ox in xs for oy in ys]


def periodic_noise(height: int, width: int, cells_y: int, cells_x: int, rng: np.random.Generator) -> np.ndarray:
    """Bruit de valeur périodique (raccord parfait sur les bords), lissé, de 0 à 1."""
    grid = rng.random((cells_y, cells_x)).astype(np.float32)
    fy = np.arange(height, dtype=np.float32) * cells_y / height
    fx = np.arange(width, dtype=np.float32) * cells_x / width
    y0 = np.floor(fy).astype(int) % cells_y
    x0 = np.floor(fx).astype(int) % cells_x
    y1 = (y0 + 1) % cells_y
    x1 = (x0 + 1) % cells_x
    ty = fy - np.floor(fy)
    tx = fx - np.floor(fx)
    ty = (ty * ty * (3.0 - 2.0 * ty))[:, None]
    tx = (tx * tx * (3.0 - 2.0 * tx))[None, :]
    top = grid[y0][:, x0] * (1.0 - tx) + grid[y0][:, x1] * tx
    bottom = grid[y1][:, x0] * (1.0 - tx) + grid[y1][:, x1] * tx
    return top * (1.0 - ty) + bottom * ty


def _jitter(rng: np.random.Generator, color, amount: float) -> np.ndarray:
    """Variation de valeur (et légère variation de teinte) d'une couleur de détail."""
    base = np.asarray(color, np.float32)
    value = 1.0 + rng.uniform(-amount, amount)
    hue = 1.0 + rng.uniform(-amount * 0.35, amount * 0.35, 3)
    return base * value * hue.astype(np.float32)


# ---------------------------------------------------------------------------------------------------------------------
# Tuiles
# ---------------------------------------------------------------------------------------------------------------------


def paint_neutral(cv: Canvas, spec: dict, rng: np.random.Generator) -> None:
    cv.rgb[:] = 1.0
    cv.a[:] = 1.0


def _frond_leaflets(cv: Canvas, path: np.ndarray, spec: dict, rng: np.random.Generator, scale: float, sides: tuple, foreshorten: float, style: dict) -> None:
    """Folioles d'une palme le long de son rachis (path : points de la base à la pointe) : épines à la base, folioles
    longues au milieu, plus courtes vers la pointe ; chaque côté en V vers l'avant."""
    seg = np.diff(path, axis=0)
    seg_len = np.sqrt((seg**2).sum(axis=1))
    cumulative = np.concatenate([[0.0], np.cumsum(seg_len)])
    total = float(cumulative[-1])
    count = int(spec["leaflets_per_side"])
    spine = float(spec["spine_fraction"])
    angle = math.radians(spec["leaflet_angle_deg"])
    for side in sides:
        for k in range(count):
            s = (k + rng.uniform(0.1, 0.9)) / count
            distance = s * total
            index = min(int(np.searchsorted(cumulative, distance, side="right")) - 1, len(seg) - 1)
            local = (distance - cumulative[index]) / max(seg_len[index], 1e-6)
            point = path[index] + seg[index] * local
            heading = math.atan2(seg[index][1], seg[index][0])
            spread = angle + rng.uniform(-0.12, 0.12)
            direction = heading + side * spread
            if s < spine:
                length = spec["spine_length_px"] * scale * rng.uniform(0.6, 1.1)
                leaf(cv, point[0], point[1], direction, length, 1.3 * scale, _jitter(rng, spec["spine_color"], 0.08), "needle", style)
                continue
            u = (s - spine) / (1.0 - spine)
            length = spec["leaflet_length_px"] * scale * (0.45 + 0.55 * math.sin(math.pi * (0.25 + 0.75 * u))) * rng.uniform(0.85, 1.1)
            length *= 1.0 - foreshorten * rng.uniform(0.0, 1.0)
            color = spec["leaflet_tip_color"] if rng.random() < spec["dry_ratio"] else spec["leaflet_color"]
            leaf(cv, point[0], point[1], direction, length, spec["leaflet_width_px"] * scale, _jitter(rng, color, 0.1), "lanceolate", style)
    widths = np.linspace(spec["rachis_width_px"] * scale, spec["rachis_width_px"] * scale * 0.35, len(path))
    stroke(cv, path, widths, [spec["rachis_color"]] * len(path), outline=0.78)


def paint_frond(cv: Canvas, spec: dict, rng: np.random.Generator) -> None:
    """Palme de dattier, rachis horizontal au milieu de la tuile (base à gauche), folioles en haut et en bas."""
    margin = 8.0
    xs = np.linspace(margin, cv.w - margin, 24)
    path = np.stack([xs, np.full_like(xs, cv.h * 0.5)], axis=1)
    _frond_leaflets(cv, path, spec, rng, 1.0, (-1, 1), 0.0, spec["style"])


def paint_crown_palm(cv: Canvas, spec: dict, frond: dict, rng: np.random.Generator) -> None:
    """Couronne de dattier vue de face (imposteur) : palmes arquées qui retombent, celles de derrière plus sombres."""
    center = np.array([cv.w * 0.5, cv.h * spec["center_y"]], np.float32)
    count = int(spec["fronds"])
    fronds = []
    for k in range(count):
        # Angle dans le plan de l'image (0 = à droite), profondeur pour l'ordre de peinture et la valeur.
        theta = math.pi * (k + rng.uniform(0.2, 0.8)) / count
        side = 1.0 if math.cos(theta) >= 0.0 else -1.0
        depth = rng.uniform(0.0, 1.0)
        fronds.append((depth, theta, side))
    fronds.sort()
    for depth, theta, side in fronds:
        length = cv.w * spec["length_frac"] * rng.uniform(0.8, 1.05) * (0.75 + 0.25 * abs(math.cos(theta)))
        rise = math.sin(theta) * spec["rise"]
        points = []
        for i in range(14):
            s = i / 13
            x = math.cos(theta) * length * s
            y = -rise * length * s + spec["droop"] * length * s * s
            points.append(center + np.array([x, y], np.float32))
        path = np.array(points, np.float32)
        value = spec["back_value"] + (1.0 - spec["back_value"]) * depth
        local = dict(frond)
        local["leaflet_color"] = [c * value for c in frond["leaflet_color"]]
        local["leaflet_tip_color"] = [c * value for c in frond["leaflet_tip_color"]]
        local["rachis_color"] = [c * value for c in frond["rachis_color"]]
        local["leaflets_per_side"] = spec["leaflets_per_side"]
        _frond_leaflets(cv, path, local, rng, spec["scale"], (-1, 1), 0.35, frond["style"])


def paint_bark_palm(cv: Canvas, spec: dict, rng: np.random.Generator) -> None:
    """Stipe de dattier : rangées décalées de bases de palmes coupées (« kornaf ») sur un fond fibreux, raccord parfait."""
    fibers = periodic_noise(cv.h, cv.w, 64, 6, rng)
    base = np.asarray(spec["fiber_color"], np.float32)
    cv.rgb[:] = base * (0.8 + 0.35 * fibers)[..., None]
    cv.a[:] = 1.0
    rows = int(spec["rows"])
    per_row = int(spec["per_row"])
    row_h = cv.h / rows
    for r in range(rows):
        for k in range(per_row):
            x = (k + 0.5 * (r % 2) + rng.uniform(-0.08, 0.08)) * cv.w / per_row
            y = (r + 0.85) * row_h
            width = cv.w / per_row * 0.5 * rng.uniform(0.85, 1.05)
            height = row_h * rng.uniform(1.05, 1.25)
            color = _jitter(rng, spec["base_color"], 0.08)
            # Base de palme : écaille en forme de bouclier, pointe vers le haut, ombre portée sous elle.
            stroke(cv, [[x, y + 3.0], [x, y + 6.0]], [width * 0.9, width * 0.8], [spec["shadow_color"]] * 2, outline=1.0, wrap=(True, True))
            leaf(cv, x, y, -math.pi / 2, height, width, color, "oblong", spec["style"], wrap=(True, True))


def paint_bark_tree(cv: Canvas, spec: dict, rng: np.random.Generator) -> None:
    """Écorce d'arbre : bandes verticales irrégulières et fissures sombres sinueuses, raccord parfait."""
    coarse = periodic_noise(cv.h, cv.w, 6, 10, rng)
    fine = periodic_noise(cv.h, cv.w, 48, 40, rng)
    base = np.asarray(spec["base_color"], np.float32)
    cv.rgb[:] = base * (0.82 + 0.25 * coarse + 0.12 * fine)[..., None]
    cv.a[:] = 1.0
    for k in range(int(spec["fissures"])):
        x = rng.uniform(0, cv.w)
        y = rng.uniform(0, cv.h)
        length = rng.uniform(0.25, 0.6) * cv.h
        points = []
        for i in range(10):
            points.append([x + math.sin(i * 0.9 + k) * rng.uniform(2.0, 6.0), y + length * i / 9])
        widths = [spec["fissure_width_px"] * rng.uniform(0.6, 1.2) * math.sin(math.pi * (i + 0.5) / 10) for i in range(10)]
        stroke(cv, points, widths, [spec["fissure_color"]] * 10, outline=1.0, wrap=(True, True))
    for k in range(int(spec["highlights"])):
        x = rng.uniform(0, cv.w)
        y = rng.uniform(0, cv.h)
        length = rng.uniform(0.1, 0.25) * cv.h
        stroke(cv, [[x, y], [x + rng.uniform(-3, 3), y + length]], [2.5, 1.0], [spec["highlight_color"]] * 2, outline=1.0, wrap=(True, True))


def _cluster_leaf(cv: Canvas, x: float, y: float, angle: float, spec: dict, rng: np.random.Generator, value: float) -> None:
    kind = spec["leaf"]
    style = spec["style"]
    length = spec["leaf_length_px"] * rng.uniform(0.75, 1.15)
    width = spec["leaf_width_px"] * rng.uniform(0.85, 1.1)
    color = spec["leaf_color"]
    if "underside_color" in spec and rng.random() < spec["underside_ratio"]:
        color = spec["underside_color"]
    color = _jitter(rng, color, spec.get("leaf_jitter", 0.1)) * value
    if kind in ("lanceolate", "oblong", "round"):
        leaf(cv, x, y, angle, length, width, color, kind, style)
    elif kind == "palmate":
        # Feuille de figuier : trois à cinq lobes arrondis autour d'un même point.
        lobes = int(rng.integers(3, 6))
        for i in range(lobes):
            offset = (i - (lobes - 1) / 2) * spec["lobe_spread_rad"]
            scale = 1.0 - 0.28 * abs(i - (lobes - 1) / 2)
            leaf(cv, x, y, angle + offset, length * scale, width * scale, color * (1.0 - 0.04 * i), "oblong", style)
    elif kind == "pinnate":
        # Feuille composée d'acacia : petit rachis et folioles minuscules de part et d'autre.
        dx, dy = math.cos(angle), math.sin(angle)
        stroke(cv, [[x, y], [x + dx * length, y + dy * length]], [1.0, 0.6], [spec["twig_color"]] * 2, outline=1.0)
        count = int(spec["leaflets"])
        for i in range(count):
            s = (i + 0.5) / count
            px = x + dx * length * s
            py = y + dy * length * s
            for side in (-1.0, 1.0):
                leaf(cv, px, py, angle + side * 1.2, width, width * 0.45, color * rng.uniform(0.9, 1.08), "round", style)
    elif kind == "plume":
        # Rameau plumeux de tamaris : tige fine qui retombe, couverte de minuscules écailles.
        points = []
        for i in range(8):
            s = i / 7
            points.append([x + math.cos(angle) * length * s, y + math.sin(angle) * length * s + spec["plume_droop"] * length * s * s])
        points = np.array(points, np.float32)
        stroke(cv, points, np.linspace(width * 0.5, width * 0.25, 8), [color * 0.85] * 8, outline=0.85)
        for i in range(int(spec["leaflets"])):
            s = rng.uniform(0.1, 1.0)
            index = min(int(s * 7), 6)
            local = s * 7 - index
            p = points[index] * (1.0 - local) + points[index + 1] * local
            leaf(cv, p[0], p[1], angle + rng.uniform(-1.2, 1.2), width * rng.uniform(0.8, 1.4), width * 0.4, color * rng.uniform(0.9, 1.15), "round", style)
    else:
        raise ValueError(f"type de feuille inconnu : {kind}")


def paint_cluster(cv: Canvas, spec: dict, rng: np.random.Generator) -> None:
    """Rameau feuillu (grappe de feuilles sur ses brindilles), dans une silhouette ovale irrégulière : sert de carte de
    feuillage aux couronnes d'arbres et aux buissons, et d'imposteur lointain."""
    origin = np.array([cv.w * 0.5, cv.h * spec["origin_y"]], np.float32)
    center = np.array([cv.w * 0.5, cv.h * spec["center_y"]], np.float32)
    rx = cv.w * spec["radius_x"]
    ry = cv.h * spec["radius_y"]
    # Points d'attache des feuilles, tirés dans l'ovale (densité plus forte vers le bord : silhouette pleine mais ajourée).
    count = int(spec["leaves"])
    anchors = []
    for _ in range(count):
        a = rng.uniform(0, 2 * math.pi)
        r = math.sqrt(rng.uniform(0.05, 1.0)) * rng.uniform(0.75, 1.0)
        wobble = 1.0 + spec.get("edge_wobble", 0.15) * math.sin(a * 5.0 + spec.get("seed_phase", 0.0))
        anchors.append(center + np.array([math.cos(a) * rx * r * wobble, math.sin(a) * ry * r * wobble], np.float32))
    # Brindilles : de l'origine vers une partie des attaches, en deux segments légèrement coudés.
    twig_color = spec["twig_color"]
    for i in range(int(spec["twigs"])):
        target = anchors[int(rng.integers(0, count))]
        mid = origin * 0.5 + target * 0.5 + rng.uniform(-0.12, 0.12, 2).astype(np.float32) * np.array([rx, ry], np.float32)
        width = spec["twig_width_px"] * rng.uniform(0.7, 1.1)
        stroke(cv, [origin, mid, target], [width, width * 0.7, width * 0.35], [twig_color] * 3, outline=0.8)
        if spec.get("thorns", 0) > 0:
            for _ in range(int(spec["thorns"])):
                s = rng.uniform(0.2, 0.95)
                p = mid * s + target * (1.0 - s) if s > 0.5 else origin * (1.0 - 2 * s) + mid * (2 * s)
                direction = math.atan2(target[1] - origin[1], target[0] - origin[0]) + rng.choice([-1.0, 1.0]) * rng.uniform(0.6, 1.1)
                leaf(cv, p[0], p[1], direction, spec["thorn_length_px"], 1.2, spec["thorn_color"], "needle", spec["style"])
    # Feuilles : d'arrière en avant (les premières, plus sombres, font la profondeur).
    order = list(range(count))
    rng.shuffle(order)
    for rank, i in enumerate(order):
        p = anchors[i]
        outward = math.atan2(p[1] - origin[1], p[0] - origin[0])
        angle = outward + rng.uniform(-spec["angle_spread_rad"], spec["angle_spread_rad"])
        depth = rank / max(count - 1, 1)
        value = spec["back_value"] + (1.0 - spec["back_value"]) * depth
        # Imposteurs : le bas de la couronne, dans l'ombre, est plus sombre que le haut éclairé.
        value *= 1.0 - spec.get("vertical_shade", 0.0) * max(-1.0, min(1.0, (p[1] - center[1]) / max(ry, 1.0)))
        _cluster_leaf(cv, p[0], p[1], angle, spec, rng, value)


def paint_tuft(cv: Canvas, spec: dict, rng: np.random.Generator) -> None:
    """Touffe de brins (herbes, roseaux, joncs, céréales, genêt) dressée depuis le bas de la tuile, avec ses épis."""
    base_y = cv.h - 4.0
    count = int(spec["blades"])
    blades = []
    for _ in range(count):
        root_x = cv.w * 0.5 + rng.uniform(-1.0, 1.0) * cv.w * spec["root_spread"]
        lean = rng.uniform(-1.0, 1.0) * spec["lean"]
        height = cv.h * rng.uniform(spec["height_min"], spec["height_max"])
        blades.append((rng.uniform(0, 1), root_x, lean, height))
    blades.sort()
    for depth, root_x, lean, height in blades:
        bend = spec["bend"] * rng.uniform(0.5, 1.2) * (1.0 if lean >= 0 else -1.0)
        points = []
        steps = 10
        for i in range(steps + 1):
            s = i / steps
            x = root_x + lean * cv.w * 0.5 * s + bend * cv.w * 0.5 * s * s
            y = base_y - height * s + spec.get("droop", 0.0) * height * s * s * abs(lean)
            points.append([x, y])
        points = np.array(points, np.float32)
        value = spec["back_value"] + (1.0 - spec["back_value"]) * depth
        width = spec["blade_width_px"] * rng.uniform(0.8, 1.2)
        widths = width * np.power(np.linspace(1.0, 0.0, steps + 1), spec.get("taper", 0.8)) + 0.45
        colors = [(_jitter(rng, spec["base_color"], 0.06) * (1.0 - s) + np.asarray(spec["tip_color"], np.float32) * s) * value for s in np.linspace(0, 1, steps + 1)]
        stroke(cv, points, widths, colors, outline=spec["style"].get("outline", 0.75))
        head = spec.get("head", "")
        if head and rng.random() < spec.get("head_ratio", 1.0):
            _paint_head(cv, head, points, spec, rng, value)
        for _ in range(int(spec.get("side_leaves", 0))):
            s = rng.uniform(0.15, 0.7)
            index = int(s * steps)
            p = points[index]
            angle = math.atan2(points[index + 1][1] - p[1], points[index + 1][0] - p[0]) + rng.choice([-1.0, 1.0]) * rng.uniform(0.35, 0.8)
            color = _jitter(rng, spec["leaf_color"], 0.08) * value
            leaf(cv, p[0], p[1], angle, spec["leaf_length_px"] * rng.uniform(0.7, 1.1), spec["leaf_width_px"], color, spec.get("leaf_profile", "blade"), spec["style"])


def _paint_head(cv: Canvas, head: str, points: np.ndarray, spec: dict, rng: np.random.Generator, value: float) -> None:
    tip = points[-1]
    direction = math.atan2(points[-1][1] - points[-3][1], points[-1][0] - points[-3][0])
    color = np.asarray(spec["head_color"], np.float32) * value
    style = spec["style"]
    if head == "panicle":
        # Panicule de roseau : nuage de fins rameaux duveteux qui penchent.
        for _ in range(int(spec["head_strands"])):
            s = rng.uniform(0.0, 1.0)
            start = points[-4] * (1.0 - s) + tip * s
            angle = direction + rng.uniform(-0.7, 0.7)
            length = spec["head_length_px"] * rng.uniform(0.4, 1.0)
            leaf(cv, start[0], start[1], angle, length, 2.2, color * rng.uniform(0.85, 1.15), "needle", style)
    elif head == "ear":
        # Épi d'orge : grains en chevrons serrés et longues barbes.
        length = spec["head_length_px"]
        for i in range(int(spec["head_strands"])):
            s = i / max(spec["head_strands"] - 1, 1)
            p = tip + np.array([math.cos(direction), math.sin(direction)], np.float32) * (length * (s - 1.0))
            for side in (-1.0, 1.0):
                leaf(cv, p[0], p[1], direction + side * 0.45, 7.0, 3.0, color * rng.uniform(0.9, 1.1), "oblong", style)
                leaf(cv, p[0], p[1], direction + side * 0.18, spec["awn_length_px"], 0.8, color * 1.08, "needle", style)
    elif head == "cluster":
        # Inflorescence de jonc : petite grappe brune sur le côté, un peu sous la pointe.
        p = points[-3]
        for _ in range(int(spec["head_strands"])):
            leaf(cv, p[0], p[1], direction + rng.uniform(0.6, 2.2), spec["head_length_px"] * rng.uniform(0.5, 1.0), 2.4, color * rng.uniform(0.85, 1.1), "oblong", style)
    elif head == "feather":
        # Drinn : épi plumeux clair au bout du brin.
        for _ in range(int(spec["head_strands"])):
            s = rng.uniform(0.4, 1.0)
            p = points[-4] * (1.0 - s) + tip * s
            leaf(cv, p[0], p[1], direction + rng.uniform(-0.5, 0.5), spec["head_length_px"] * rng.uniform(0.4, 1.0), 1.6, color * rng.uniform(0.95, 1.12), "needle", style)
    elif head == "flowers":
        # Petites fleurs (genêt, fève) portées le long de l'extrémité.
        for _ in range(int(spec["head_strands"])):
            s = rng.uniform(0.5, 1.0)
            index = min(int(s * (len(points) - 1)), len(points) - 2)
            p = points[index]
            leaf(cv, p[0], p[1], direction + rng.choice([-1.0, 1.0]) * rng.uniform(0.6, 1.4), spec["head_length_px"], spec["head_length_px"] * 0.45, color * rng.uniform(0.95, 1.08), "round", style)
    else:
        raise ValueError(f"type d'épi inconnu : {head}")


def paint_sprites(cv: Canvas, spec: dict, rng: np.random.Generator) -> None:
    """Planche de petits motifs (2 x 2) : fruit rond, grappe d'olives, fleur à cinq pétales, fleur des champs."""
    half_w = cv.w / 2
    half_h = cv.h / 2
    style = spec["style"]
    for index, sprite in enumerate(spec["order"]):
        ox = (index % 2) * half_w
        oy = (index // 2) * half_h
        cx = ox + half_w * 0.5
        cy = oy + half_h * 0.5
        radius = half_w * 0.36
        color = np.asarray(spec["color"], np.float32)
        if sprite == "fruit":
            leaf(cv, cx, cy + radius, -math.pi / 2, radius * 2.0, radius, color, "round", dict(style, side_contrast=0.25))
            leaf(cv, cx - radius * 0.35, cy - radius * 0.3, -math.pi / 2, radius * 0.5, radius * 0.22, color * 1.35, "round", style)
            for k in range(5):
                leaf(cv, cx, cy - radius * 0.85, -math.pi / 2 + (k - 2) * 0.35, radius * 0.38, radius * 0.12, color * 0.7, "needle", style)
        elif sprite == "olives":
            for k in range(3):
                angle = -math.pi / 2 + (k - 1) * 0.7
                x = cx + math.cos(angle + math.pi) * radius * 0.4 * (k - 1)
                y = cy + radius * 0.3 * (1 - abs(k - 1))
                leaf(cv, x, y + radius * 0.45, angle, radius * 0.9, radius * 0.32, color * (0.92 + 0.06 * k), "round", dict(style, side_contrast=0.3))
        elif sprite == "five_petals":
            for k in range(5):
                angle = k * 2 * math.pi / 5 + 0.3
                leaf(cv, cx, cy, angle, radius, radius * 0.42, color * (0.95 + 0.03 * k), "oblong", style)
            leaf(cv, cx, cy + radius * 0.15, -math.pi / 2, radius * 0.3, radius * 0.15, color * 0.6, "round", style)
        elif sprite == "daisy":
            for k in range(11):
                angle = k * 2 * math.pi / 11
                leaf(cv, cx, cy, angle, radius, radius * 0.17, color * (0.94 + 0.012 * k), "oblong", style)
            leaf(cv, cx, cy + radius * 0.28, -math.pi / 2, radius * 0.56, radius * 0.28, color * 0.62, "round", dict(style, side_contrast=0.2))
        else:
            raise ValueError(f"motif inconnu : {sprite}")


# ---------------------------------------------------------------------------------------------------------------------
# Assemblage et écriture
# ---------------------------------------------------------------------------------------------------------------------


def _finish_tile(cv: Canvas, dilate: int) -> tuple:
    """Couleurs non prémultipliées ; les pixels transparents reçoivent la couleur voisine (dilatation) puis la couleur
    moyenne de la tuile, pour que les niveaux de mipmap ne fassent pas apparaître de liseré sombre."""
    alpha = cv.a.copy()
    rgb = np.where(alpha[..., None] > 1e-4, cv.rgb / np.maximum(alpha[..., None], 1e-4), 0.0)
    known = alpha > 0.02
    if known.any():
        mean = rgb[known].mean(axis=0)
    else:
        mean = np.ones(3, np.float32)
    filled = known.copy()
    for _ in range(dilate):
        if filled.all():
            break
        accum = np.zeros_like(rgb)
        weight = np.zeros(alpha.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            shifted = np.roll(filled, (dy, dx), axis=(0, 1))
            accum += np.roll(rgb, (dy, dx), axis=(0, 1)) * shifted[..., None]
            weight += shifted
        grow = (~filled) & (weight > 0)
        rgb[grow] = accum[grow] / weight[grow][..., None]
        filled |= grow
    rgb[~filled] = mean
    return rgb, alpha


def build_atlas(spec: dict) -> tuple:
    """Peint l'atlas décrit par spec ; renvoie (tableau RVBA uint8, rectangles UV par tuile, rectangles en pixels).

    Les rectangles UV (u0, v0, u1, v1, origine en haut à gauche de l'image) sont rentrés d'un demi-texel du niveau
    de mipmap « inset_mip » pour limiter le débordement entre tuiles voisines."""
    size = int(spec["size_px"])
    unit = int(spec["tile_px"])
    image = np.zeros((size, size, 4), np.float32)
    occupied = np.zeros((size // unit, size // unit), bool)
    rects = {}
    rects_px = []
    rng_root = np.random.default_rng(int(spec["seed"]))
    tiles = spec["tiles"]
    for name in sorted(tiles):
        tile = tiles[name]
        col, row, w, h = tile["rect"]
        if occupied[row : row + h, col : col + w].any():
            raise ValueError(f"atlas : la tuile {name} chevauche une autre tuile")
        occupied[row : row + h, col : col + w] = True
        cv = Canvas(w * unit, h * unit)
        rng = np.random.default_rng(int(rng_root.integers(0, 2**31)) + sum(ord(c) for c in name))
        kind = tile["kind"]
        if kind == "neutral":
            paint_neutral(cv, tile, rng)
        elif kind == "frond":
            paint_frond(cv, tile, rng)
        elif kind == "crown_palm":
            paint_crown_palm(cv, tile, tiles[tile["frond"]], rng)
        elif kind == "bark_palm":
            paint_bark_palm(cv, tile, rng)
        elif kind == "bark_tree":
            paint_bark_tree(cv, tile, rng)
        elif kind == "cluster":
            paint_cluster(cv, tile, rng)
        elif kind == "tuft":
            paint_tuft(cv, tile, rng)
        elif kind == "sprites":
            paint_sprites(cv, tile, rng)
        else:
            raise ValueError(f"atlas : type de tuile inconnu {kind}")
        rgb, alpha = _finish_tile(cv, int(spec["dilate_px"]))
        x0 = col * unit
        y0 = row * unit
        image[y0 : y0 + h * unit, x0 : x0 + w * unit, :3] = rgb
        image[y0 : y0 + h * unit, x0 : x0 + w * unit, 3] = alpha
        rects_px.append((x0, y0, x0 + w * unit, y0 + h * unit))
        inset = 0.5 * (2 ** int(spec["inset_mip"])) / size
        rects[name] = (x0 / size + inset, y0 / size + inset, (x0 + w * unit) / size - inset, (y0 + h * unit) / size - inset)
    # Valeurs de détail : 1,0 (couleur de sommet inchangée) est stocké à 0,5.
    pixels = np.empty((size, size, 4), np.uint8)
    pixels[..., :3] = np.clip(np.round(image[..., :3] * 0.5 * 255.0), 0, 255).astype(np.uint8)
    pixels[..., 3] = np.clip(np.round(image[..., 3] * 255.0), 0, 255).astype(np.uint8)
    return pixels, rects, rects_px


def coverage_mips(pixels: np.ndarray, rects_px: list, threshold: float) -> list:
    """Chaîne de mipmaps qui conserve la couverture de l'alpha (méthode de Castaño) : à chaque niveau, l'alpha de chaque
    tuile est mis à l'échelle pour que la part de texels au-dessus du seuil de découpe reste celle du niveau 0. Sans
    cela, la moyenne des niveaux réduits fait fondre feuillages et herbes au loin (alpha scissor)."""
    levels = [pixels.astype(np.float32) / 255.0]
    targets = []
    for x0, y0, x1, y1 in rects_px:
        targets.append(float((levels[0][y0:y1, x0:x1, 3] > threshold).mean()))
    size = pixels.shape[0]
    level = 0
    while size > 1:
        previous = levels[-1]
        half = (previous[0::2, 0::2] + previous[1::2, 0::2] + previous[0::2, 1::2] + previous[1::2, 1::2]) * 0.25
        level += 1
        for (x0, y0, x1, y1), target in zip(rects_px, targets):
            sx0, sy0 = x0 >> level, y0 >> level
            sx1, sy1 = max(x1 >> level, sx0 + 1), max(y1 >> level, sy0 + 1)
            alpha = half[sy0:sy1, sx0:sx1, 3]
            if target <= 0.0 or target >= 1.0:
                continue
            low, high = 0.0, 8.0
            for _ in range(20):
                scale = 0.5 * (low + high)
                if float((alpha * scale > threshold).mean()) < target:
                    low = scale
                else:
                    high = scale
            half[sy0:sy1, sx0:sx1, 3] = np.clip(alpha * high, 0.0, 1.0)
        levels.append(half)
        size //= 2
    return [np.clip(np.round(level * 255.0), 0, 255).astype(np.uint8) for level in levels]


def _encode_bc3(image: np.ndarray) -> bytes:
    """Compression BC3 (DXT5) d'un niveau RVBA 8 bits : couleurs sur l'axe principal de chaque bloc 4 x 4 (565, quatre
    teintes), alpha sur huit niveaux entre le minimum et le maximum du bloc. Entièrement vectorisé."""
    height, width = image.shape[:2]
    padded = np.pad(image, ((0, (-height) % 4), (0, (-width) % 4), (0, 0)), mode="edge")
    bh, bw = padded.shape[0] // 4, padded.shape[1] // 4
    blocks = padded.reshape(bh, 4, bw, 4, 4).transpose(0, 2, 1, 3, 4).reshape(bh * bw, 16, 4).astype(np.float32)
    # Alpha : extrêmes du bloc, huit niveaux (a0 > a1), index de 3 bits.
    alpha = blocks[:, :, 3]
    a0 = alpha.max(axis=1)
    a1 = alpha.min(axis=1)
    a0i = np.round(a0).astype(np.int32)
    a1i = np.round(a1).astype(np.int32)
    weights = np.array([0, 7, 1, 2, 3, 4, 5, 6], np.float32)  # part de a1 sur 7 pour les index 0..7
    palette = (a0i[:, None] * (7 - weights)[None, :] + a1i[:, None] * weights[None, :]) / 7.0
    alpha_index = np.abs(alpha[:, :, None] - palette[:, None, :]).argmin(axis=2).astype(np.uint64)
    alpha_index[a0i == a1i] = 0
    alpha_bits = np.zeros(len(blocks), np.uint64)
    for i in range(16):
        alpha_bits |= alpha_index[:, i] << np.uint64(3 * i)
    # Couleur : axe principal par itération de puissance, extrêmes projetés, quantification 565.
    rgb = blocks[:, :, :3]
    mean = rgb.mean(axis=1)
    centered = rgb - mean[:, None, :]
    cov = np.einsum("bni,bnj->bij", centered, centered)
    axis = np.ones((len(blocks), 3), np.float32)
    for _ in range(6):
        axis = np.einsum("bij,bj->bi", cov, axis)
        norm = np.linalg.norm(axis, axis=1, keepdims=True)
        axis = np.where(norm > 1e-6, axis / np.maximum(norm, 1e-6), np.array([0.577, 0.577, 0.577], np.float32))
    projection = np.einsum("bni,bi->bn", centered, axis)
    c_max = np.clip(mean + axis * projection.max(axis=1, keepdims=True), 0, 255)
    c_min = np.clip(mean + axis * projection.min(axis=1, keepdims=True), 0, 255)

    def to565(c: np.ndarray) -> np.ndarray:
        r = np.round(c[:, 0] * 31 / 255).astype(np.uint32)
        g = np.round(c[:, 1] * 63 / 255).astype(np.uint32)
        b = np.round(c[:, 2] * 31 / 255).astype(np.uint32)
        return (r << 11) | (g << 5) | b

    def from565(v: np.ndarray) -> np.ndarray:
        return np.stack([((v >> 11) & 31) * 255.0 / 31, ((v >> 5) & 63) * 255.0 / 63, (v & 31) * 255.0 / 31], axis=1).astype(np.float32)

    e0 = to565(c_max)
    e1 = to565(c_min)
    swap = e0 < e1
    e0, e1 = np.where(swap, e1, e0), np.where(swap, e0, e1)
    p0 = from565(e0)
    p1 = from565(e1)
    colors = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], axis=1)
    distance = ((rgb[:, :, None, :] - colors[:, None, :, :]) ** 2).sum(axis=3)
    color_index = distance.argmin(axis=2).astype(np.uint32)
    color_index[e0 == e1] = 0
    color_bits = np.zeros(len(blocks), np.uint32)
    for i in range(16):
        color_bits |= color_index[:, i] << np.uint32(2 * i)
    out = np.zeros((len(blocks), 16), np.uint8)
    out[:, 0] = a0i.astype(np.uint8)
    out[:, 1] = a1i.astype(np.uint8)
    out[:, 2:8] = alpha_bits[:, None].view(np.uint8).reshape(-1, 8)[:, :6]
    out[:, 8:10] = e0.astype("<u2")[:, None].view(np.uint8).reshape(-1, 2)
    out[:, 10:12] = e1.astype("<u2")[:, None].view(np.uint8).reshape(-1, 2)
    out[:, 12:16] = color_bits.astype("<u4")[:, None].view(np.uint8).reshape(-1, 4)
    return out.tobytes()


def write_dds_bc3(path: str, levels: list) -> None:
    """Fichier DDS compressé BC3 (DXT5) avec sa chaîne de mipmaps : Godot la garde telle quelle à l'import."""
    height, width = levels[0].shape[:2]
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000
    linear_size = max(1, (width + 3) // 4) * max(1, (height + 3) // 4) * 16
    pixel_format = struct.pack("<II4sIIIII", 32, 0x4, b"DXT5", 0, 0, 0, 0, 0)
    caps = struct.pack("<IIIII", 0x1000 | 0x400000 | 0x8, 0, 0, 0, 0)
    header = struct.pack("<4sIIIIIII", b"DDS ", 124, flags, height, width, linear_size, 0, len(levels)) + b"\0" * 44 + pixel_format + caps
    with open(path, "wb") as handle:
        handle.write(header)
        for level in levels:
            handle.write(_encode_bc3(level))
