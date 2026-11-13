"""Circuit d'Alès : calcule les masques de tuiles et les éléments de course.

Entrée  : level/track/ales/ales_circuit_osm.csv (tracé OpenStreetMap, mètres)
Sortie  : level/track/ales/build/
            - asphalt.png, gravel.png, kerb.png, barrier.png, pit.png
              (1 pixel = 1 tuile de 32 px ; blanc = tuile présente)
            - kerb_dir.png (orientation des vibreurs : 0 vertical, 255 horizontal)
            - track.json (origine de la grille, sections, grille de départ,
              ligne de départ, zone de stand)

Usage : python3 -I tools/track/make_ales_masks.py <racine du projet>
Le script Godot tools/track/build_ales_track.gd construit ensuite la scène.
"""
import csv
import json
import math
import os
import sys

from PIL import Image, ImageDraw

# ------------------------------------------------------------
# Paramètres (échelle réelle du jeu)
# ------------------------------------------------------------
PX_PER_M = 34.0          # une voiture de ~4,2 m mesure ~141 px
TILE = 32                # taille des tuiles de sol
TRACK_WIDTH_M = 13.0     # largeur officielle de la piste
PIT_WIDTH_M = 9.0        # voie des stands
GRAVEL_RUNOFF_M = 22.0   # bac à graviers à l'extérieur des virages
BARRIER_DIST_M = 32.0    # barrière de pneus : distance au bord de piste
CORNER_WINDOW_M = 25.0   # fenêtre de calcul de la courbure
CORNER_ANGLE_DEG = 30.0  # changement de cap au-delà duquel c'est un virage
SECTION_COUNT = 14
GATE_MARGIN_M = 2.0      # la porte dépasse un peu de chaque côté
MARGIN_TILES = 40        # herbe autour du site

MAIN_WAY = "196899326"   # tracé principal, sens horaire (sens de course)
PIT_WAY = "196899365"    # voie des stands
START_INDEX = 1          # nœud OSM ligne de départ / arrivée


def load_ways(csv_path):
    ways = {}
    with open(csv_path, newline="") as f:
        for row in csv.DictReader(f):
            ways.setdefault(row["way_id"], []).append(
                (float(row["x_east_m"]), float(row["y_north_m"]))
            )
    return ways


def to_world(point):
    """Mètres (x est, y nord) -> pixels du jeu (x droite, y bas)."""
    return (point[0] * PX_PER_M, -point[1] * PX_PER_M)


def resample(points, step, closed):
    """Points régulièrement espacés de `step` le long de la polyligne."""
    pts = list(points)
    if closed and pts[0] != pts[-1]:
        pts.append(pts[0])
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = math.dist(a, b)
        if seg == 0:
            continue
        d = step - carry
        while d <= seg:
            t = d / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            d += step
        carry = seg - (d - step)
    if closed and math.dist(out[0], out[-1]) < step * 0.5:
        out.pop()
    return out


def heading(points, i, closed):
    n = len(points)
    a = points[(i - 1) % n] if closed else points[max(i - 1, 0)]
    b = points[(i + 1) % n] if closed else points[min(i + 1, n - 1)]
    return math.atan2(b[1] - a[1], b[0] - a[0])


def angle_diff(a, b):
    return (b - a + math.pi) % (2 * math.pi) - math.pi


def main(root):
    src = os.path.join(root, "level/track/ales/ales_circuit_osm.csv")
    out_dir = os.path.join(root, "level/track/ales/build")
    os.makedirs(out_dir, exist_ok=True)

    ways = load_ways(src)
    main_m = ways[MAIN_WAY]
    if main_m[0] == main_m[-1]:
        main_m = main_m[:-1]

    # Départ au nœud de la ligne d'arrivée : on fait tourner la liste
    # pour que l'indice 0 soit sur la ligne.
    main_m = main_m[START_INDEX:] + main_m[:START_INDEX]

    step_px = 1.0 * PX_PER_M                     # un point par mètre
    center = resample([to_world(p) for p in main_m], step_px, True)
    pit = resample([to_world(p) for p in ways[PIT_WAY]], step_px, False)
    n = len(center)
    lap_px = n * step_px

    # ---- Grille de tuiles ----
    xs = [p[0] for p in center + pit]
    ys = [p[1] for p in center + pit]
    reach = (TRACK_WIDTH_M / 2 + BARRIER_DIST_M + 2) * PX_PER_M
    gx0 = int(math.floor((min(xs) - reach) / TILE)) - MARGIN_TILES
    gy0 = int(math.floor((min(ys) - reach) / TILE)) - MARGIN_TILES
    gx1 = int(math.ceil((max(xs) + reach) / TILE)) + MARGIN_TILES
    gy1 = int(math.ceil((max(ys) + reach) / TILE)) + MARGIN_TILES
    size = (gx1 - gx0, gy1 - gy0)

    def to_img(p):
        return (p[0] / TILE - gx0, p[1] / TILE - gy0)

    def thick_line(img, pts, width_px, closed, fill=255):
        d = ImageDraw.Draw(img)
        poly = [to_img(p) for p in pts]
        if closed:
            poly = poly + poly[:2]
        w = max(int(round(width_px / TILE)), 1)
        d.line(poly, fill=fill, width=w, joint="curve")
        r = w / 2
        for x, y in (poly[0], poly[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    track_w = TRACK_WIDTH_M * PX_PER_M

    # ---- Virages : changement de cap sur la fenêtre ----
    win = int(CORNER_WINDOW_M)
    headings = [heading(center, i, True) for i in range(n)]
    is_corner = []
    for i in range(n):
        turn = abs(angle_diff(headings[(i - win) % n], headings[(i + win) % n]))
        is_corner.append(math.degrees(turn) > CORNER_ANGLE_DEG)

    # Côté extérieur du virage : +1 = gauche du sens de marche, -1 = droite.
    def outside_side(i):
        turn = angle_diff(headings[(i - win) % n], headings[(i + win) % n])
        # Sur l'écran (y vers le bas), turn > 0 = virage à droite :
        # l'extérieur est à gauche.
        return 1 if turn > 0 else -1

    # ---- Masques ----
    asphalt = Image.new("L", size, 0)
    thick_line(asphalt, center, track_w, True)
    thick_line(asphalt, pit, PIT_WIDTH_M * PX_PER_M, False)

    gravel = Image.new("L", size, 0)
    gd = ImageDraw.Draw(gravel)
    for i in range(n):
        if not is_corner[i]:
            continue
        side = outside_side(i)
        h = headings[i]
        # normale gauche (écran) : (sin h, -cos h)
        nx, ny = math.sin(h), -math.cos(h)
        c = center[i]
        off = (track_w / 2 + GRAVEL_RUNOFF_M * PX_PER_M / 2) * side
        p = (c[0] + nx * off, c[1] + ny * off)
        r = GRAVEL_RUNOFF_M * PX_PER_M / 2 / TILE
        x, y = to_img(p)
        gd.ellipse([x - r, y - r, x + r, y + r], fill=255)

    barrier_outer = Image.new("L", size, 0)
    barrier_inner = Image.new("L", size, 0)
    bw = track_w + 2 * BARRIER_DIST_M * PX_PER_M
    thick_line(barrier_outer, center, bw + 2 * TILE, True)
    thick_line(barrier_inner, center, bw, True)
    thick_line(barrier_outer, pit, PIT_WIDTH_M * PX_PER_M + 2 * BARRIER_DIST_M * PX_PER_M + 2 * TILE, False)
    thick_line(barrier_inner, pit, PIT_WIDTH_M * PX_PER_M + 2 * BARRIER_DIST_M * PX_PER_M, False)

    a_px = asphalt.load()
    g_px = gravel.load()
    bo = barrier_outer.load()
    bi = barrier_inner.load()

    barrier = Image.new("L", size, 0)
    b_px = barrier.load()
    kerb = Image.new("L", size, 0)
    k_px = kerb.load()
    kerb_dir = Image.new("L", size, 0)
    kd_px = kerb_dir.load()

    # Pour l'orientation des vibreurs : point de tracé le plus proche.
    def nearest_index(x, y):
        wx, wy = (x + gx0 + 0.5) * TILE, (y + gy0 + 0.5) * TILE
        best, best_d = 0, float("inf")
        for i in range(0, n, 3):
            d = (center[i][0] - wx) ** 2 + (center[i][1] - wy) ** 2
            if d < best_d:
                best, best_d = i, d
        return best, math.sqrt(best_d)

    for y in range(size[1]):
        for x in range(size[0]):
            if bo[x, y] and not bi[x, y]:
                b_px[x, y] = 255
            if g_px[x, y] and a_px[x, y]:
                g_px[x, y] = 0
            if not a_px[x, y]:
                continue
            border = any(
                0 <= x + dx < size[0] and 0 <= y + dy < size[1] and not a_px[x + dx, y + dy]
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
            )
            if not border:
                continue
            i, dist = nearest_index(x, y)
            # Vibreurs : bords de la piste principale, dans les virages.
            if is_corner[i] and dist < track_w * 0.75:
                k_px[x, y] = 255
                h = headings[i]
                kd_px[x, y] = 0 if abs(math.sin(h)) > abs(math.cos(h)) else 255

    # ---- Sections (portes perpendiculaires au tracé) ----
    sections = []
    half_gate = track_w / 2 + GATE_MARGIN_M * PX_PER_M
    for k in range(SECTION_COUNT):
        i = int(round(k * n / SECTION_COUNT)) % n
        h = headings[i]
        nx, ny = math.sin(h), -math.cos(h)
        c = center[i]
        sections.append({
            "id": k,
            "center": c,
            "a": (c[0] + nx * half_gate, c[1] + ny * half_gate),
            "b": (c[0] - nx * half_gate, c[1] - ny * half_gate),
            "heading": h,
        })

    # ---- Grille de départ (quinconce, derrière la ligne) ----
    h0 = headings[0]
    fx, fy = math.cos(h0), math.sin(h0)
    lx, ly = math.sin(h0), -math.cos(h0)
    spawns = []
    for slot in range(8):
        back = 150 + slot * 190
        side = 110 if slot % 2 == 0 else -110
        c = center[0]
        spawns.append({
            "pos": (c[0] - fx * back + lx * side, c[1] - fy * back + ly * side),
            "heading": h0,
        })

    # ---- Zone de stand : milieu de la voie des stands ----
    m = len(pit) // 2
    ph = heading(pit, m, False)
    pit_zone = {
        "center": pit[m],
        "heading": ph,
        "size": (24 * PX_PER_M, PIT_WIDTH_M * PX_PER_M * 0.8),
    }

    for name, img in (("asphalt", asphalt), ("gravel", gravel), ("kerb", kerb),
                      ("kerb_dir", kerb_dir), ("barrier", barrier)):
        img.save(os.path.join(out_dir, name + ".png"))

    data = {
        "tile": TILE,
        "grid_origin": (gx0, gy0),
        "grid_size": size,
        "px_per_m": PX_PER_M,
        "lap_length_px": lap_px,
        "start": {"pos": center[0], "heading": h0},
        "sections": sections,
        "spawns": spawns,
        "pit_zone": pit_zone,
    }
    with open(os.path.join(out_dir, "track.json"), "w") as f:
        json.dump(data, f, indent=1)

    corners = sum(is_corner) / n * 100
    print("tour : %.0f m (%d px) ; grille %dx%d tuiles ; %.0f %% du tour en virage"
          % (lap_px / PX_PER_M, lap_px, size[0], size[1], corners))
    for name, img in (("asphalte", asphalt), ("gravier", gravel), ("vibreurs", kerb), ("barrière", barrier)):
        print("  %-9s %6d tuiles" % (name, sum(1 for v in img.getdata() if v)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
