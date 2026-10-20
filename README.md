# Photos (Flutter)

A local-first photo gallery for Android built with Flutter. Photos remain in the device's own media library; the app does not upload pictures or require Internet permission.

## Features

- Three-column photo grid with paginated thumbnail loading.
- Device albums/folders, including an All Photos view.
- Immersive full-screen photo viewing with pinch-to-zoom and auto-hiding controls.
- Android permission handling, including limited photo selection where supported.
- Dark interface and a Flutter Foundry-generated camera icon.
- GitHub Actions checks formatting, analysis, widget tests, Android manifest/privacy, and builds an **arm64-v8a** release APK.

## Build

Install Flutter stable and Android build tools, then run:

```sh
flutter pub get
dart format lib test
flutter analyze --fatal-infos
flutter test
flutter create . --platforms=android --project-name photos --org com.hyouka
python3 tool/configure_android.py
flutter build apk --release --target-platform android-arm64
```

The APK is written under build/app/outputs/flutter-apk/ (Flutter may name a single-ABI build app-arm64-v8a-release.apk). GitHub Actions detects the actual output, verifies that it contains the arm64-v8a ABI only, and publishes it under the photos-apk-arm64-v8a artifact.

## Privacy

The gallery reads images from the device only. No remote image service, analytics SDK, tracking SDK, or Internet permission is included.

## Main packages

- `photo_manager` — on-device image-library access and albums.
- `photo_manager_image_provider` — cached Flutter image providers for photo thumbnails.
