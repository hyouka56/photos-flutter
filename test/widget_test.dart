import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/main.dart';
import 'package:photos/photo_library.dart';

void main() {
  late FakePhotoLibrary library;
  late MemoryFavoritesStore favorites;

  setUp(() {
    library = FakePhotoLibrary();
    favorites = MemoryFavoritesStore();
  });

  testWidgets('zoom stays focal, returns to default, and double tap resets',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ZoomableImageCanvas(
            child: ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canvasSize = tester.getSize(find.byKey(const Key('photoZoomCanvas')));
    expect(canvasSize.width, 800);
    expect(canvasSize.height, 600);

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('photoZoomViewer')),
    );
    expect(viewer.constrained, isTrue);
    expect(viewer.alignment, isNull);
    final controller = viewer.transformationController!;
    final identity = Matrix4.identity();
    expect(controller.value.storage, equals(identity.storage));

    final focalPoint = const Offset(300, 240);
    final scenePointBefore = controller.toScene(focalPoint);
    final firstFinger =
        await tester.startGesture(const Offset(270, 240), pointer: 1);
    final secondFinger =
        await tester.startGesture(const Offset(330, 240), pointer: 2);
    await tester.pump();
    await firstFinger.moveTo(const Offset(240, 240));
    await tester.pump(const Duration(milliseconds: 20));
    await secondFinger.moveTo(const Offset(360, 240));
    await tester.pump(const Duration(milliseconds: 20));

    final scenePointAfter = controller.toScene(focalPoint);
    expect(scenePointAfter.dx, closeTo(scenePointBefore.dx, 1.0));
    expect(scenePointAfter.dy, closeTo(scenePointBefore.dy, 1.0));
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.1));

    await firstFinger.up();
    await secondFinger.up();
    await tester.pumpAndSettle();

    controller.value = Matrix4.identity()..translateByDouble(50, 30, 0, 1);
    await tester.pump();
    expect(controller.value.storage, equals(identity.storage));

    controller.value = controller.value.clone()
      ..scaleByDouble(2.0, 2.0, 1.0, 1.0);
    await tester.pump();
    expect(find.byKey(const Key('resetZoomButton')), findsNothing);

    await tester.tapAt(const Offset(80, 80));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(80, 80));
    await tester.pumpAndSettle();
    expect(controller.value.storage, equals(identity.storage));
  });

  testWidgets('photo viewer swipes to next and previous photo at default zoom',
      (tester) async {
    final photos = <GalleryPhoto>[
      GalleryPhoto(id: 'swipe-1', asset: null, createdAt: DateTime(2025, 1, 1)),
      GalleryPhoto(id: 'swipe-2', asset: null, createdAt: DateTime(2025, 1, 2)),
      GalleryPhoto(id: 'swipe-3', asset: null, createdAt: DateTime(2025, 1, 3)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: photos,
          initialIndex: 1,
          favoriteIds: const <String>{},
          onFavoriteChanged: (photo, isFavorite) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2025-01-02'), findsOneWidget);

    await tester.dragFrom(const Offset(420, 300), const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.text('2025-01-03'), findsOneWidget);

    await tester.dragFrom(const Offset(380, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(find.text('2025-01-02'), findsOneWidget);
  });

  testWidgets('asks for photo access and retries after access is granted', (tester) async {
    library.accessGranted = false;
    await tester.pumpWidget(
      PhotosApp(library: library, favoritesStore: favorites),
    );
    await tester.pumpAndSettle();

    expect(find.text('Allow photo access'), findsOneWidget);
    expect(find.byKey(const Key('photosGrid')), findsNothing);

    library.accessGranted = true;
    await tester.tap(find.text('Allow photo access'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photosGrid')), findsOneWidget);
    expect(library.requestCount, 2);
  });

  testWidgets('shows the local photo grid and bottom navigation', (tester) async {
    await tester.pumpWidget(
      PhotosApp(library: library, favoritesStore: favorites),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photosGrid')), findsOneWidget);
    expect(find.byKey(const Key('pullToRefresh')), findsOneWidget);
    expect(find.byKey(const Key('refreshLibrary')), findsNothing);
    expect(find.byKey(const Key('photoTile-photo-1')), findsOneWidget);
    expect(find.byKey(const Key('photoTile-photo-2')), findsOneWidget);
    expect(find.byKey(const Key('albumsTab')), findsOneWidget);
    expect(find.byKey(const Key('favoritesTab')), findsOneWidget);
    expect(library.requestCount, 1);
  });

  testWidgets('favorites are saved and displayed in the favorites tab', (tester) async {
    await tester.pumpWidget(
      PhotosApp(library: library, favoritesStore: favorites),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('favorite-photo-1')));
    await tester.pumpAndSettle();

    expect(favorites.ids, contains('photo-1'));

    await tester.tap(find.byKey(const Key('favoritesTab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('favoritesGrid')), findsOneWidget);
    expect(find.byKey(const Key('photoTile-photo-1')), findsOneWidget);
    expect(find.byKey(const Key('photoTile-photo-2')), findsNothing);
  });

  testWidgets('albums have a readable count and system back returns to albums', (tester) async {
    await tester.pumpWidget(PhotosApp(library: library, favoritesStore: favorites));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('albumsTab')));
    await tester.pumpAndSettle();
    expect(find.text('3 albums on this device'), findsOneWidget);
    expect(find.textContaining('Instance of LibraryAlbum'), findsNothing);
    await tester.tap(find.byKey(const Key('album-camera-roll')));
    await tester.pumpAndSettle();
    expect(find.text('Camera Roll'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('albumsGrid')), findsOneWidget);
  });

  testWidgets('long press selects all and deletes photos permanently', (tester) async {
    await tester.pumpWidget(PhotosApp(library: library, favoritesStore: favorites));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('photoTile-photo-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deleteSelectedPhotosButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('selectAllPhotosButton')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('deleteSelectedPhotosButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeletePhotosButton')));
    await tester.pumpAndSettle();
    expect(library.deletedIds, containsAll(<String>['photo-1', 'photo-2']));
    expect(favorites.ids, isEmpty);
    expect(find.byKey(const Key('photoTile-photo-1')), findsNothing);
  });

  testWidgets('deleting a favorite also deletes it from the device library', (tester) async {
    await tester.pumpWidget(PhotosApp(library: library, favoritesStore: favorites));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-photo-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favoritesTab')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('photoTile-photo-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteSelectedPhotosButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeletePhotosButton')));
    await tester.pumpAndSettle();
    expect(library.deletedIds, contains('photo-1'));
    expect(favorites.ids, isEmpty);
  });
}

class MemoryFavoritesStore implements FavoritesStore {
  Set<String> ids = <String>{};

  @override
  Future<Set<String>> load() async => Set<String>.from(ids);

  @override
  Future<void> save(Set<String> value) async {
    ids = Set<String>.from(value);
  }
}

class FakePhotoLibrary implements PhotoLibrary {
  int requestCount = 0;
  bool accessGranted = true;
  final Set<String> deletedIds = <String>{};

  final _photos = <GalleryPhoto>[
    GalleryPhoto(
      id: 'photo-1',
      asset: null,
      createdAt: DateTime(2025, 1, 2),
    ),
    GalleryPhoto(
      id: 'photo-2',
      asset: null,
      createdAt: DateTime(2025, 1, 1),
    ),
  ];

  final _albums = const <LibraryAlbum>[
    LibraryAlbum(
      id: allPhotosAlbumId,
      name: 'All photos',
      count: 2,
      isAll: true,
    ),
    LibraryAlbum(
      id: 'camera-roll',
      name: 'Camera Roll',
      count: 1,
    ),
    LibraryAlbum(
      id: 'downloads',
      name: 'Downloads',
      count: 1,
    ),
  ];

  @override
  Future<bool> requestAccess() async {
    requestCount++;
    return accessGranted;
  }

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<LibraryAlbum>> getAlbums() async => _albums;

  @override
  Future<List<GalleryPhoto>> getPhotos({
    required String albumId,
    required int page,
    required int pageSize,
  }) async {
    final source = albumId == 'camera-roll'
        ? <GalleryPhoto>[_photos.first]
        : albumId == 'downloads'
            ? <GalleryPhoto>[_photos.last]
            : _photos;
    final start = page * pageSize;
    if (start >= source.length) return const <GalleryPhoto>[];
    final end = (start + pageSize).clamp(0, source.length);
    return source.sublist(start, end);
  }

  @override
  Future<List<String>> deletePhotos(List<String> ids) async {
    final found = _photos.where((photo) => ids.contains(photo.id)).map((photo) => photo.id).toList();
    deletedIds.addAll(found);
    _photos.removeWhere((photo) => ids.contains(photo.id));
    return found;
  }

  @override
  Future<List<GalleryPhoto>> findPhotosByIds(Set<String> ids) async {
    return _photos.where((photo) => ids.contains(photo.id)).toList();
  }
}
