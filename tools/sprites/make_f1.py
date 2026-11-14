"""Génère le sprite de la Formule 1 (80x144 par image, avant en bas),
6 images d'animation (fumée d'échappement), palette des voitures existantes."""
import sys
from PIL import Image, ImageDraw

W, H, FRAMES = 80, 144, 6

OUTLINE   = (40, 40, 56, 255)
EDGE      = (58, 58, 80, 255)
DARK      = (70, 70, 94, 255)
TIRE      = (46, 46, 62, 255)
TIRE_HI   = (86, 89, 114, 255)
TIRE_LINE = (58, 58, 80, 255)
GREY      = (125, 127, 153, 255)
GREY_HI   = (178, 174, 203, 255)
ORANGE    = (236, 122, 32, 255)
ORANGE_HI = (252, 172, 74, 255)
ORANGE_LO = (186, 82, 22, 255)
YELLOW    = (248, 237, 137, 255)
WHITE     = (248, 248, 248, 255)
SMOKE     = (152, 158, 190, 255)
SMOKE_HI  = (178, 174, 203, 255)


def rect(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


def left_half(d):
    # ---- Pneus arrière (larges) ----
    rect(d, 5, 27, 18, 55, TIRE)
    for y in range(29, 55, 3):
        rect(d, 7, y, 17, y, TIRE_LINE)
    rect(d, 5, 28, 5, 54, TIRE_HI)
    # ---- Pneus avant ----
    rect(d, 7, 99, 18, 121, TIRE)
    for y in range(101, 121, 3):
        rect(d, 9, y, 17, y, TIRE_LINE)
    rect(d, 7, 100, 7, 120, TIRE_HI)
    # ---- Bras de suspension ----
    rect(d, 19, 34, 27, 34, EDGE)
    rect(d, 19, 46, 25, 46, EDGE)
    d.line([(19, 104), (33, 100)], fill=EDGE)
    d.line([(19, 115), (34, 110)], fill=EDGE)
    # ---- Fond plat (visible sous les pontons) ----
    rect(d, 20, 54, 24, 90, EDGE)
    # ---- Aileron arrière ----
    rect(d, 8, 11, 11, 25, DARK)          # dérive
    rect(d, 12, 15, 39, 22, ORANGE)
    rect(d, 12, 15, 39, 15, ORANGE_HI)
    rect(d, 12, 22, 39, 22, ORANGE_LO)
    rect(d, 12, 19, 39, 19, ORANGE_LO)    # second plan
    # ---- Capot moteur ----
    d.polygon([(33, 23), (39, 23), (39, 52), (27, 52)], fill=ORANGE)
    rect(d, 37, 23, 39, 70, ORANGE_HI)    # arête centrale
    rect(d, 36, 30, 39, 38, DARK)         # échappement / aileron de requin
    rect(d, 38, 31, 39, 37, EDGE)
    # ---- Pontons ----
    d.polygon([(27, 50), (39, 50), (39, 92), (31, 96), (24, 88), (23, 58)], fill=ORANGE)
    rect(d, 23, 60, 24, 86, ORANGE_LO)    # ombre extérieure
    rect(d, 25, 62, 28, 63, YELLOW)       # bande déco
    rect(d, 25, 66, 28, 67, YELLOW)
    rect(d, 26, 54, 30, 56, DARK)         # entrée d'air
    # ---- Arceau / prise d'air ----
    rect(d, 36, 62, 39, 70, DARK)
    rect(d, 37, 63, 39, 64, GREY)
    # ---- Cockpit + pilote ----
    d.ellipse([33, 71, 46, 90], fill=EDGE)
    d.ellipse([35, 75, 44, 85], fill=YELLOW)     # casque
    rect(d, 37, 81, 42, 83, WHITE)                # visière
    rect(d, 36, 88, 39, 90, GREY)                 # halo
    rect(d, 39, 84, 40, 90, GREY_HI)
    # ---- Nez ----
    d.polygon([(33, 90), (39, 90), (39, 127), (36, 127), (34, 110)], fill=ORANGE)
    rect(d, 38, 92, 39, 126, ORANGE_HI)
    rect(d, 34, 104, 35, 112, ORANGE_LO)
    # ---- Aileron avant profilé ----
    # Bord d'attaque courbe : le centre (contre le nez) est le plus en
    # avant, les extrémités sont repoussées vers l'arrière (vers le haut
    # du sprite), avec 3 éléments étagés qui suivent la courbe.
    def sweep(x):
        t = (39 - x) / 29.0          # 0 au centre, 1 à l'extrémité
        return round(t * t * t * 4)  # centre presque droit, bouts relevés
    for x in range(10, 40):
        o = sweep(x)
        base = 135 - o               # bord d'attaque
        rect(d, x, base - 1, x, base, ORANGE_HI)      # élément principal
        rect(d, x, base - 3, x, base - 2, ORANGE)     # 2e élément
        if x < 34:
            rect(d, x, base - 5, x, base - 4, ORANGE_LO)  # 3e élément (volet)
        rect(d, x, base - 6 if x < 34 else base - 4, x, base - 6 if x < 34 else base - 4, EDGE)
    # Dérives (endplates) inclinées aux extrémités
    d.polygon([(7, 124), (9, 124), (10, 135), (8, 135)], fill=DARK)
    rect(d, 8, 125, 8, 128, EDGE)
    rect(d, 36, 124, 39, 129, EDGE)       # pointe du nez


def body() -> Image.Image:
    half = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    left_half(ImageDraw.Draw(half))
    left = half.crop((0, 0, W // 2, H))
    full = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    full.paste(left, (0, 0))
    full.paste(left.transpose(Image.FLIP_LEFT_RIGHT), (W // 2, 0))
    # Contour 1 px autour de la silhouette (style pixel art des sprites).
    px = full.load()
    out = full.copy()
    po = out.load()
    for y in range(H):
        for x in range(W):
            if px[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and px[nx, ny][3] != 0:
                    po[x, y] = OUTLINE
                    break
    return out


def smoke(img: Image.Image, frame: int) -> None:
    """Petites volutes qui montent de l'échappement (x ~ 39-40, y < 11)."""
    p = img.load()
    for k in range(3):
        y = 9 - ((frame * 2 + k * 4) % 11)
        if y < 0:
            continue
        x = 39 + (1 if (frame + k) % 2 else -1) * (k % 2)
        size = 1 if y < 4 else 2
        for dx in range(size):
            for dy in range(size):
                if 0 <= x + dx < W and 0 <= y + dy < H and p[x + dx, y + dy][3] == 0:
                    p[x + dx, y + dy] = SMOKE_HI if y < 5 else SMOKE


def main(sheet_path: str, preview_path: str, check_path: str) -> None:
    base = body()
    sheet = Image.new("RGBA", (W * FRAMES, H), (0, 0, 0, 0))
    for f in range(FRAMES):
        frame = base.copy()
        smoke(frame, f)
        sheet.paste(frame, (f * W, 0))
    sheet.save(sheet_path)

    # Aperçu : vue de dessus orientée vers la droite, comme les autres
    # aperçus (~170 x 108), fond transparent.
    preview = base.crop(base.getbbox()).rotate(90, expand=True)
    canvas = Image.new("RGBA", (174, 108), (0, 0, 0, 0))
    scale = min(170 / preview.width, 104 / preview.height)
    preview = preview.resize((int(preview.width * scale), int(preview.height * scale)), Image.NEAREST)
    canvas.paste(preview, ((174 - preview.width) // 2, (108 - preview.height) // 2), preview)
    canvas.save(preview_path)

    # Planche de contrôle x4 (fond gris) : 6 images + aperçu.
    check = Image.new("RGBA", (W * FRAMES + 10 * FRAMES + 180, H), (200, 200, 200, 255))
    for f in range(FRAMES):
        fr = sheet.crop((f * W, 0, (f + 1) * W, H))
        check.paste(fr, (f * (W + 10), 0), fr)
    check.paste(canvas, (FRAMES * (W + 10), 18), canvas)
    check = check.resize((check.width * 3, check.height * 3), Image.NEAREST)
    check.save(check_path)


if __name__ == "__main__":
    main(*sys.argv[1:4])
