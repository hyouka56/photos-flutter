import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'photo_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhotosApp());
}

class PhotosApp extends StatelessWidget {
  const PhotosApp({
    super.key,
    this.library,
    this.favoritesStore,
  });

  final PhotoLibrary? library;
  final FavoritesStore? favoritesStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080808),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF080808),
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Color(0xFFE0E0E0),
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080808),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF101010),
          indicatorColor: Colors.white.withValues(alpha: 0.14),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
      ),
      home: PhotosHome(
        library: library ?? PhotoManagerLibrary(),
        favoritesStore: favoritesStore ?? SharedPreferencesFavoritesStore(),
      ),
    );
  }
}

abstract interface class FavoritesStore {
  Future<Set<String>> load();
  Future<void> save(Set<String> ids);
}

class SharedPreferencesFavoritesStore implements FavoritesStore {
  static const _key = 'photos.favorite.asset.ids';

  @override
  Future<Set<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_key) ?? const <String>[]).toSet();
  }

  @override
  Future<void> save(Set<String> ids) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_key, ids.toList()..sort());
  }
}

class PhotosHome extends StatefulWidget {
  const PhotosHome({
    super.key,
    required this.library,
    required this.favoritesStore,
  });

  final PhotoLibrary library;
  final FavoritesStore favoritesStore;

  @override
  State<PhotosHome> createState() => _PhotosHomeState();
}

class _PhotosHomeState extends State<PhotosHome> {
  static const _pageSize = 60;

  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingFavorites = false;
  bool _favoritesLoaded = false;
  bool _hasAccess = false;
  bool _permissionNeeded = false;
  bool _hasMore = false;
  String? _error;

  int _selectedTab = 0;
  int _page = 0;
  int _albumOriginTab = 1;
  bool _openedFromAlbums = false;
  bool _selectionMode = false;
  bool _selectingAll = false;
  bool _allSelected = false;
  bool _deleting = false;
  final Set<String> _selectedPhotoIds = <String>{};

  bool get _interceptsSystemBack =>
      _selectionMode || _selectedTab != 0 || _openedFromAlbums;

  LibraryAlbum get _allPhotosAlbum => _albums.firstWhere(
        (album) => album.isAll,
        orElse: () => const LibraryAlbum(
          id: allPhotosAlbumId,
          name: 'All photos',
          count: 0,
          isAll: true,
        ),
      );

  List<LibraryAlbum> _albums = const [];
  LibraryAlbum _activeAlbum = const LibraryAlbum(
    id: allPhotosAlbumId,
    name: 'All photos',
    count: 0,
    isAll: true,
  );
  List<GalleryPhoto> _photos = const [];
  List<GalleryPhoto> _favoritePhotos = const [];
  Set<String> _favoriteIds = <String>{};

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
      _permissionNeeded = false;
    });

    try {
      // Ask the OS first so a storage/preferences failure cannot suppress the
      // first-run photo permission prompt.
      final hasAccess = await widget.library.requestAccess();
      Set<String> savedFavorites = <String>{};
      try {
        savedFavorites = await widget.favoritesStore.load();
      } catch (error, stackTrace) {
        developer.log(
          'Could not read saved favorites; continuing without them.',
          name: 'photos.favorites',
          error: error,
          stackTrace: stackTrace,
        );
      }

      if (!mounted) return;

      setState(() {
        _favoriteIds = savedFavorites;
        _favoritesLoaded = false;
        _favoritePhotos = const [];
      });

      if (!hasAccess) {
        setState(() {
          _hasAccess = false;
          _permissionNeeded = true;
          _loading = false;
        });
        return;
      }

      final albums = await widget.library.getAlbums();
      final allAlbum = albums.firstWhere(
        (album) => album.isAll,
        orElse: () => const LibraryAlbum(
          id: allPhotosAlbumId,
          name: 'All photos',
          count: 0,
          isAll: true,
        ),
      );
      final photos = await widget.library.getPhotos(
        albumId: allAlbum.id,
        page: 0,
        pageSize: _pageSize,
      );

      if (!mounted) return;

      setState(() {
        _hasAccess = true;
        _permissionNeeded = false;
        _albums = albums;
        _activeAlbum = allAlbum;
        _photos = photos;
        _page = 0;
        _hasMore = photos.length == _pageSize;
        _loading = false;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Could not initialize the local photo library.',
        name: 'photos.library',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Android could not read your photo library (${error.runtimeType}). '
            'Check Photos and videos access in system settings, then pull down to retry.';
      });
    }
  }

  Future<void> _openSettings() async {
    try {
      await widget.library.openSettings();
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not open system settings.');
    }
  }

  Future<void> _refresh() async {
    if (!_hasAccess || _permissionNeeded) {
      await _start();
      return;
    }

    if (_selectedTab == 1) {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final albums = await widget.library.getAlbums();
        if (!mounted) return;
        setState(() {
          _albums = albums;
          _loading = false;
        });
      } catch (error, stackTrace) {
        developer.log(
          'Could not refresh albums.',
          name: 'photos.library',
          error: error,
          stackTrace: stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Could not refresh albums (${error.runtimeType}). Pull down to retry.';
        });
      }
      return;
    }

    if (_selectedTab == 2) {
      setState(() {
        _loadingFavorites = true;
        _error = null;
      });
      try {
        // Refresh album handles before resolving saved asset IDs. This also
        // picks up permission changes and newly added/removed device photos.
        await widget.library.getAlbums();
        final favorites = await widget.library.findPhotosByIds(_favoriteIds);
        if (!mounted) return;
        setState(() {
          _favoritePhotos = favorites;
          _favoritesLoaded = true;
          _loadingFavorites = false;
        });
      } catch (error, stackTrace) {
        developer.log(
          'Could not refresh favorite photos.',
          name: 'photos.favorites',
          error: error,
          stackTrace: stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _loadingFavorites = false;
          _error = 'Could not refresh favorites (${error.runtimeType}). Pull down to retry.';
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final albums = await widget.library.getAlbums();
      final refreshedAlbum = albums.firstWhere(
        (album) => album.id == _activeAlbum.id,
        orElse: () => albums.firstWhere(
          (album) => album.isAll,
          orElse: () => _activeAlbum,
        ),
      );
      final photos = await widget.library.getPhotos(
        albumId: refreshedAlbum.id,
        page: 0,
        pageSize: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _albums = albums;
        _activeAlbum = refreshedAlbum;
        _photos = photos;
        _page = 0;
        _hasMore = photos.length == _pageSize;
        _loading = false;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Could not refresh the photo library.',
        name: 'photos.library',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not refresh photos (${error.runtimeType}). '
            'Check the app’s photo permissions, then pull down to retry.';
      });
    }
  }

  Future<void> _openAlbum(LibraryAlbum album) async {
    _albumOriginTab = _selectedTab;
    setState(() {
      _openedFromAlbums = true;
      _selectionMode = false;
      _selectedPhotoIds.clear();
      _allSelected = false;
      _activeAlbum = album;
      _selectedTab = 0;
      _loading = true;
      _loadingMore = false;
      _page = 0;
      _photos = const [];
      _error = null;
    });

    try {
      final photos = await widget.library.getPhotos(
        albumId: album.id,
        page: 0,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _page = 0;
        _hasMore = photos.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open this album.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading ||
        _loadingMore ||
        !_hasMore ||
        !_hasAccess ||
        _selectedTab != 0) {
      return;
    }

    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final nextPhotos = await widget.library.getPhotos(
        albumId: _activeAlbum.id,
        page: nextPage,
        pageSize: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _photos = [..._photos, ...nextPhotos];
        _page = nextPage;
        _hasMore = nextPhotos.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _showMessage('Could not load more photos. Scroll to retry.');
    }
  }

  Future<void> _selectTab(int index) async {
    final leavingAlbum = _openedFromAlbums;
    setState(() {
      _selectedTab = index;
      _selectionMode = false;
      _selectedPhotoIds.clear();
      _selectingAll = false;
      _allSelected = false;
      if (leavingAlbum) {
        _openedFromAlbums = false;
        _activeAlbum = _allPhotosAlbum;
        _page = 0;
        _hasMore = false;
        if (index == 0) _loading = true;
      }
    });
    if (leavingAlbum && index == 0) await _refresh();
    if (index == 2 && !_favoritesLoaded) await _loadFavorites();
  }

  Future<void> _handleSystemBack() async {
    if (_selectionMode) {
      _clearSelection();
      return;
    }
    if (_openedFromAlbums) {
      await _selectTab(_albumOriginTab);
      return;
    }
    if (_selectedTab != 0) await _selectTab(0);
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPhotoIds.clear();
      _selectingAll = false;
      _allSelected = false;
    });
  }

  void _beginPhotoSelection(GalleryPhoto photo) {
    setState(() {
      _selectionMode = true;
      _selectedPhotoIds..clear()..add(photo.id);
      _allSelected = false;
    });
  }

  void _togglePhotoSelection(GalleryPhoto photo) {
    setState(() {
      if (_selectedPhotoIds.contains(photo.id)) {
        _selectedPhotoIds.remove(photo.id);
      } else {
        _selectedPhotoIds.add(photo.id);
      }
      _selectionMode = _selectedPhotoIds.isNotEmpty;
      _allSelected = false;
    });
  }

  Future<List<GalleryPhoto>> _loadAllPhotosInCurrentScope() async {
    if (_selectedTab == 2) return List<GalleryPhoto>.from(_favoritePhotos);
    final result = <GalleryPhoto>[];
    var page = 0;
    while (true) {
      final batch = await widget.library.getPhotos(
        albumId: _activeAlbum.id,
        page: page,
        pageSize: _pageSize,
      );
      result.addAll(batch);
      if (batch.length < _pageSize) break;
      page++;
    }
    return result;
  }

  Future<void> _selectAllPhotosInScope() async {
    if (_deleting || _selectingAll) return;
    if (_allSelected) {
      _clearSelection();
      return;
    }
    setState(() => _selectingAll = true);
    try {
      final allPhotos = await _loadAllPhotosInCurrentScope();
      if (!mounted) return;
      if (allPhotos.isEmpty) {
        setState(() { _selectingAll = false; _allSelected = false; });
        _showMessage('There are no photos to select.');
        return;
      }
      setState(() {
        _selectedPhotoIds..clear()..addAll(allPhotos.map((photo) => photo.id));
        _selectionMode = true;
        _selectingAll = false;
        _allSelected = true;
      });
    } catch (error, stackTrace) {
      developer.log('Could not select all photos in this view.', name: 'photos.selection', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _selectingAll = false);
      _showMessage('Could not select all photos. Try again.');
    }
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotoIds.isEmpty || _deleting) return;
    final requestedIds = Set<String>.from(_selectedPhotoIds);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('Delete permanently?'),
        content: Text(requestedIds.length.toString() +
            (requestedIds.length == 1
                ? ' photo will be deleted from this device. This cannot be undone.'
                : ' photos will be deleted from this device. This cannot be undone.')),
        actions: [
          TextButton(
            key: const Key('cancelDeletePhotosButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmDeletePhotosButton'),
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    Set<String> deletedIds;
    try {
      deletedIds = (await widget.library.deletePhotos(requestedIds.toList()))
          .toSet().intersection(requestedIds);
    } catch (error, stackTrace) {
      developer.log('Could not permanently delete selected photos.', name: 'photos.deletion', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _deleting = false);
      _showMessage('Delete failed. No photos were removed from the app view.');
      return;
    }
    if (deletedIds.isEmpty) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _showMessage('No photos were deleted. Android may have canceled its confirmation.');
      return;
    }

    final nextFavoriteIds = Set<String>.from(_favoriteIds)..removeAll(deletedIds);
    try {
      await widget.favoritesStore.save(nextFavoriteIds);
    } catch (error, stackTrace) {
      developer.log('Could not persist favorites after deletion.', name: 'photos.favorites', error: error, stackTrace: stackTrace);
    }

    var refreshedAlbums = _albums;
    var refreshedAlbum = _activeAlbum;
    var refreshedPhotos = _photos.where((photo) => !deletedIds.contains(photo.id)).toList();
    var refreshedFavorites = _favoritePhotos.where((photo) => !deletedIds.contains(photo.id)).toList();
    try {
      refreshedAlbums = await widget.library.getAlbums();
      refreshedAlbum = refreshedAlbums.firstWhere(
        (album) => album.id == _activeAlbum.id,
        orElse: () => refreshedAlbums.firstWhere((album) => album.isAll, orElse: () => _activeAlbum),
      );
      if (_selectedTab == 0) {
        refreshedPhotos = await widget.library.getPhotos(albumId: refreshedAlbum.id, page: 0, pageSize: _pageSize);
      }
      refreshedFavorites = await widget.library.findPhotosByIds(nextFavoriteIds);
    } catch (error, stackTrace) {
      developer.log('Could not fully refresh library after deletion.', name: 'photos.deletion', error: error, stackTrace: stackTrace);
    }
    if (!mounted) return;
    setState(() {
      _albums = refreshedAlbums;
      _activeAlbum = refreshedAlbum;
      _favoriteIds = nextFavoriteIds;
      _favoritePhotos = refreshedFavorites;
      _favoritesLoaded = true;
      if (_selectedTab == 0) {
        _photos = refreshedPhotos;
        _page = 0;
        _hasMore = refreshedPhotos.length == _pageSize;
      }
      _selectedPhotoIds.removeAll(deletedIds);
      _selectionMode = false;
      _selectingAll = false;
      _allSelected = false;
      _deleting = false;
      _loading = false;
    });
    final failedCount = requestedIds.length - deletedIds.length;
    _showMessage(failedCount == 0
        ? '${deletedIds.length} photos deleted permanently.'
        : '${deletedIds.length} deleted. $failedCount could not be deleted.');
  }

  Future<void> _loadFavorites() async {
    if (_loadingFavorites || _favoritesLoaded) return;

    setState(() => _loadingFavorites = true);
    try {
      final matches = await widget.library.findPhotosByIds(_favoriteIds);
      if (!mounted) return;
      setState(() {
        _favoritePhotos = matches;
        _favoritesLoaded = true;
        _loadingFavorites = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFavorites = false);
      _showMessage('Could not load your favorites.');
    }
  }

  Future<void> _setFavorite(GalleryPhoto photo, bool isFavorite) async {
    final nextIds = Set<String>.from(_favoriteIds);
    if (isFavorite) {
      nextIds.add(photo.id);
    } else {
      nextIds.remove(photo.id);
    }

    setState(() {
      _favoriteIds = nextIds;
      if (_favoritesLoaded) {
        if (isFavorite) {
          if (!_favoritePhotos.any((item) => item.id == photo.id)) {
            _favoritePhotos = [photo, ..._favoritePhotos];
          }
        } else {
          _favoritePhotos =
              _favoritePhotos.where((item) => item.id != photo.id).toList();
        }
      }
    });

    try {
      await widget.favoritesStore.save(nextIds);
    } catch (_) {
      if (mounted) _showMessage('Could not save favorites on this device.');
    }
  }

  void _openPhoto(GalleryPhoto photo) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PhotoViewer(
          photo: photo,
          initiallyFavorite: _favoriteIds.contains(photo.id),
          onFavoriteChanged: (value) => _setFavorite(photo, value),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String get _title {
    if (_selectedTab == 1) return 'Albums';
    if (_selectedTab == 2) return 'Favorites';
    if (!_activeAlbum.isAll) return _activeAlbum.name;
    return 'Photos';
  }

  String get _subtitle {
    if (!_hasAccess) return 'Private photo library';
    if (_selectedTab == 1) return '${_albums.length} albums on this device';
    if (_selectedTab == 2) {
      return '${_favoriteIds.length} saved favorites';
    }
    final count = _activeAlbum.count;
    return count == 1 ? '1 photo on this device' : '$count photos on this device';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_interceptsSystemBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleSystemBack();
      },
      child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
              child: Row(
                children: [
                  if (_selectionMode) ...[
                    IconButton(
                      key: const Key('cancelPhotoSelectionButton'),
                      tooltip: 'Cancel selection',
                      onPressed: _deleting ? null : _clearSelection,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '${_selectedPhotoIds.length} selected',
                        key: const Key('selectionCount'),
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      key: const Key('selectAllPhotosButton'),
                      onPressed: _deleting || _selectingAll ? null : _selectAllPhotosInScope,
                      child: _selectingAll
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_allSelected ? 'Clear all' : 'Select all'),
                    ),
                    IconButton(
                      key: const Key('deleteSelectedPhotosButton'),
                      tooltip: 'Delete permanently',
                      onPressed: _deleting || _selectedPhotoIds.isEmpty ? null : _deleteSelectedPhotos,
                      icon: _deleting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.delete_forever_outlined),
                    ),
                  ] else ...[
                    if (_openedFromAlbums)
                      IconButton(
                        key: const Key('backToAlbums'),
                        tooltip: 'Albums',
                        onPressed: () => _selectTab(_albumOriginTab),
                        icon: const Icon(Icons.arrow_back_rounded),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(left: 8, right: 12),
                        child: Icon(Icons.photo_library_rounded, size: 29),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_title, key: const Key('pageTitle'), maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -0.7)),
                          const SizedBox(height: 2),
                          Text(_subtitle, style: const TextStyle(color: Color(0xFF9B9B9B), fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                key: const Key('pullToRefresh'),
                onRefresh: _refresh,
                color: Colors.white,
                backgroundColor: const Color(0xFF202020),
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _selectionMode ? null : NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) { _selectTab(index); },
        destinations: const [
          NavigationDestination(key: Key('photosTab'), icon: Icon(Icons.photo_outlined), selectedIcon: Icon(Icons.photo), label: 'Photos'),
          NavigationDestination(key: Key('albumsTab'), icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Albums'),
          NavigationDestination(key: Key('favoritesTab'), icon: Icon(Icons.favorite_border_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'Favorites'),
        ],
      ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        message: _error!,
        actionLabel: 'Try again',
        onAction: _start,
        secondaryLabel: 'Open settings',
        onSecondary: _openSettings,
      );
    }

    if (!_hasAccess || _permissionNeeded) {
      return _MessageState(
        icon: Icons.photo_library_outlined,
        title: 'Your photos, kept private',
        message:
            'Allow access to view pictures stored on this device. Photos are not uploaded anywhere.',
        actionLabel: 'Allow photo access',
        onAction: _start,
        secondaryLabel: 'Open settings',
        onSecondary: _openSettings,
      );
    }

    if (_selectedTab == 1) return _buildAlbums();
    if (_selectedTab == 2) return _buildFavorites();
    return _buildPhotoGrid(_photos, favoritesMode: false);
  }

  Widget _buildAlbums() {
    if (_albums.isEmpty) {
      return const _MessageState(
        icon: Icons.folder_off_outlined,
        title: 'No albums found',
        message: 'Albums will appear here when they contain photos.',
      );
    }

    return GridView.builder(
      key: const Key('albumsGrid'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      itemCount: _albums.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.18,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final album = _albums[index];
        return _AlbumTile(
          album: album,
          onTap: () => _openAlbum(album),
        );
      },
    );
  }

  Widget _buildFavorites() {
    if (_loadingFavorites) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_favoriteIds.isEmpty || _favoritePhotos.isEmpty) {
      return _MessageState(
        icon: Icons.favorite_border_rounded,
        title: 'Your favorites live here',
        message: _favoriteIds.isEmpty
            ? 'Tap the heart on any photo to save it here.'
            : 'Some saved photos may have been removed from your device.',
        actionLabel: 'Back to photos',
        onAction: () => _selectTab(0),
      );
    }

    return _buildPhotoGrid(_favoritePhotos, favoritesMode: true);
  }

  Widget _buildPhotoGrid(
    List<GalleryPhoto> photos, {
    required bool favoritesMode,
  }) {
    if (photos.isEmpty) {
      return _MessageState(
        icon: favoritesMode
            ? Icons.favorite_border_rounded
            : Icons.photo_outlined,
        title: favoritesMode ? 'No favorites yet' : 'No photos yet',
        message: favoritesMode
            ? 'Tap the heart on a photo to keep it close.'
            : 'Pictures on this device will show up here.',
        actionLabel: favoritesMode ? 'Back to photos' : 'Refresh library',
        onAction: favoritesMode ? () => _selectTab(0) : _refresh,
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!_selectionMode && notification is ScrollUpdateNotification &&
            notification.metrics.extentAfter < 700) {
          _loadMore();
        }
        return false;
      },
      child: GridView.builder(
        key: Key(favoritesMode ? 'favoritesGrid' : 'photosGrid'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
        itemCount: photos.length + (!favoritesMode && _loadingMore ? 1 : 0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.91,
        ),
        itemBuilder: (context, index) {
          if (index >= photos.length) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            );
          }
          final photo = photos[index];
          return _PhotoTile(
            photo: photo,
            isFavorite: _favoriteIds.contains(photo.id),
            isSelected: _selectedPhotoIds.contains(photo.id),
            selectionMode: _selectionMode,
            onTap: () => _selectionMode ? _togglePhotoSelection(photo) : _openPhoto(photo),
            onLongPress: () => _beginPhotoSelection(photo),
            onFavoriteTap: () => _setFavorite(photo, !_favoriteIds.contains(photo.id)),
          );
        },
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 58, color: const Color(0xFFBDBDBD)),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  height: 1.45,
                  color: Color(0xFFB0B0B0),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(actionLabel!),
                ),
              ],
              if (secondaryLabel != null && onSecondary != null)
                TextButton(
                  onPressed: onSecondary,
                  child: Text(
                    secondaryLabel!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.isFavorite, required this.isSelected,
    required this.selectionMode, required this.onTap, required this.onLongPress, required this.onFavoriteTap});
  final GalleryPhoto photo;
  final bool isFavorite;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(5),
    child: Material(
      color: const Color(0xFF1D1D1D),
      child: InkWell(
        key: Key('photoTile-${photo.id}'), onTap: onTap, onLongPress: onLongPress,
        child: Stack(fit: StackFit.expand, children: [
          if (photo.asset != null)
            Image(image: AssetEntityImageProvider(photo.asset!, isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(420)), fit: BoxFit.cover, gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => const _PhotoPlaceholder())
          else const _PhotoPlaceholder(),
          if (selectionMode)
            Positioned(top: 6, right: 6, child: Container(width: 27, height: 27,
              decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
              child: isSelected ? const Icon(Icons.check_rounded, color: Colors.black, size: 18) : null))
          else
            Positioned(top: 2, right: 2, child: IconButton(
              key: Key('favorite-${photo.id}'), tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
              onPressed: onFavoriteTap, visualDensity: VisualDensity.compact, padding: const EdgeInsets.all(5),
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              icon: Icon(isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 19,
                color: Colors.white, shadows: const [Shadow(blurRadius: 8, color: Colors.black)]))),
          if (photo.createdAt != null)
            Positioned(bottom: 5, left: 6, right: 6, child: Text(_formatDate(photo.createdAt!), maxLines: 1,
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white,
                shadows: [Shadow(blurRadius: 6, color: Colors.black)]))),
        ]),
      ),
    ),
  );
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF202020),
      child: Center(
        child: Icon(
          Icons.landscape_outlined,
          size: 32,
          color: Color(0xFF555555),
        ),
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.album,
    required this.onTap,
  });

  final LibraryAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF181818),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('album-${album.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: Icon(
                    album.isAll
                        ? Icons.photo_library_rounded
                        : Icons.folder_rounded,
                    size: 53,
                    color: const Color(0xFFE2E2E2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                album.count == 1 ? '1 photo' : '${album.count} photos',
                style: const TextStyle(
                  color: Color(0xFF969696),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.photo,
    required this.initiallyFavorite,
    required this.onFavoriteChanged,
  });

  final GalleryPhoto photo;
  final bool initiallyFavorite;
  final ValueChanged<bool> onFavoriteChanged;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

/// Full-viewport image canvas. The child always has the viewport's size;
/// the image itself is centered with BoxFit.contain. InteractiveViewer can
/// therefore preserve the user's pinch focal point for portrait and landscape
/// images alike, without starting from an offset intrinsic-size rectangle.
class ZoomableImageCanvas extends StatefulWidget {
  const ZoomableImageCanvas({super.key, required this.child});

  final Widget child;

  @override
  State<ZoomableImageCanvas> createState() => _ZoomableImageCanvasState();
}

class _ZoomableImageCanvasState extends State<ZoomableImageCanvas> {
  final TransformationController _transformationController =
      TransformationController();
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_handleTransformChanged);
  }

  void _handleTransformChanged() {
    final nextScale = _transformationController.value.getMaxScaleOnAxis();
    if (!mounted || (nextScale - _scale).abs() < 0.015) return;
    setState(() => _scale = nextScale);
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        key: const Key('photoZoomCanvas'),
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _resetZoom,
            child: InteractiveViewer(
              key: const Key('photoZoomViewer'),
              transformationController: _transformationController,
              constrained: true,
              alignment: Alignment.center,
              minScale: 1,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(1000),
              clipBehavior: Clip.none,
              child: SizedBox.expand(child: widget.child),
            ),
          ),
          if (_scale > 1.015)
            Positioned(
              right: 16,
              bottom: 22,
              child: SafeArea(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.7),
                  shape: const CircleBorder(),
                  child: IconButton(
                    key: const Key('resetZoomButton'),
                    tooltip: 'Reset zoom',
                    onPressed: _resetZoom,
                    icon: const Icon(Icons.center_focus_strong_rounded),
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoViewerState extends State<PhotoViewer> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initiallyFavorite;
  }

  void _toggleFavorite() {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    widget.onFavoriteChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.photo.asset;
    final title = widget.photo.createdAt == null
        ? 'Photo'
        : _formatDate(widget.photo.createdAt!);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        key: const Key('photoViewerCanvas'),
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: asset == null
                ? const Center(child: _PhotoPlaceholder())
                : ZoomableImageCanvas(
                    child: Image(
                      image: AssetEntityImageProvider(
                        asset,
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize.square(2400),
                      ),
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const _PhotoPlaceholder(),
                    ),
                  ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: 58,
                color: Colors.black.withValues(alpha: 0.55),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('viewerBack'),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('viewerFavorite'),
                      onPressed: _toggleFavorite,
                      tooltip:
                          _isFavorite ? 'Remove favorite' : 'Add favorite',
                      icon: Icon(
                        _isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$local.year-$month-$day';
}
