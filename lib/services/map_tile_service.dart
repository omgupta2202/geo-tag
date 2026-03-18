import 'dart:typed_data';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Fetches a real satellite tile from Esri World Imagery (free, no API key).
/// Falls back to null on any network error so the watermark still renders.
class MapTileService {
  // Esri World Imagery — free satellite tiles, no key required
  static const String _esriUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'World_Imagery/MapServer/tile/{z}/{y}/{x}';

  // Fallback: OpenTopoMap (also free)
  static const String _fallbackUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Returns raw PNG/JPEG bytes of a 256×256 satellite tile,
  /// or null if the fetch fails.
  static Future<Uint8List?> fetchTile(double lat, double lng,
      {int zoom = 17}) async {
    try {
      final tile = _latLngToTile(lat, lng, zoom);
      final url = _esriUrl
          .replaceAll('{z}', '$zoom')
          .replaceAll('{y}', '${tile.y}')
          .replaceAll('{x}', '${tile.x}');

      final response = await http
          .get(Uri.parse(url), headers: {
            'User-Agent': 'GeoLens/1.0 (Flutter)',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          })
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }

      // Try fallback
      return await _fetchFallback(tile, zoom);
    } catch (e) {
      debugPrint('MapTileService error: $e');
      return null;
    }
  }

  static Future<Uint8List?> _fetchFallback(_TileCoord tile, int zoom) async {
    try {
      final url = _fallbackUrl
          .replaceAll('{z}', '$zoom')
          .replaceAll('{x}', '${tile.x}')
          .replaceAll('{y}', '${tile.y}');
      final response = await http
          .get(Uri.parse(url), headers: {
            'User-Agent': 'GeoLens/1.0 (Flutter)',
            'Cache-Control': 'no-cache',
          })
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// Converts lat/lng to OSM/Esri tile coordinates at given zoom.
  static _TileCoord _latLngToTile(double lat, double lng, int zoom) {
    final n = math.pow(2, zoom).toDouble();
    final x = ((lng + 180.0) / 360.0 * n).floor();
    final latRad = lat * math.pi / 180.0;
    final y =
        ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
                2.0 *
                n)
            .floor();
    return _TileCoord(x.clamp(0, (n - 1).toInt()), y.clamp(0, (n - 1).toInt()));
  }
}

class _TileCoord {
  final int x, y;
  const _TileCoord(this.x, this.y);
}
