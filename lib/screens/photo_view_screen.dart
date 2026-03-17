import 'package:flutter/material.dart';
import 'package:geo_lens/utils/tactical_design.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:geo_lens/services/database_service.dart';
import 'dart:io';

class PhotoViewScreen extends StatelessWidget {
  final Map<String, dynamic> photo;

  const PhotoViewScreen({super.key, required this.photo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('DATA ANALYSIS', style: TacticalDesign.heading.copyWith(fontSize: 14)),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: TacticalDesign.accentGreen),
            onPressed: () => Share.shareXFiles([XFile(photo['file_path'])]),
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(child: Image.file(File(photo['file_path']))),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(photo['caption'] ?? 'NO CAPTION', style: TacticalDesign.hudText.copyWith(color: TacticalDesign.accentGreen, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 12),
                   _metaRow('ADDRESS', photo['address'] ?? 'UNKNOWN', isLong: true),
                   _metaRow('LAT/LNG', '${photo['latitude'].toStringAsFixed(6)}, ${photo['longitude'].toStringAsFixed(6)}'),
                   _metaRow('ALTITUDE', '${photo['altitude'].toStringAsFixed(1)}m'),
                   _metaRow('BEARING', '${photo['heading'].toStringAsFixed(0)}°'),
                   _metaRow('TIMESTAMP', photo['timestamp']),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value, {bool isLong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: isLong ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Text(label, style: TacticalDesign.hudText.copyWith(fontSize: 10, color: Colors.white54)),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              value,
              style: TacticalDesign.hudText.copyWith(fontSize: 10),
              textAlign: TextAlign.end,
              maxLines: isLong ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
