#!/usr/bin/env python3
"""Configure the generated Android manifest for a private, on-device photo gallery."""

from pathlib import Path
import re
import shutil


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    source_icon = root / "assets" / "photos_icon.png"
    target_dir = root / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi"
    target_icon = target_dir / "photos_icon.png"

    if not manifest.is_file():
        raise SystemExit(f"Android manifest not found: {manifest}")
    if not source_icon.is_file():
        raise SystemExit(f"Launcher icon not found: {source_icon}")

    text = manifest.read_text(encoding="utf-8")
    text = re.sub(
        r"\s*<uses-permission\b(?=[^>]*android:name=\"android\.permission\.INTERNET\")[^>]*/>",
        "",
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(r'android:label="[^"]+"', 'android:label="Photos"', text, count=1)
    text = re.sub(
        r'android:icon="[^"]+"',
        'android:icon="@drawable/photos_icon"',
        text,
        count=1,
    )

    permissions = (
        '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" '
        'android:maxSdkVersion="32" />',
        '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />',
        '<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />',
    )
    for permission in permissions:
        permission_name = re.search(r'android:name="([^"]+)"', permission).group(1)
        if f'android:name="{permission_name}"' not in text:
            text = text.replace("<application", f"    {permission}\n\n    <application", 1)

    manifest.write_text(text, encoding="utf-8")
    target_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source_icon, target_icon)

    print("Configured Photos label and offline media permissions.")
    print(f"Launcher icon: {target_icon}")


if __name__ == "__main__":
    main()
