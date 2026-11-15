"""Draws the Vortex Anime icon: a slashed V and play mark at the eye of a spiralling vortex."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 2048


def vortex(size):
    """Spiral arms in polar space, coloured from deep violet out to white hot at the arm edges."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    dx, dy = (x - c) / size, (y - c) / size
    r = np.sqrt(dx * dx + dy * dy) + 1e-5
    theta = np.arctan2(dy, dx)
    twist = theta * 5 + np.log(r) * 7.5
    arms = (np.sin(twist) * 0.5 + 0.5) ** 3.2
    fine = (np.sin(theta * 11 + np.log(r) * 15 + 1.1) * 0.5 + 0.5) ** 7
    # Bright near the eye, fading out into the dark corners.
    falloff = np.clip(1.05 - r * 1.55, 0, 1) ** 1.25
    eye = np.clip((r - 0.10) / 0.12, 0, 1)
    light = np.clip((arms * 0.95 + fine * 0.35) * falloff * eye, 0, 1)

    stops = np.array([[0.0, 9, 9, 15], [0.22, 34, 14, 84], [0.5, 109, 58, 224], [0.74, 139, 92, 246], [0.9, 196, 181, 253], [1.0, 255, 255, 255]], dtype=np.float32)
    rgb = np.stack([np.interp(light, stops[:, 0], stops[:, i]) for i in (1, 2, 3)], axis=-1)
    # A soft violet pool behind it all, so the dark gaps aren't flat.
    pool = np.clip(0.62 - r, 0, 1)[..., None] * np.array([58, 26, 130], dtype=np.float32) * 0.5
    return Image.fromarray(np.clip(rgb + pool, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def mark(size, scale):
    """The V: a white blade, a violet blade cut across it, and a play mark in the notch."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = size * scale / 100
    o = (size - 100 * u) / 2

    def p(*points):
        return [(o + x * u, o + y * u) for x, y in points]

    d.polygon(p((14, 18), (35, 18), (53, 66), (46, 86), (37, 86)), fill=(255, 255, 255, 255))
    d.polygon(p((66, 18), (88, 18), (54, 86), (50, 86), (43.5, 69)), fill=(167, 139, 250, 255))
    # The sword-cut highlight along the violet blade.
    d.polygon(p((81, 18), (88, 18), (54, 86), (50.5, 86)), fill=(237, 233, 254, 255))
    d.polygon(p((46.5, 20), (58, 30.5), (46.5, 41)), fill=(255, 255, 255, 255))
    return img


def eye(size, scale):
    """A dark disc so the V stays sharp against the bright arms."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    radius = size * scale * 0.46
    c = size / 2
    d.ellipse((c - radius, c - radius, c + radius, c + radius), fill=(9, 9, 15, 235))
    return img.filter(ImageFilter.GaussianBlur(size * 0.012))


def foreground(scale):
    big = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    big.alpha_composite(eye(S, scale))
    shadow = mark(S, scale).filter(ImageFilter.GaussianBlur(S * 0.008))
    glow = Image.new("RGBA", (S, S), (139, 92, 246, 0))
    glow.putalpha(shadow.getchannel("A").point(lambda a: int(a * 0.7)))
    big.alpha_composite(glow)
    big.alpha_composite(mark(S, scale))
    return big


_field = None


def field():
    global _field
    if _field is None:
        _field = vortex(S)
    return _field


def icon(size, scale=0.62):
    big = field().copy()
    big.alpha_composite(foreground(scale))
    return big.resize((size, size), Image.LANCZOS)


def main():
    res = ROOT / "android/app/src/main/res"
    for folder, launcher, layer in (("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216), ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432)):
        icon(launcher).convert("RGB").save(res / f"mipmap-{folder}/ic_launcher.png")
        foreground(0.44).resize((layer, layer), Image.LANCZOS).save(res / f"mipmap-{folder}/ic_launcher_foreground.png")
        field().resize((layer, layer), Image.LANCZOS).convert("RGB").save(res / f"mipmap-{folder}/ic_launcher_background.png")
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    stale = res / "values/ic_launcher_background.xml"
    if stale.exists():
        stale.unlink()
    icon(256).save(ROOT / "windows/runner/resources/app_icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    web = ROOT / "web"
    icon(32).convert("RGB").save(web / "favicon.png")
    for name, size in (("Icon-192", 192), ("Icon-512", 512), ("Icon-maskable-192", 192), ("Icon-maskable-512", 512)):
        icon(size).convert("RGB").save(web / f"icons/{name}.png")
    for png in (ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset").glob("*.png"):
        with Image.open(png) as old:
            w = old.size[0]
        icon(w).convert("RGB").save(png)
    icon(1024).convert("RGB").save(ROOT / "tools/icon_preview.png")
    # What a phone shows: the same art at home-screen size, for checking it still reads when small.
    icon(96).convert("RGB").save(ROOT / "tools/icon_small.png")


if __name__ == "__main__":
    main()
