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
      final savedFavorites = await widget.favoritesStore.load();
      final hasAccess = await widget.library.requestAccess();

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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'We couldn’t load your photo library. Please try again.';
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
    if (!_hasAccess) {
      await _start();
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Refresh failed. Please try again.';
      });
    }
  }

  Future<void> _openAlbum(LibraryAlbum album) async {
    setState(() {
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
    setState(() => _selectedTab = index);
    if (index == 2 && !_favoritesLoaded) {
      await _loadFavorites();
    }
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
    if (_selectedTab == 1) return '$_albums.length albums on this device';
    if (_selectedTab == 2) {
      return '${_favoriteIds.length} saved favorites';
    }
    final count = _activeAlbum.count;
    return count == 1 ? '1 photo on this device' : '${count} photos on this device';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
              child: Row(
                children: [
                  if (_selectedTab == 0 && !_activeAlbum.isAll)
                    IconButton(
                      key: const Key('backToAllPhotos'),
                      tooltip: 'All photos',
                      onPressed: () => _openAlbum(
                        _albums.firstWhere(
                          (album) => album.isAll,
                          orElse: () => const LibraryAlbum(
                            id: allPhotosAlbumId,
                            name: 'All photos',
                            count: 0,
                            isAll: true,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.photo_library_rounded, size: 29),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          key: const Key('pageTitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle,
                          style: const TextStyle(
                            color: Color(0xFF9B9B9B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('refreshLibrary'),
                    tooltip: 'Refresh photos',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          _selectTab(index);
        },
        destinations: const [
          NavigationDestination(
            key: Key('photosTab'),
            icon: Icon(Icons.photo_outlined),
            selectedIcon: Icon(Icons.photo),
            label: 'Photos',
          ),
          NavigationDestination(
            key: Key('albumsTab'),
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Albums',
          ),
          NavigationDestination(
            key: Key('favoritesTab'),
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Favorites',
          ),
        ],
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
        if (notification.metrics.extentAfter < 700) {
          _loadMore();
        }
        return false;
      },
      child: GridView.builder(
        key: Key(favoritesMode ? 'favoritesGrid' : 'photosGrid'),
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
            onTap: () => _openPhoto(photo),
            onFavoriteTap: () => _setFavorite(
              photo,
              !_favoriteIds.contains(photo.id),
            ),
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
  const _PhotoTile({
    super.key,
    required this.photo,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
  });

  final GalleryPhoto photo;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Material(
        color: const Color(0xFF1D1D1D),
        child: InkWell(
          key: Key('photoTile-${photo.id}'),
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo.asset != null)
                Image(
                  image: AssetEntityImageProvider(
                    photo.asset!,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(420),
                  ),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      const _PhotoPlaceholder(),
                )
              else
                const _PhotoPlaceholder(),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  key: Key('favorite-${photo.id}'),
                  tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
                  onPressed: onFavoriteTap,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(5),
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 19,
                    color: Colors.white,
                    shadows: const [
                      Shadow(blurRadius: 8, color: Colors.black),
                    ],
                  ),
                ),
              ),
              if (photo.createdAt != null)
                Positioned(
                  bottom: 5,
                  left: 6,
                  right: 6,
                  child: Text(
                    _formatDate(photo.createdAt!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
    super.key,
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.photo.createdAt == null
              ? 'Photo'
              : _formatDate(widget.photo.createdAt!),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            key: const Key('viewerFavorite'),
            onPressed: _toggleFavorite,
            tooltip: _isFavorite ? 'Remove favorite' : 'Add favorite',
            icon: Icon(
              _isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Center(
        child: asset == null
            ? const _PhotoPlaceholder()
            : InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image(
                  image: AssetEntityImageProvider(
                    asset,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(1800),
                  ),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      const _PhotoPlaceholder(),
                ),
              ),
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
