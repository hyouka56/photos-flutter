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
    <path android:fillColor="#000000" android:pathData="M0,0h512v512h-512z" />
    <path android:fillColor="#FFFFFF" android:pathData="M320,132a34,34 0,1 0,68 0a34,34 0,1 0,-68 0z" />
    <path android:fillColor="#FFFFFF" android:pathData="M68,405l118,-157 70,90 63,-78 125,145z" />
</vector>
"""

def _set_style_item(xml_text: str, style_name: str, item_name: str, value: str) -> str:
    style_re = re.compile(
        r'(<style\b[^>]*\bname="' + re.escape(style_name)
        + r'"[^>]*>)(.*?)(</style>)', flags=re.DOTALL
    )
    match = style_re.search(xml_text)
    if not match:
        return xml_text
    opening, body, closing = match.group(1), match.group(2), match.group(3)
    item_re = re.compile(
        r'<item\s+name="' + re.escape(item_name) + r'">.*?</item>',
        flags=re.DOTALL,
    )
    item = f'<item name="{item_name}">{value}</item>'
    if item_re.search(body):
        body = item_re.sub(item, body, count=1)
    else:
        body = body.rstrip() + f'\n        {item}\n    '
    return xml_text[:match.start()] + opening + body + closing + xml_text[match.end():]


def configure_dark_launch_screen(root: Path) -> None:
    resources = root / "android" / "app" / "src" / "main" / "res"
    launch_background = resources / "drawable" / "launch_background.xml"
    launch_background.parent.mkdir(parents=True, exist_ok=True)
    launch_background.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <item android:drawable="#FF000000" />\n'
        '</layer-list>\n', encoding="utf-8"
    )

    for styles_file in resources.rglob("*.xml"):
        if not styles_file.parent.name.startswith("values") or styles_file.name not in {"styles.xml", "themes.xml"}:
            continue
        xml_text = styles_file.read_text(encoding="utf-8")
        if not re.search(r'<style\b[^>]*\bname="LaunchTheme"', xml_text):
            continue
        for style_name in ("LaunchTheme", "NormalTheme"):
            if not re.search(r'<style\b[^>]*\bname="' + re.escape(style_name) + r'"', xml_text):
                continue
            background = "@drawable/launch_background" if style_name == "LaunchTheme" else "#FF000000"
            for item_name, value in (
                ("android:windowBackground", background),
                ("android:statusBarColor", "#FF000000"),
                ("android:navigationBarColor", "#FF000000"),
                ("android:windowLightStatusBar", "false"),
            ):
                xml_text = _set_style_item(xml_text, style_name, item_name, value)
            if style_name == "LaunchTheme" and styles_file.parent.name in {"values-v31", "values-night-v31"}:
                xml_text = _set_style_item(xml_text, style_name, "android:windowSplashScreenBackground", "#FF000000")
                xml_text = _set_style_item(xml_text, style_name, "android:windowSplashScreenAnimatedIcon", "@drawable/photos_icon")
        styles_file.write_text(xml_text, encoding="utf-8")



def configure_android_gradle_properties(root: Path) -> None:
    """Disable duplicate VFS watchers and use AGP's built-in Kotlin support."""
    android = root / "android"
    properties = android / "gradle.properties"
    settings = android / "settings.gradle.kts"
    app_gradle = android / "app" / "build.gradle.kts"
    if not properties.is_file():
        raise SystemExit(f"Android Gradle properties not found: {properties}")
    if not settings.is_file() or not app_gradle.is_file():
        raise SystemExit("Flutter 3.47+ Kotlin DSL Android templates are required for built-in Kotlin")

    settings_text = settings.read_text(encoding="utf-8")
    agp_match = re.search(
        r'id\(\s*["\']com\.android\.application["\']\s*\)\s*version\s*["\'](\d+(?:\.\d+)+)["\']',
        settings_text,
    )
    if not agp_match or int(agp_match.group(1).split(".")[0]) < 9:
        version = agp_match.group(1) if agp_match else "not detected"
        raise SystemExit(f"Built-in Kotlin requires Android Gradle Plugin 9+; detected {version}")

    app_text = app_gradle.read_text(encoding="utf-8")
    if re.search(
        r'(?m)^\s*id\(\s*["\'](?:kotlin-android|org\.jetbrains\.kotlin\.android)["\']\s*\)',
        app_text,
    ):
        raise SystemExit("Android app still applies the Kotlin Gradle Plugin; migrate app/build.gradle.kts first")
    if not re.search(r"kotlin\s*\{\s*compilerOptions\s*\{", app_text, flags=re.DOTALL):
        raise SystemExit("Android app is missing the built-in Kotlin compilerOptions block")

    text = properties.read_text(encoding="utf-8")
    settings_to_apply = (
        (r"(?m)^\s*org\.gradle\.vfs\.watch\s*=.*$", "org.gradle.vfs.watch=false",
         "# Avoid duplicate Android-root filesystem watchers on CI."),
        (r"(?m)^\s*android\.builtInKotlin\s*=.*$", "android.builtInKotlin=true",
         "# Use AGP 9 built-in Kotlin; supported by this Flutter template and photo_manager."),
    )
    for expression, configured, comment in settings_to_apply:
        setting = re.compile(expression)
        if setting.search(text):
            text = setting.sub(configured, text, count=1)
        else:
            text = text.rstrip() + f"\n\n{comment}\n{configured}\n"
    properties.write_text(text, encoding="utf-8")
    print(f"Built-in Kotlin enabled (Android Gradle Plugin {agp_match.group(1)}).")

def main() -> None:
    root = Path(__file__).resolve().parents[1]
    manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    icon = root / "android" / "app" / "src" / "main" / "res" / "drawable" / "photos_icon.xml"
    gradle_kts = root / "android" / "app" / "build.gradle.kts"
    gradle_groovy = root / "android" / "app" / "build.gradle"

    if not manifest.is_file():
        raise SystemExit(f"Android manifest not found: {manifest}")

    activity = root / "android" / "app" / "src" / "main" / "kotlin" / "com" / "hyouka" / "photos" / "MainActivity.kt"
    activity.parent.mkdir(parents=True, exist_ok=True)
    activity.write_text("""package com.hyouka.photos

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "photos/permanent_delete"
    private val systemUiChannelName = "photos/system_ui"
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteIds: List<String> = emptyList()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemUiChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "immersive" -> {
                        setImmersiveSystemUi(true)
                        result.success(null)
                    }
                    "edgeToEdge" -> {
                        setImmersiveSystemUi(false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "deleteImagesPermanently") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    result.error("UNSUPPORTED_VERSION", "Use PhotoManager deletion on Android versions below 11.", null)
                    return@setMethodCallHandler
                }
                if (pendingDeleteResult != null) {
                    result.error("DELETE_IN_PROGRESS", "A delete confirmation is already open.", null)
                    return@setMethodCallHandler
                }
                val ids = call.argument<List<String>>("ids")?.distinct().orEmpty()
                if (ids.isEmpty()) {
                    result.success(emptyList<String>())
                    return@setMethodCallHandler
                }
                val numericIds = ids.mapNotNull { it.toLongOrNull() }
                if (numericIds.size != ids.size) {
                    result.error("INVALID_MEDIA_IDS", "The selected images contain invalid MediaStore identifiers.", null)
                    return@setMethodCallHandler
                }
                val uris = numericIds.map {
                    ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, it)
                }
                try {
                    val request = MediaStore.createDeleteRequest(contentResolver, uris)
                    pendingDeleteIds = ids
                    pendingDeleteResult = result
                    startIntentSenderForResult(request.intentSender, DELETE_REQUEST_CODE, null, 0, 0, 0)
                } catch (error: Exception) {
                    pendingDeleteResult = null
                    pendingDeleteIds = emptyList()
                    result.error("DELETE_REQUEST_FAILED", error.message ?: "Could not request media deletion.", null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun setImmersiveSystemUi(immersive: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val controller = window.insetsController ?: return
            val systemBars = WindowInsets.Type.statusBars() or
                WindowInsets.Type.navigationBars()
            controller.systemBarsBehavior =
                WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (immersive) {
                controller.hide(systemBars)
            } else {
                controller.show(systemBars)
            }
        } else {
            window.decorView.systemUiVisibility = if (immersive) {
                (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN)
            } else {
                (View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN)
            }
        }
    }

    @Deprecated("Deprecated by Android, kept for Flutter's activity-result callback compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != DELETE_REQUEST_CODE) return
        val result = pendingDeleteResult ?: return
        val ids = pendingDeleteIds
        pendingDeleteResult = null
        pendingDeleteIds = emptyList()
        if (resultCode != Activity.RESULT_OK) {
            result.success(emptyList<String>())
            return
        }
        val deleted = ids.filter { id ->
            val numericId = id.toLongOrNull() ?: return@filter false
            val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, numericId)
            contentResolver.query(uri, arrayOf(MediaStore.Images.Media._ID), null, null, null)?.use { cursor ->
                !cursor.moveToFirst()
            } ?: true
        }
        result.success(deleted)
    }

    companion object {
        private const val DELETE_REQUEST_CODE = 0x501A
    }
}
""", encoding="utf-8")

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
        '<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />',
        '<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />',
    )
    for permission in permissions:
        permission_name = re.search(r'android:name="([^"]+)"', permission).group(1)
        if f'android:name="{permission_name}"' not in text:
            text = text.replace("<application", f"    {permission}\n\n    <application", 1)

    manifest.write_text(text, encoding="utf-8")

    if gradle_kts.is_file():
        gradle_file = gradle_kts
        gradle_text = gradle_file.read_text(encoding="utf-8")
        if "abiFilters" not in gradle_text:
            marker = "    defaultConfig {"
            if gradle_text.count(marker) != 1:
                raise SystemExit("Could not find exactly one defaultConfig block in build.gradle.kts")
            gradle_text = gradle_text.replace(
                marker,
                marker + chr(10) + "        ndk {" + chr(10) + '            abiFilters += listOf("arm64-v8a")' + chr(10) + "        }",
                1,
            )
        if 'abiFilters += listOf("arm64-v8a")' not in gradle_text:
            raise SystemExit("Android ABI filter is not configured for arm64-v8a")
        gradle_file.write_text(gradle_text, encoding="utf-8")
    elif gradle_groovy.is_file():
        gradle_file = gradle_groovy
        gradle_text = gradle_file.read_text(encoding="utf-8")
        if "abiFilters" not in gradle_text:
            marker = "    defaultConfig {"
            if gradle_text.count(marker) != 1:
                raise SystemExit("Could not find exactly one defaultConfig block in build.gradle")
            gradle_text = gradle_text.replace(
                marker,
                marker + chr(10) + "        ndk {" + chr(10) + '            abiFilters "arm64-v8a"' + chr(10) + "        }",
                1,
            )
        if 'abiFilters "arm64-v8a"' not in gradle_text:
            raise SystemExit("Android ABI filter is not configured for arm64-v8a")
        gradle_file.write_text(gradle_text, encoding="utf-8")
    else:
        raise SystemExit("Android app Gradle file not found")

    # ABI filters do not consistently exclude native libraries bundled by
    # transitive plugins, so explicitly exclude incompatible JNI directories.
    gradle_text = gradle_file.read_text(encoding="utf-8")
    if "PHOTOS_ARM64_ABI_PACKAGING_EXCLUSIONS" not in gradle_text:
        if gradle_file.suffix == ".kts":
            gradle_text += (
                "\n\n// PHOTOS_ARM64_ABI_PACKAGING_EXCLUSIONS\n"
                "android {\n"
                "    packaging {\n"
                "        jniLibs {\n"
                '            excludes += setOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")\n'
                "        }\n"
                "    }\n"
                "}\n"
            )
        else:
            gradle_text += (
                "\n\n// PHOTOS_ARM64_ABI_PACKAGING_EXCLUSIONS\n"
                "android {\n"
                "    packaging {\n"
                "        jniLibs {\n"
                '            excludes += ["lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**"]\n'
                "        }\n"
                "    }\n"
                "}\n"
            )
        gradle_file.write_text(gradle_text, encoding="utf-8")

    icon.parent.mkdir(parents=True, exist_ok=True)
    icon.write_text(VECTOR_ICON, encoding="utf-8")
    configure_dark_launch_screen(root)
    configure_android_gradle_properties(root)
    print("Configured Photos label, Android media permissions, immersive photo-viewer system UI, borderless sun-and-mountain icon, permanent media deletion request, dark launch screen, duplicate-watcher workaround, and arm64-v8a ABI filter.")
    print(f"Launcher icon: {icon}")
    print(f"Android Gradle config: {gradle_file}")


if __name__ == "__main__":
    main()
