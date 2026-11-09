"""Resample the user-supplied artwork into Android launcher resources (Pillow)."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "mobile/android/app/src/main/res"
SOURCE = ROOT / "design/branding/app-icon.png"


def main():
    with Image.open(SOURCE) as source:
        image = source.convert("RGB")
        if image.width != image.height:
            raise ValueError("Launcher artwork must be square")
        for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                              ("xxhdpi", 144), ("xxxhdpi", 192)):
            target = RES / f"mipmap-{density}"
            target.mkdir(parents=True, exist_ok=True)
            image.resize((size, size), Image.Resampling.LANCZOS).save(target / "ic_launcher.png")
            # Adaptive icons use a 108dp canvas; the supplied central emblem
            # fits inside the 66dp safe zone. Android applies the launcher mask.
            adaptive_size = size * 108 // 48
            image.resize((adaptive_size, adaptive_size), Image.Resampling.LANCZOS).save(
                target / "ic_launcher_foreground.png")
    print("Generated five legacy and five adaptive launcher artwork sizes")


if __name__ == "__main__":
    main()
