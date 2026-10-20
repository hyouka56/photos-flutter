import 'dart:io' show Platform;

import 'package:flutter/services.dart';
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
  Future<List<String>> deletePhotos(List<String> ids);
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
      hasAll: true,
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

  static const MethodChannel _permanentDeleteChannel =
      MethodChannel('photos/permanent_delete');

  @override
  Future<List<String>> deletePhotos(List<String> ids) async {
    if (ids.isEmpty) return const <String>[];

    if (Platform.isAndroid) {
      try {
        final deleted = await _permanentDeleteChannel.invokeListMethod<String>(
          'deleteImagesPermanently',
          <String, Object>{'ids': ids},
        );
        return deleted ?? const <String>[];
      } on PlatformException catch (error) {
        if (error.code != 'UNSUPPORTED_VERSION') rethrow;
      } on MissingPluginException {
        // Older builds can fall back to the plugin's supported editor API.
      }
    }

    return PhotoManager.editor.deleteWithIds(ids);
  }


}
