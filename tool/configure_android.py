#!/usr/bin/env python3
"""Configure a private, offline Android photo gallery and vector launcher icon."""

from pathlib import Path
import re

VECTOR_ICON = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="512"
    android:viewportHeight="512">
    <path android:fillColor="#111111" android:pathData="M0,0h512v512h-512z" />
    <path android:fillColor="#292929" android:pathData="M142,72h228c54,0 70,16 70,70v228c0,54 -16,70 -70,70h-228c-54,0 -70,-16 -70,-70v-228c0,-54 16,-70 70,-70z" />
    <path android:fillColor="#FFFFFF" android:pathData="M104,176c0,-16 12,-28 28,-28h39l31,-40c5,-7 13,-12 22,-12h64c9,0 17,5 22,12l31,40h39c16,0 28,12 28,28v176c0,16 -12,28 -28,28h-248c-16,0 -28,-12 -28,-28z" />
    <path android:fillColor="#111111" android:pathData="M178,256a78,78 0,1 0,156 0a78,78 0,1 0,-156 0z" />
    <path android:fillColor="#FFFFFF" android:pathData="M218,256a38,38 0,1 0,76 0a38,38 0,1 0,-76 0z" />
</vector>
"""


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    icon = root / "android" / "app" / "src" / "main" / "res" / "drawable" / "photos_icon.xml"

    if not manifest.is_file():
        raise SystemExit(f"Android manifest not found: {manifest}")

    text = manifest.read_text(encoding="utf-8")
    text = re.sub(
        r'\s*<uses-permission\b(?=[^>]*android:name="android\.permission\.INTERNET")[^>]*/>',
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
        '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />',
        '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />',
        '<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />',
    )
    for permission in permissions:
        permission_name = re.search(r'android:name="([^"]+)"', permission).group(1)
        if f'android:name="{permission_name}"' not in text:
            text = text.replace("<application", f"    {permission}\n\n    <application", 1)

    manifest.write_text(text, encoding="utf-8")
    icon.parent.mkdir(parents=True, exist_ok=True)
    icon.write_text(VECTOR_ICON, encoding="utf-8")
    print("Configured Photos label, offline-only media permissions, and native vector launcher icon.")
    print(f"Launcher icon: {icon}")


if __name__ == "__main__":
    main()
