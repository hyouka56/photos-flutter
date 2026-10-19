# Photos (Flutter)

A local-first photo gallery for Android built with Flutter. Photos remain in the device's own media library; the app does not upload pictures or require Internet permission.

## Features

- Three-column photo grid with paginated thumbnail loading.
- Device albums/folders, including an All Photos view.
- Full-screen photo viewing with pinch-to-zoom.
- Favorites saved locally on the device.
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

The APK output is `build/app/outputs/flutter-apk/app-release.apk`. GitHub Actions publishes the APK under the `photos-apk-arm64-v8a` artifact.

## Privacy

The gallery reads images from the device only. Favorites are stored locally with SharedPreferences. No remote image service, analytics SDK, tracking SDK, or Internet permission is included.

## Main packages

- `photo_manager` — on-device image-library access and albums.
- `photo_manager_image_provider` — cached Flutter image providers for photo thumbnails.
- `shared_preferences` — local favorite IDs.
