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

  testWidgets('shows the local photo grid and bottom navigation', (tester) async {
    await tester.pumpWidget(
      PhotosApp(library: library, favoritesStore: favorites),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photosGrid')), findsOneWidget);
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

  testWidgets('albums open their own photo list', (tester) async {
    await tester.pumpWidget(
      PhotosApp(library: library, favoritesStore: favorites),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('albumsTab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('album-camera-roll')), findsOneWidget);
    await tester.tap(find.byKey(const Key('album-camera-roll')));
    await tester.pumpAndSettle();

    expect(find.text('Camera Roll'), findsOneWidget);
    expect(find.byKey(const Key('photoTile-photo-1')), findsOneWidget);
    expect(find.byKey(const Key('photoTile-photo-2')), findsNothing);
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
    return true;
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
  Future<List<GalleryPhoto>> findPhotosByIds(Set<String> ids) async {
    return _photos.where((photo) => ids.contains(photo.id)).toList();
  }
}
