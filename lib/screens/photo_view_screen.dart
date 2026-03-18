import 'package:flutter/material.dart';
import 'package:geo_lens/utils/tactical_design.dart';
import 'package:geo_lens/services/map_tile_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:typed_data';

class PhotoViewScreen extends StatefulWidget {
  final Map<String, dynamic> photo;
  const PhotoViewScreen({super.key, required this.photo});

  @override
  State<PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<PhotoViewScreen> {
  bool _showInfo = false;

  @override
  void initState() {
    super.initState();
    // Evict cache so the watermarked file is always shown fresh
    FileImage(File(widget.photo['file_path'] as String)).evict();
  }

  Future<void> _share() async {
    final filePath = widget.photo['file_path'] as String;
    if (!await File(filePath).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found')),
        );
      }
      return;
    }
    await Share.shareXFiles([XFile(filePath)]);
  }

  @override
  Widget build(BuildContext context) {
    final String filePath = widget.photo['file_path'] as String;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showInfo ? Icons.info : Icons.info_outline,
              color: TacticalDesign.accentGreen,
            ),
            onPressed: () => setState(() => _showInfo = !_showInfo),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: TacticalDesign.accentGreen),
            onPressed: _share,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => setState(() => _showInfo = false),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Full-screen watermarked image
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Image.file(
                File(filePath),
                key: ValueKey(filePath),
                fit: BoxFit.contain,
              ),
            ),

            // Slide-up info panel (tap ℹ to toggle)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              bottom: _showInfo ? 0 : -340,
              left: 0,
              right: 0,
              child: _InfoPanel(photo: widget.photo),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPanel extends StatefulWidget {
  final Map<String, dynamic> photo;
  const _InfoPanel({required this.photo});

  @override
  State<_InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<_InfoPanel> {
  Uint8List? _tileBytes;

  @override
  void initState() {
    super.initState();
    _fetchTile();
  }

  Future<void> _fetchTile() async {
    final lat = widget.photo['latitude'] as double;
    final lng = widget.photo['longitude'] as double;
    final bytes = await MapTileService.fetchTile(lat, lng, zoom: 17);
    if (mounted && bytes != null) setState(() => _tileBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.photo['latitude'] as double;
    final lng = widget.photo['longitude'] as double;
    final address = widget.photo['address'] as String? ?? 'Unknown Location';
    final timestamp = widget.photo['timestamp'] as String? ?? '—';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      decoration: BoxDecoration(
        color: const Color(0xEE101010),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // GPS Map Camera style card
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Map thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 90,
                  height: 90,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_tileBytes != null)
                        Image.memory(_tileBytes!, fit: BoxFit.cover)
                      else
                        Container(
                          color: const Color(0xFF1E2A1A),
                          child: const Center(child: Icon(Icons.satellite_alt, color: Colors.white24, size: 26)),
                        ),
                      const Center(child: Icon(Icons.location_pin, color: Colors.red, size: 24)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(Icons.camera_alt, size: 9, color: Colors.white38),
                        const SizedBox(width: 3),
                        Text('GPS Map Camera', style: TacticalDesign.hudText.copyWith(fontSize: 9, color: Colors.white38)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Address as headline
                    Text(
                      address,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1.25),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Lat ${lat.toStringAsFixed(6)}°  Long ${lng.toStringAsFixed(6)}°',
                      style: TacticalDesign.hudText.copyWith(fontSize: 9.5, color: Colors.white70),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      timestamp,
                      style: TacticalDesign.hudText.copyWith(fontSize: 9, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Extra metadata rows
          _row(Icons.terrain_outlined,
              '${(widget.photo['altitude'] as double).toStringAsFixed(1)} m altitude'),
          _row(Icons.explore_outlined,
              '${(widget.photo['heading'] as double).toStringAsFixed(0)}° bearing'),
          if ((widget.photo['caption'] as String?)?.isNotEmpty == true)
            _row(Icons.label_outline, widget.photo['caption'] as String),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
