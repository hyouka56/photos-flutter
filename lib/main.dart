import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'photo_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhotosApp());
}

class PhotosApp extends StatelessWidget {
  const PhotosApp({super.key, this.library});

  final PhotoLibrary? library;

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
      home: PhotosHome(library: library ?? PhotoManagerLibrary()),
    );
  }
}

class PhotosHome extends StatefulWidget {
  const PhotosHome({super.key, required this.library});

  final PhotoLibrary library;

  @override
  State<PhotosHome> createState() => _PhotosHomeState();
}

class _PhotosHomeState extends State<PhotosHome> {
  static const _pageSize = 60;

  bool _loading = true;
  bool _loadingMore = false;
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
      final hasAccess = await widget.library.requestAccess();
      if (!mounted) return;

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

    var refreshedAlbums = _albums;
    var refreshedAlbum = _activeAlbum;
    var refreshedPhotos = _photos.where((photo) => !deletedIds.contains(photo.id)).toList();
    try {
      refreshedAlbums = await widget.library.getAlbums();
      refreshedAlbum = refreshedAlbums.firstWhere(
        (album) => album.id == _activeAlbum.id,
        orElse: () => refreshedAlbums.firstWhere((album) => album.isAll, orElse: () => _activeAlbum),
      );
      if (_selectedTab == 0) {
        refreshedPhotos = await widget.library.getPhotos(albumId: refreshedAlbum.id, page: 0, pageSize: _pageSize);
      }
    } catch (error, stackTrace) {
      developer.log('Could not fully refresh library after deletion.', name: 'photos.deletion', error: error, stackTrace: stackTrace);
    }
    if (!mounted) return;
    setState(() {
      _albums = refreshedAlbums;
      _activeAlbum = refreshedAlbum;
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

  void _openPhoto(GalleryPhoto photo) {
    final photos = List<GalleryPhoto>.from(_photos);
    var initialIndex = photos.indexWhere((item) => item.id == photo.id);
    if (initialIndex < 0) {
      photos.add(photo);
      initialIndex = photos.length - 1;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PhotoViewer(
          photos: photos,
          initialIndex: initialIndex,
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
    if (!_activeAlbum.isAll) return _activeAlbum.name;
    return 'Photos';
  }

  String get _subtitle {
    if (!_hasAccess) return 'Private photo library';
    if (_selectedTab == 1) return '${_albums.length} albums on this device';
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
    return _buildPhotoGrid(_photos);
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

  Widget _buildPhotoGrid(List<GalleryPhoto> photos) {
    if (photos.isEmpty) {
      return _MessageState(
        icon: Icons.photo_outlined,
        title: 'No photos yet',
        message: 'Pictures on this device will show up here.',
        actionLabel: 'Refresh library',
        onAction: _refresh,
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
        key: const Key('photosGrid'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
        itemCount: photos.length + (_loadingMore ? 1 : 0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.91,
        ),
        itemBuilder: (context, index) {
          if (index >= photos.length) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            );
          }
          final photo = photos[index];
          return _PhotoTile(
            photo: photo,
            isSelected: _selectedPhotoIds.contains(photo.id),
            selectionMode: _selectionMode,
            onTap: () => _selectionMode ? _togglePhotoSelection(photo) : _openPhoto(photo),
            onLongPress: () => _beginPhotoSelection(photo),
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
  const _PhotoTile({
    required this.photo,
    required this.isSelected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });
  final GalleryPhoto photo;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
              thumbnailSize: const ThumbnailSize.square(420)),
              semanticLabel: photo.createdAt == null
                  ? 'Photo thumbnail'
                  : 'Photo taken ${_formatDate(photo.createdAt!)}',
              fit: BoxFit.cover, gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => const _PhotoPlaceholder())
          else const _PhotoPlaceholder(),
          if (selectionMode)
            Positioned(top: 6, right: 6, child: Container(width: 27, height: 27,
              decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
              child: isSelected ? const Icon(Icons.check_rounded, color: Colors.black, size: 18) : null)),
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
  const PhotoViewer({super.key, required this.photos, required this.initialIndex});

  final List<GalleryPhoto> photos;
  final int initialIndex;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

/// Full-viewport image canvas with focal-point-correct zooming.
class ZoomableImageCanvas extends StatefulWidget {
  const ZoomableImageCanvas({
    super.key,
    required this.child,
    this.onScaleChanged,
  });

  final Widget child;
  final ValueChanged<double>? onScaleChanged;

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
    final matrix = _transformationController.value;
    final nextScale = matrix.getMaxScaleOnAxis();
    if (!mounted) return;

    if (nextScale <= 1.015) {
      final hasResidualTransform = (nextScale - 1).abs() > 0.001 ||
          matrix.entry(0, 3).abs() > 0.5 ||
          matrix.entry(1, 3).abs() > 0.5;
      if (hasResidualTransform) {
        _transformationController.value = Matrix4.identity();
        return;
      }
      if (_scale != 1) {
        setState(() => _scale = 1);
        widget.onScaleChanged?.call(1);
      }
      return;
    }

    if ((nextScale - _scale).abs() < 0.015) return;
    setState(() => _scale = nextScale);
    widget.onScaleChanged?.call(nextScale);
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
    return Stack(
      key: widget.key == null
          ? const Key('photoZoomCanvas')
          : ValueKey<String>('photoZoomCanvas-${widget.key}'),
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _resetZoom,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Photo zoom area',
            hint: 'Pinch to zoom. Double tap to reset zoom.',
            customSemanticsActions: {
              CustomSemanticsAction(label: 'Reset zoom'): _resetZoom,
            },
            child: InteractiveViewer(
            key: widget.key == null
              ? const Key('photoZoomViewer')
              : ValueKey<String>('photoZoomViewer-${widget.key}'),
            transformationController: _transformationController,
            constrained: true,
            minScale: 1,
            maxScale: 8,
            boundaryMargin: const EdgeInsets.all(1000),
            clipBehavior: Clip.none,
            // Null alignment keeps focal calculations and rendering on the
            // same top-left transform origin.
            child: SizedBox.expand(child: widget.child),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _controlsVisible = false;
  bool _controlsVisibleAtPointerDown = false;
  Timer? _hideControlsTimer;
  double _currentScale = 1;
  int _canvasVersion = 0;

  final Set<int> _activePointers = <int>{};
  Offset? _swipeStart;
  bool _swipeStartedAtDefaultScale = false;
  bool _multiTouchGesture = false;

  GalleryPhoto get _currentPhoto => widget.photos[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _setSystemUiMode(immersive: true);
  }

  static const MethodChannel _systemUiChannel = MethodChannel('photos/system_ui');

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _setSystemUiMode(immersive: false);
    _pageController.dispose();
    super.dispose();
  }

  void _setSystemUiMode({required bool immersive}) {
    unawaited(_applySystemUiMode(immersive: immersive));
  }

  Future<void> _applySystemUiMode({required bool immersive}) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } on MissingPluginException {
      // Some widget-test bindings do not register system UI platform methods.
    } on PlatformException {
      // The Android channel remains a fallback for the viewer.
    }
    try {
      await _systemUiChannel.invokeMethod<void>(immersive ? 'immersive' : 'edgeToEdge');
    } on MissingPluginException {
      // This Android-only method channel is not registered in widget tests.
    } on PlatformException {
      // Keep the viewer usable if the platform implementation fails.
    }
  }

  void _showControls() {
    _hideControlsTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _setSystemUiMode(immersive: false);
    _hideControlsTimer = Timer(const Duration(milliseconds: 2300), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
      _setSystemUiMode(immersive: true);
      _hideControlsTimer = null;
    });
  }

  void _handleTap() {
    if (_controlsVisibleAtPointerDown) {
      _hideControlsTimer?.cancel();
      setState(() => _controlsVisible = false);
      _setSystemUiMode(immersive: true);
      _hideControlsTimer = null;
    } else {
      _showControls();
    }
  }

  void _handlePageChanged(int index) {
    final changed = index != _currentIndex;
    setState(() {
      _currentIndex = index;
      _currentScale = 1;
      _canvasVersion++;
    });
    if (changed) _showControls();
  }

  void _handleScaleChanged(String photoId, double scale) {
    if (_currentPhoto.id == photoId) {
      _currentScale = scale;
      if (scale > 1.015) _showControls();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _controlsVisibleAtPointerDown = _controlsVisible;
    _showControls();
    if (_activePointers.isEmpty) {
      _swipeStart = event.localPosition;
      _swipeStartedAtDefaultScale = _currentScale <= 1.015;
      _multiTouchGesture = false;
    } else {
      _multiTouchGesture = true;
    }
    _activePointers.add(event.pointer);
  }

  void _handlePointerUp(PointerEvent event) {
    final isLastPointer =
        _activePointers.length == 1 && _activePointers.contains(event.pointer);
    if (isLastPointer &&
        _swipeStart != null &&
        !_multiTouchGesture &&
        _swipeStartedAtDefaultScale &&
        _currentScale <= 1.015) {
      final delta = event.localPosition - _swipeStart!;
      final threshold =
          (MediaQuery.sizeOf(context).width * 0.14).clamp(55.0, 100.0);
      if (delta.dx.abs() >= threshold &&
          delta.dx.abs() > delta.dy.abs() * 1.2) {
        final targetIndex =
            delta.dx < 0 ? _currentIndex + 1 : _currentIndex - 1;
        if (targetIndex >= 0 && targetIndex < widget.photos.length) {
          _pageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }

    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _swipeStart = null;
      _swipeStartedAtDefaultScale = false;
      _multiTouchGesture = false;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _multiTouchGesture = true;
    if (_activePointers.isEmpty) {
      _swipeStart = null;
      _swipeStartedAtDefaultScale = false;
      _multiTouchGesture = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _currentPhoto.createdAt == null
        ? 'Photo'
        : _formatDate(_currentPhoto.createdAt!);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: Stack(
          key: const Key('photoViewerCanvas'),
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _handleTap,
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'Photo viewer',
                hint: 'Tap to show or hide controls. Swipe horizontally to change photos. Pinch to zoom.',
                child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.photos.length,
              onPageChanged: _handlePageChanged,
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                final asset = photo.asset;
                if (asset == null) {
                  return const Center(child: _PhotoPlaceholder());
                }
                return ZoomableImageCanvas(
                  key: ValueKey<String>(
                    'photoZoom-${photo.id}-$_canvasVersion',
                  ),
                  onScaleChanged: (scale) =>
                      _handleScaleChanged(photo.id, scale),
                  child: Image(
                    image: AssetEntityImageProvider(
                      asset,
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(2400),
                    ),
                    semanticLabel: title == 'Photo'
                        ? 'Full-screen photo'
                        : 'Full-screen photo taken on $title',
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) =>
                        const _PhotoPlaceholder(),
                  ),
                );
              },
            ),
            ),
            ),
            if (_controlsVisible)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    key: const Key('viewerControls'),
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
                            key: const Key('viewerPhotoTitle'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, color: Colors.white),
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
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
