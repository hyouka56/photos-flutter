#!/usr/bin/env python3
"""Apply a narrow source-only workaround for Flutter 3.47's KGP detector.

photo_manager 3.12.0 already has an AGP 9 built-in-Kotlin branch. Flutter 3.47
scans Gradle files with a regex and treats the conditional legacy fallback
`apply plugin: 'kotlin-android'` as an unconditional KGP use. This script only
runs for that exact package version, after Pub resolution and after we have
verified this build uses AGP 9+ built-in Kotlin. It changes the fallback syntax
to the equivalent Gradle PluginManager API call; the conditional fallback
remains available if built-in Kotlin is not active.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


def fail(message: str) -> None:
    raise SystemExit(f"photo_manager KGP compatibility check failed: {message}")


def locked_version(lockfile: Path, package_name: str) -> str:
    text = lockfile.read_text(encoding="utf-8")
    match = re.search(
        rf"(?ms)^  {re.escape(package_name)}:\n(?P<body>.*?)(?=^  [^ \t].*:\s*$|\Z)",
        text,
    )
    if not match:
        fail(f"{package_name} is missing from pubspec.lock")
    version = re.search(r"(?m)^    version:\s*['\"]?([^'\"\n]+)", match.group("body"))
    if not version:
        fail(f"could not read locked version for {package_name}")
    return version.group(1).strip()


def package_root(package_config: Path, package_name: str) -> Path:
    try:
        data = json.loads(package_config.read_text(encoding="utf-8"))
        entry = next(item for item in data["packages"] if item["name"] == package_name)
    except (OSError, ValueError, KeyError, StopIteration) as exc:
        fail(f"could not locate {package_name} through {package_config}: {exc}")
    root_uri = entry.get("rootUri")
    if not isinstance(root_uri, str) or not root_uri:
        fail(f"invalid rootUri for {package_name}")
    resolved = urlparse(urljoin(package_config.resolve().as_uri(), root_uri))
    if resolved.scheme != "file":
        fail(f"expected a local Pub package, got rootUri={root_uri!r}")
    return Path(url2pathname(resolved.path)).resolve()


def main() -> None:
    root = Path.cwd()
    properties = root / "android" / "gradle.properties"
    settings = root / "android" / "settings.gradle.kts"
    if not properties.is_file() or not settings.is_file():
        fail("generated Android Gradle files are missing")
    if not re.search(r"(?m)^\s*android\.builtInKotlin\s*=\s*true\s*$", properties.read_text(encoding="utf-8")):
        fail("android.builtInKotlin=true was not enabled")
    settings_text = settings.read_text(encoding="utf-8")
    agp = re.search(
        r"(?s)id\(\s*['\"]com\.android\.application['\"]\s*\)\s*version\s*['\"](\d+(?:\.\d+)+)['\"]",
        settings_text,
    )
    if not agp or int(agp.group(1).split(".")[0]) < 9:
        fail("the generated app is not using AGP 9+")

    version = locked_version(root / "pubspec.lock", "photo_manager")
    if version != "3.12.0":
        fail(f"expected reviewed photo_manager 3.12.0, found {version}; review before changing")

    build_file = package_root(root / ".dart_tool" / "package_config.json", "photo_manager") / "android" / "build.gradle"
    if not build_file.is_file():
        fail(f"Android plugin Gradle file not found: {build_file}")
    source = build_file.read_text(encoding="utf-8")
    if "if (!useBuiltInKotlin)" not in source or "compilerOptions" not in source:
        fail("package no longer has the reviewed conditional built-in-Kotlin implementation")
    pattern = re.compile(r"(?m)^(\s*)apply plugin: ['\"]kotlin-android['\"]\s*$")
    hits = list(pattern.finditer(source))
    if len(hits) != 1:
        fail(f"expected one conditional kotlin-android fallback, found {len(hits)}")
    match = hits[0]
    replacement = match.group(1) + "project.pluginManager.apply('kotlin-android')"
    updated = source[:match.start()] + replacement + source[match.end():]
    if pattern.search(updated):
        fail("legacy KGP syntax remains after the patch")
    build_file.write_text(updated, encoding="utf-8")
    print(
        "Patched photo_manager 3.12.0's conditional KGP fallback using the equivalent "
        f"PluginManager API (AGP {agp.group(1)} built-in Kotlin remains enabled)."
    )


if __name__ == "__main__":
    main()
