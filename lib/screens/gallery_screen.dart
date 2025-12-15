import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

enum _GalleryFilter { photos, videos }

/// Máximo de elementos
const int kMaxPhotosPerUser = 12;
const int kMaxVideosPerUser = 4;

/// Pantalla de galería: fotos y videos cortos (<=10s)
class GalleryScreen extends StatefulWidget {
  final String uid;

  const GalleryScreen({super.key, required this.uid});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;
  String? _error;

  _GalleryFilter _filter = _GalleryFilter.photos;

  /// ids seleccionados
  final Set<String> _selectedIds = {};
  List<_GalleryItem> _lastItems = [];

  bool get _hasSelection => _selectedIds.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final userId = widget.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Galería'),
        centerTitle: true,
        actions: [
          if (_hasSelection)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDeleteSelected,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: _buildFilterBar(),
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _error = null),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('gallery')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error cargando galería: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                final items = docs
                    .map((doc) => _GalleryItem.fromDoc(doc))
                    .where(
                      (item) => _filter == _GalleryFilter.photos
                          ? !item.isVideo
                          : item.isVideo,
                    )
                    .toList();

                _lastItems = items;

                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      _filter == _GalleryFilter.photos
                          ? 'No tienes fotos aún.\nSube algunas para mostrar en tu perfil público.'
                          : 'No tienes videos aún.\nSube uno corto (máx 10s) para tu perfil.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(8.0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = _selectedIds.contains(item.id);

                    return GestureDetector(
                      onTap: () {
                        if (_hasSelection) {
                          _toggleSelection(item.id);
                        } else {
                          _openViewer(items, item);
                        }
                      },
                      onLongPress: () => _toggleSelection(item.id),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _GalleryThumbnail(item: item),
                          if (isSelected)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _uploading ? null : _showUploadOptions,
                  child: _uploading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined),
                            SizedBox(width: 8),
                            Text('Agregar a galería'),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final isPhotos = _filter == _GalleryFilter.photos;
    final isVideos = _filter == _GalleryFilter.videos;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FilterChip(
            label: 'Fotos',
            selected: isPhotos,
            onTap: () {
              setState(() {
                _filter = _GalleryFilter.photos;
                _selectedIds.clear();
              });
            },
          ),
          const SizedBox(width: 12),
          _FilterChip(
            label: 'Videos',
            selected: isVideos,
            onTap: () {
              setState(() {
                _filter = _GalleryFilter.videos;
                _selectedIds.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _confirmDeleteSelected() async {
    if (!_hasSelection) return;

    final count = _selectedIds.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar elementos'),
        content: Text(
          '¿Seguro que quieres eliminar $count elemento(s) de tu galería?\n'
          'Esto no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final userId = widget.uid;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final storage = FirebaseStorage.instance;

      for (final item in _lastItems) {
        if (_selectedIds.contains(item.id)) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('gallery')
              .doc(item.id);

          batch.delete(docRef);

          // Intenta borrar el archivo en Storage
          try {
            final ref = storage.refFromURL(item.url);
            await ref.delete();
          } catch (_) {
            // ignorar errores de storage
          }
        }
      }

      await batch.commit();

      setState(() {
        _selectedIds.clear();
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Error eliminando elementos: $e';
      });
    }
  }

  /// Muestra bottom sheet para elegir si subir fotos o video
  Future<void> _showUploadOptions() async {
    if (_uploading) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Subir fotos'),
                subtitle: const Text('Múltiples fotos, se verán en tu perfil'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAndUploadPhotos();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Subir video corto'),
                subtitle: const Text('Máx. 10 segundos, se verá en tu perfil'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAndUploadVideo();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Subir múltiples fotos a Storage
  Future<void> _pickAndUploadPhotos() async {
    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      // 1) Límite de fotos
      final int currentPhotos = _lastItems
          .where((item) => !item.isVideo)
          .length;

      if (currentPhotos >= kMaxPhotosPerUser) {
        setState(() {
          _uploading = false;
          _error =
              'Ya alcanzaste el límite de $kMaxPhotosPerUser fotos en tu galería.';
        });
        return;
      }

      final List<XFile> picked = await _picker.pickMultiImage(imageQuality: 80);

      if (picked.isEmpty) {
        setState(() => _uploading = false);
        return;
      }

      // 2) Solo subimos hasta llenar el cupo
      final int remainingSlots = kMaxPhotosPerUser - currentPhotos;
      final List<XFile> filesToUpload = picked.take(remainingSlots).toList();

      final userId = widget.uid;
      final storage = FirebaseStorage.instance;
      final galleryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('gallery');

      for (final file in filesToUpload) {
        final Uint8List bytes = await file.readAsBytes();

        final String fileName =
            'gallery_${DateTime.now().millisecondsSinceEpoch}.jpg';

        final ref = storage.ref().child('users/$userId/gallery/$fileName');

        await ref.putData(bytes);

        final url = await ref.getDownloadURL();

        await galleryRef.add({
          'url': url,
          'type': 'image',
          'status': 'approved', // 👈 antes decía 'pending'
          'createdAt': FieldValue.serverTimestamp(),
        });

        // También almacenamos la URL en el documento principal del usuario
        // para que el perfil público pueda construir un carrusel simple.
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'gallery': FieldValue.arrayUnion([url]),
        }, SetOptions(merge: true));
      }

      // 3) Si se quedaron fotos fuera, avisamos
      if (filesToUpload.length < picked.length) {
        setState(() {
          _error =
              'Solo se subieron $remainingSlots fotos (límite $kMaxPhotosPerUser).';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error subiendo foto(s): $e';
      });
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  /// Subir un video corto (máx 10s) a Storage
  Future<void> _pickAndUploadVideo() async {
    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      // 1) Límite de videos
      final int currentVideos = _lastItems.where((item) => item.isVideo).length;

      if (currentVideos >= kMaxVideosPerUser) {
        setState(() {
          _uploading = false;
          _error =
              'Ya alcanzaste el límite de $kMaxVideosPerUser videos en tu galería.';
        });
        return;
      }

      final XFile? file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 10),
      );

      if (file == null) {
        setState(() => _uploading = false);
        return;
      }

      // ====== Medir duración real del video ======
      int durationSeconds = 0;
      try {
        final controller = VideoPlayerController.file(File(file.path));
        await controller.initialize();
        final dur = controller.value.duration;
        durationSeconds = dur.inSeconds;
        await controller.dispose();
      } catch (_) {
        durationSeconds = 0;
      }

      if (durationSeconds > 10) {
        setState(() {
          _uploading = false;
          _error =
              'El video dura ${durationSeconds}s. Solo se permiten videos de máximo 10 segundos.';
        });
        return;
      }

      final userId = widget.uid;
      final storage = FirebaseStorage.instance;
      final galleryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('gallery');

      final Uint8List bytes = await file.readAsBytes();

      final String fileName =
          'gallery_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final ref = storage.ref().child('users/$userId/gallery/$fileName');

      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'video/mp4'),
      );

      final url = await uploadTask.ref.getDownloadURL();

      await galleryRef.add({
        'url': url,
        'type': 'video',
        'durationSeconds': durationSeconds,
        'status': 'approved', // 👈 antes 'pending'
        'createdAt': FieldValue.serverTimestamp(),
      });

      // También almacenamos la URL del video en el documento principal del usuario
      // para que el perfil público lo pueda listar en su carrusel de videos.
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'galleryVideos': FieldValue.arrayUnion([url]),
      }, SetOptions(merge: true));
    } catch (e) {
      setState(() {
        _error = 'Error subiendo video: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  void _openViewer(List<_GalleryItem> allItems, _GalleryItem tappedItem) {
    final initialIndex = allItems.indexWhere((i) => i.id == tappedItem.id);
    if (initialIndex == -1) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _GalleryViewer(initialIndex: initialIndex, items: allItems),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}

class _GalleryItem {
  final String id;
  final String url;
  final bool isVideo;
  final int? durationSeconds;

  _GalleryItem({
    required this.id,
    required this.url,
    required this.isVideo,
    this.durationSeconds,
  });

  factory _GalleryItem.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final type = (data['type'] ?? 'image').toString();

    return _GalleryItem(
      id: doc.id,
      url: (data['url'] ?? '') as String,
      isVideo: type == 'video',
      durationSeconds: data['durationSeconds'] is int
          ? data['durationSeconds'] as int
          : null,
    );
  }
}

class _GalleryThumbnail extends StatelessWidget {
  final _GalleryItem item;

  const _GalleryThumbnail({required this.item});

  @override
  Widget build(BuildContext context) {
    if (!item.isVideo) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          item.url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.black12,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image),
          ),
        ),
      );
    } else {
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              color: Colors.black,
              child: const Center(
                child: Icon(
                  Icons.videocam_outlined,
                  color: Colors.white70,
                  size: 32,
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 4,
            right: 4,
            child: Icon(
              Icons.play_circle_outline,
              size: 22,
              color: Colors.white,
            ),
          ),
        ],
      );
    }
  }
}

class _GalleryViewer extends StatefulWidget {
  final int initialIndex;
  final List<_GalleryItem> items;

  const _GalleryViewer({required this.initialIndex, required this.items});

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late PageController _pageController;
  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  bool _isVideoLoading = false;
  bool _isPlaying = false;

  _GalleryItem get _currentItem => widget.items[_currentIndex];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentIndex = widget.initialIndex;

    if (_currentItem.isVideo) {
      _initVideo(_currentItem.url);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initVideo(String url) async {
    setState(() {
      _isVideoLoading = true;
      _isPlaying = false;
    });

    _videoController?.dispose();
    final controller = VideoPlayerController.network(url);
    _videoController = controller;

    await controller.initialize();
    controller.setLooping(true);

    setState(() {
      _isVideoLoading = false;
      _isPlaying = true;
    });

    await controller.play();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    final item = _currentItem;
    if (item.isVideo) {
      _initVideo(item.url);
    } else {
      _videoController?.pause();
      _isPlaying = false;
    }
  }

  void _togglePlayPause() {
    final vc = _videoController;
    if (vc == null) return;

    if (vc.value.isPlaying) {
      vc.pause();
      setState(() {
        _isPlaying = false;
      });
    } else {
      vc.play();
      setState(() {
        _isPlaying = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

          if (!item.isVideo) {
            return InteractiveViewer(
              child: Center(
                child: Image.network(
                  item.url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
            );
          } else {
            if (_isVideoLoading || _videoController == null) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            return GestureDetector(
              onTap: _togglePlayPause,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                  if (!_isPlaying)
                    const Icon(
                      Icons.play_circle_outline,
                      size: 80,
                      color: Colors.white70,
                    ),
                  Positioned(
                    bottom: 24,
                    child: _VideoControlsOverlay(
                      isPlaying: _isPlaying,
                      durationText: item.durationSeconds != null
                          ? '${item.durationSeconds}s'
                          : null,
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}

class _VideoControlsOverlay extends StatelessWidget {
  final bool isPlaying;
  final String? durationText;

  const _VideoControlsOverlay({required this.isPlaying, this.durationText});

  @override
  Widget build(BuildContext context) {
    final icon = isPlaying
        ? Icons.pause_circle_outline
        : Icons.play_circle_outline;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: Colors.white70),
        if (durationText != null) const SizedBox(height: 4),
        if (durationText != null)
          Text(
            durationText!,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
      ],
    );
  }
}
