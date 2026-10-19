import 'package:photo_manager/photo_manager.dart';

const allPhotosAlbumId = '__all_photos__';

class LibraryAlbum {
  const LibraryAlbum({
    required this.id,
    required this.name,
    required this.count,
    this.isAll = false,
  });

  final String id;
  final String name;
  final int count;
  final bool isAll;
}

class GalleryPhoto {
  const GalleryPhoto({
    required this.id,
    required this.asset,
    this.createdAt,
  });

  final String id;
  final AssetEntity? asset;
  final DateTime? createdAt;

  factory GalleryPhoto.fromAsset(AssetEntity asset) {
    return GalleryPhoto(
      id: asset.id,
      asset: asset,
      createdAt: asset.createDateTime,
    );
  }
}

abstract interface class PhotoLibrary {
  Future<bool> requestAccess();
  Future<void> openSettings();
  Future<List<LibraryAlbum>> getAlbums();
  Future<List<GalleryPhoto>> getPhotos({
    required String albumId,
    required int page,
    required int pageSize,
  });
  Future<List<GalleryPhoto>> findPhotosByIds(Set<String> ids);
}

class PhotoManagerLibrary implements PhotoLibrary {
  AssetPathEntity? _allPath;
  Map<String, AssetPathEntity> _paths = <String, AssetPathEntity>{};

  @override
  Future<bool> requestAccess() async {
    final permission = await PhotoManager.requestPermissionExtend();
    return permission.hasAccess;
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    final allPaths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
    );
    _allPath = allPaths.isEmpty ? null : allPaths.first;

    final paths = await PhotoManager.getAssetPathList(
      hasAll: false,
      onlyAll: false,
      type: RequestType.image,
    );
    _paths = <String, AssetPathEntity>{
      for (final path in paths) path.id: path,
    };

    final albums = <LibraryAlbum>[
      LibraryAlbum(
        id: allPhotosAlbumId,
        name: 'All photos',
        count: _allPath == null ? 0 : await _allPath!.assetCountAsync,
        isAll: true,
      ),
    ];

    for (final path in paths) {
      if (path.isAll) continue;
      albums.add(
        LibraryAlbum(
          id: path.id,
          name: path.name,
          count: await path.assetCountAsync,
        ),
      );
    }

    return albums;
  }

  @override
  Future<List<GalleryPhoto>> getPhotos({
    required String albumId,
    required int page,
    required int pageSize,
  }) async {
    if (_allPath == null && _paths.isEmpty) {
      await getAlbums();
    }
    final path = albumId == allPhotosAlbumId
        ? _allPath
        : _paths[albumId];

    if (path == null) return const <GalleryPhoto>[];

    final assets = await path.getAssetListPaged(
      page: page,
      size: pageSize,
    );
    return assets.map(GalleryPhoto.fromAsset).toList(growable: false);
  }

  @override
  Future<List<GalleryPhoto>> findPhotosByIds(Set<String> ids) async {
    if (ids.isEmpty) return const <GalleryPhoto>[];
    if (_allPath == null) await getAlbums();

    final path = _allPath;
    if (path == null) return const <GalleryPhoto>[];

    final assetCount = await path.assetCountAsync;
    final pageCount = (assetCount / 80).ceil();
    final found = <String, GalleryPhoto>{};

    for (var page = 0; page < pageCount; page++) {
      final assets = await path.getAssetListPaged(page: page, size: 80);
      if (assets.isEmpty) break;

      for (final asset in assets) {
        if (ids.contains(asset.id)) {
          found[asset.id] = GalleryPhoto.fromAsset(asset);
        }
      }

      if (found.length == ids.length) break;
    }

    final photos = found.values.toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime(1970);
        final bDate = b.createdAt ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });
    return photos;
  }
}
