import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geo_lens/services/database_service.dart';
import 'package:geo_lens/utils/tactical_design.dart';
import 'package:geo_lens/screens/photo_view_screen.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<Map<String, dynamic>> _photos = [];
  final Set<int> _selectedIds = {};
  bool _isSelectionMode = false;
  final GlobalKey<AnimatedGridState> _gridKey = GlobalKey<AnimatedGridState>();

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final db = Provider.of<DatabaseService>(context, listen: false);
    final photos = await db.queryAllPhotos();
    if (mounted) setState(() => _photos = photos);
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TacticalDesign.surface,
        title: const Text('PURGE DATA?', style: TextStyle(color: Colors.white, letterSpacing: 2)),
        content: Text('Permanently remove ${_selectedIds.length} items from storage?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('PURGE', style: TextStyle(color: TacticalDesign.alertRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = Provider.of<DatabaseService>(context, listen: false);
      final idsToDelete = List<int>.from(_selectedIds);
      
      // We'll simulate the "liquid" grid shift by removing items and refreshing
      // In a real high-end app, we'd use AnimatedGrid or similar.
      for (var id in idsToDelete) {
        await db.deletePhoto(id);
      }
      
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      _loadPhotos();
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_isSelectionMode ? '${_selectedIds.length} SELECTED' : 'GALLERY', style: TacticalDesign.heading.copyWith(fontSize: 16)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: TacticalDesign.alertRed),
              onPressed: _deleteSelected,
            ),
        ],
      ),
      body: _photos.isEmpty
          ? RefreshIndicator(
              onRefresh: _loadPhotos,
              color: TacticalDesign.accentGreen,
              child: ListView(
                children: [
                   SizedBox(height: MediaQuery.of(context).size.height / 3),
                   const Center(child: Text('NO ARCHIVED DATA', style: TextStyle(color: Colors.white24, letterSpacing: 2))),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadPhotos,
              color: TacticalDesign.accentGreen,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: MasonryGridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    return _StaggeredGalleryItem(
                      index: index,
                      photo: _photos[index],
                      isSelected: _selectedIds.contains(_photos[index]['id']),
                      onTap: () {
                        if (_isSelectionMode) {
                          _toggleSelection(_photos[index]['id']);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => PhotoViewScreen(photo: _photos[index])),
                          ).then((_) => _loadPhotos());
                        }
                      },
                      onLongPress: () => _toggleSelection(_photos[index]['id']),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _StaggeredGalleryItem extends StatefulWidget {
  final int index;
  final Map<String, dynamic> photo;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _StaggeredGalleryItem({
    required this.index,
    required this.photo,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_StaggeredGalleryItem> createState() => _StaggeredGalleryItemState();
}

class _StaggeredGalleryItemState extends State<_StaggeredGalleryItem> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  
  late AnimationController _selectionPulseController;

  @override
  void initState() {
    super.initState();
    // 1. Entrance Staggered Animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );

    // Delay start based on index - slower stagger
    Future.delayed(Duration(milliseconds: widget.index * 150), () {
      if (mounted) _entranceController.forward();
    });

    // 2. Selection Pulse Animation - slower pulse
    _selectionPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _selectionPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedBuilder(
            animation: _selectionPulseController,
            builder: (context, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: widget.isSelected ? [
                    BoxShadow(
                      color: TacticalDesign.accentGreen.withOpacity(0.3 + (_selectionPulseController.value * 0.4)),
                      blurRadius: 10 + (_selectionPulseController.value * 10),
                      spreadRadius: 2,
                    )
                  ] : [],
                ),
                child: Transform.scale(
                  scale: widget.isSelected ? 0.92 : 1.0,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          File(widget.photo['file_path']),
                          fit: BoxFit.cover,
                          // Force cache invalidation so gallery always shows the watermarked image
                          cacheWidth: 600,
                          key: ValueKey(widget.photo['file_path']),
                        ),
                      ),
                      if (widget.isSelected)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: TacticalDesign.accentGreen.withOpacity(0.1),
                              border: Border.all(color: TacticalDesign.accentGreen, width: 3),
                            ),
                          ),
                        ),
                      if (widget.isSelected)
                        const Positioned(
                          top: 10,
                          right: 10,
                          child: Icon(Icons.check_circle, color: TacticalDesign.accentGreen, size: 24),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
