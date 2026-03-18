import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:geo_lens/services/location_service.dart';
import 'package:geo_lens/services/sensor_service.dart';
import 'package:geo_lens/services/database_service.dart';
import 'package:geo_lens/services/settings_service.dart';
import 'package:geo_lens/services/watermark_service.dart';
import 'package:geo_lens/services/map_tile_service.dart';
import 'package:geo_lens/utils/rolling_digit.dart';
import 'package:geo_lens/utils/tactical_design.dart';
import 'package:geo_lens/screens/settings_screen.dart';
import 'package:geo_lens/screens/gallery_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;

  // Zoom Logic
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 5.0;
  double _currentZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  bool _showZoomIndicator = false;
  Timer? _zoomTimer;

  // Animation Controllers
  late AnimationController _shutterController;
  late AnimationController _gpsPulseController;
  late AnimationController _rippleController;

  final GlobalKey _galleryButtonKey = GlobalKey();

  // Pre-cached map tile — fetched as soon as GPS locks, reused at capture time
  Uint8List? _cachedMapTile;
  String? _cachedTileKey;
  LocationService? _locationService;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _shutterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _gpsPulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _rippleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));

    // Attach location listener after first frame so Provider is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locationService = Provider.of<LocationService>(context, listen: false);
      _locationService!.addListener(_onLocationChanged);
      // Trigger immediately if GPS is already locked
      if (_locationService!.currentPosition != null) _onLocationChanged();
    });
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(_cameras![0], ResolutionPreset.high, enableAudio: false);
        await _controller!.initialize();
        _minZoomLevel = await _controller!.getMinZoomLevel();
        _maxZoomLevel = await _controller!.getMaxZoomLevel();
        if (!mounted) return;
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  @override
  void dispose() {
    _locationService?.removeListener(_onLocationChanged);
    _shutterController.dispose();
    _gpsPulseController.dispose();
    _rippleController.dispose();
    _zoomTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    final pos = _locationService?.currentPosition;
    if (pos == null) return;
    final key = '${pos.latitude.toStringAsFixed(3)}_${pos.longitude.toStringAsFixed(3)}';
    if (key == _cachedTileKey) return;
    _cachedTileKey = key;
    MapTileService.fetchTile(pos.latitude, pos.longitude, zoom: 17).then((bytes) {
      if (mounted && bytes != null && _cachedTileKey == key) {
        _cachedMapTile = bytes;
      }
    });
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoomLevel = _currentZoomLevel;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_controller == null) return;
    double newZoom = (_baseZoomLevel * details.scale).clamp(_minZoomLevel, _maxZoomLevel);
    setState(() {
      _currentZoomLevel = newZoom;
      _showZoomIndicator = true;
    });
    _controller!.setZoomLevel(newZoom);
    _resetZoomTimer();
  }

  void _resetZoomTimer() {
    _zoomTimer?.cancel();
    _zoomTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showZoomIndicator = false);
    });
  }

  void _resetZoom() {
    setState(() {
      _currentZoomLevel = 1.0;
      _showZoomIndicator = true;
    });
    _controller?.setZoomLevel(1.0);
    _resetZoomTimer();
    HapticFeedback.mediumImpact();
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    _shutterController.forward().then((_) => _shutterController.reverse());
    _rippleController.forward(from: 0.0);
    HapticFeedback.heavyImpact();

    try {
      final XFile imageFile = await _controller!.takePicture();
      final Uint8List originalBytes = await imageFile.readAsBytes();
      final location = Provider.of<LocationService>(context, listen: false);
      final sensor = Provider.of<SensorService>(context, listen: false);
      final db = Provider.of<DatabaseService>(context, listen: false);
      final settings = Provider.of<SettingsService>(context, listen: false);
      final now = DateTime.now();
      final timeZoneOffset = now.timeZoneOffset;
      final sign = timeZoneOffset.isNegative ? '-' : '+';
      final tzHours = timeZoneOffset.inHours.abs().toString().padLeft(2, '0');
      final tzMins = (timeZoneOffset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      final timestamp = DateFormat("EEEE, dd/MM/yyyy hh:mm a").format(now) + ' GMT $sign$tzHours:$tzMins';
      
      // Save watermarked file FIRST, then trigger fly animation with correct path
      final directory = await getApplicationDocumentsDirectory();
      final String filePath = path.join(directory.path, 'GEOLENS_${DateTime.now().millisecondsSinceEpoch}.jpg');

      // Use pre-cached tile (fetched when GPS locked) — falls back to a
      // fresh fetch only if cache is empty (very first capture before tile loads).
      final Uint8List? mapTile = _cachedMapTile ?? await MapTileService.fetchTile(
        location.currentPosition?.latitude ?? 0.0,
        location.currentPosition?.longitude ?? 0.0,
        zoom: 17,
      );

      final Uint8List burnedBytes = await WatermarkService.burnMetadata(
        WatermarkParams(
          imageBytes: originalBytes,
          latitude: location.currentPosition?.latitude ?? 0.0,
          longitude: location.currentPosition?.longitude ?? 0.0,
          altitude: location.currentPosition?.altitude ?? 0.0,
          heading: sensor.heading,
          caption: settings.customCaption,
          timestamp: timestamp,
          address: location.currentAddress ?? 'Unknown Location',
          cityState: location.cityState ?? location.currentAddress ?? 'Unknown Location',
          country: location.country ?? '',
          visibility: settings.overlays,
          mapTileBytes: mapTile,
        ),
      );

      await File(filePath).writeAsBytes(burnedBytes);

      // Evict any cached version so gallery always loads the watermarked file
      await FileImage(File(filePath)).evict();

      // Trigger fly animation AFTER watermarked file is saved
      _triggerFlyToGallery(filePath);

      await db.insertPhoto({
        'file_path': filePath,
        'latitude': location.currentPosition?.latitude ?? 0.0,
        'longitude': location.currentPosition?.longitude ?? 0.0,
        'heading': sensor.heading,
        'altitude': location.currentPosition?.altitude ?? 0.0,
        'timestamp': timestamp,
        'caption': settings.customCaption,
        'address': location.currentAddress ?? 'UNKNOWN LOCATION',
      });
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _triggerFlyToGallery(String imagePath) {
    final overlay = Overlay.of(context);
    final renderBox = _galleryButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final Offset destination = renderBox.localToGlobal(Offset.zero);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _FlyToGalleryAnimation(
        imagePath: imagePath,
        startPosition: Offset(MediaQuery.of(context).size.width / 2 - 40, MediaQuery.of(context).size.height / 2 - 40),
        endPosition: destination,
        onComplete: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) return const Scaffold(backgroundColor: Colors.black);

    // CRITICAL: listen: false to stop build() from firing on every sensor change
    final settings = Provider.of<SettingsService>(context, listen: false);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onScaleStart: _handleScaleStart,
        onScaleUpdate: _handleScaleUpdate,
        onDoubleTap: _resetZoom,
        child: Stack(
          children: [
            // 1. Camera Viewfinder (Isolated from overlays)
            RepaintBoundary(
              child: Center(
                child: CameraPreview(_controller!),
              ),
            ),

            // Shutter Ripple Effect
            AnimatedBuilder(
              animation: _rippleController,
              builder: (context, child) {
                return IgnorePointer(
                  child: CustomPaint(
                    painter: _RipplePainter(progress: _rippleController.value),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),

            // 2. Spatial Metadata HUD (Anchored Bottom-Left)
            // Uses Consumer to only rebuild this card on sensor/location updates
            Consumer2<LocationService, SensorService>(
              builder: (context, location, sensor, child) {
                return _buildSpatialHUD(location, sensor, settings);
              },
            ),

            // 3. Zoom Scale Indicator (Right Edge)
            _buildZoomScale(),

            // 4. Control Tray
            _buildControlTray(),

            // 5. GPS Pulse Status (Top Bar)
            Consumer<LocationService>(
              builder: (context, location, child) {
                return _buildGPSStatus(location);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGPSStatus(LocationService location) {
    // Permission denied or service off — show a tappable banner
    if (location.permissionDenied || location.serviceDisabled) {
      return Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        child: GestureDetector(
          onTap: () async {
            if (location.serviceDisabled) {
              await location.openLocationSettings();
            } else {
              // Try re-requesting; if permanently denied, open app settings
              final perm = await Geolocator.checkPermission();
              if (perm == LocationPermission.deniedForever) {
                await location.openAppSettings();
              } else {
                await location.retryPermission();
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: TacticalDesign.alertRed.withOpacity(0.85),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_off, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    location.serviceDisabled
                        ? 'GPS is off — tap to enable'
                        : 'Location permission denied — tap to fix',
                    style: TacticalDesign.hudText.copyWith(fontSize: 11, color: Colors.white),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 12),
              ],
            ),
          ),
        ),
      );
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 20,
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _gpsPulseController,
            builder: (context, child) {
              return CustomPaint(
                painter: _GPSPulsePainter(
                  progress: _gpsPulseController.value,
                  color: location.isLoading ? TacticalDesign.alertRed : TacticalDesign.accentGreen,
                ),
                child: const SizedBox(width: 24, height: 24),
              );
            },
          ),
          const SizedBox(width: 12),
          Text(
            location.isLoading ? 'SEARCHING GNSS...' : 'GNSS LOCKED',
            style: TacticalDesign.hudText.copyWith(fontSize: 10, letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildSpatialHUD(LocationService location, SensorService sensor, SettingsService settings) {
    final lat = location.currentPosition?.latitude ?? 0.0;
    final lng = location.currentPosition?.longitude ?? 0.0;
    final hasLocation = location.currentPosition != null;

    final now = DateTime.now();
    final tzOffset = now.timeZoneOffset;
    final sign = tzOffset.isNegative ? '-' : '+';
    final tzH = tzOffset.inHours.abs().toString().padLeft(2, '0');
    final tzM = (tzOffset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final timestamp = DateFormat("EEEE, dd/MM/yyyy hh:mm a").format(now) + ' GMT $sign$tzH:$tzM';

    return Positioned(
      bottom: 150,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xEE101010),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Satellite map thumbnail
            SizedBox(
              width: 100,
              height: 100,
              child: hasLocation
                  ? _HudMapThumbnail(lat: lat, lng: lng)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: const Color(0xFF1E2A1A),
                        child: const Center(child: Icon(Icons.satellite_alt, color: Colors.white24, size: 30)),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            // Info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // GPS Map Camera brand (top-right)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.camera_alt, size: 9, color: Colors.white38),
                      const SizedBox(width: 3),
                      Text('GPS Map Camera', style: TacticalDesign.hudText.copyWith(fontSize: 9, color: Colors.white38)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (settings.isOverlayEnabled('location')) ...[
                    // City / State / Country headline
                    Text(
                      location.cityState ?? (location.isLoading ? 'Locating...' : 'Unknown Location'),
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, height: 1.2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Full address
                    Text(
                      location.currentAddress ?? '',
                      style: TacticalDesign.hudText.copyWith(fontSize: 9, color: const Color(0xFFCCCCCC), height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    // Coordinates with degree symbol
                    Text(
                      'Lat ${lat.toStringAsFixed(6)}°  Long ${lng.toStringAsFixed(6)}°',
                      style: TacticalDesign.hudText.copyWith(fontSize: 9.5, color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 3),
                  // Timestamp
                  Text(
                    timestamp,
                    style: TacticalDesign.hudText.copyWith(fontSize: 9, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomScale() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      right: _showZoomIndicator ? 20 : -50,
      top: MediaQuery.of(context).size.height / 3,
      child: Column(
        children: [
          Container(
            height: 200,
            width: 4,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  height: 200 * ((_currentZoomLevel - _minZoomLevel) / (_maxZoomLevel - _minZoomLevel)),
                  width: 4,
                  decoration: BoxDecoration(
                    color: TacticalDesign.accentGreen,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [const BoxShadow(color: TacticalDesign.accentGreen, blurRadius: 8)],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('${_currentZoomLevel.toStringAsFixed(1)}X', style: TacticalDesign.hudText.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildControlTray() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20, top: 20),
        color: Colors.black.withOpacity(0.8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              key: _galleryButtonKey,
              icon: const Icon(Icons.photo_library_outlined, color: Colors.white70, size: 28),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GalleryScreen())),
            ),
            GestureDetector(
              onTap: _capture,
              child: Container(
                height: 72,
                width: 72,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 28),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  _RipplePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0 || progress == 1) return;
    
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white.withOpacity((1 - progress).clamp(0, 1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(center, progress * math.max(size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) => true;
}

class _GPSPulsePainter extends CustomPainter {
  final double progress;
  final Color color;
  _GPSPulsePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color.withOpacity((1 - progress).clamp(0, 1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, 4 + (progress * 8), paint);
    canvas.drawCircle(center, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GPSPulsePainter oldDelegate) => true;
}

// ── Satellite map thumbnail for the camera HUD ────────────────────────────────
class _HudMapThumbnail extends StatefulWidget {
  final double lat;
  final double lng;
  const _HudMapThumbnail({required this.lat, required this.lng});

  @override
  State<_HudMapThumbnail> createState() => _HudMapThumbnailState();
}

class _HudMapThumbnailState extends State<_HudMapThumbnail> {
  Uint8List? _tileBytes;
  String? _currentKey;

  @override
  void initState() {
    super.initState();
    _fetchTile();
  }

  @override
  void didUpdateWidget(_HudMapThumbnail old) {
    super.didUpdateWidget(old);
    final key = '${widget.lat.toStringAsFixed(3)}_${widget.lng.toStringAsFixed(3)}';
    if (key != _currentKey) _fetchTile();
  }

  Future<void> _fetchTile() async {
    final key = '${widget.lat.toStringAsFixed(3)}_${widget.lng.toStringAsFixed(3)}';
    _currentKey = key;
    final bytes = await MapTileService.fetchTile(widget.lat, widget.lng, zoom: 17);
    if (mounted && _currentKey == key && bytes != null) {
      setState(() => _tileBytes = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_tileBytes != null)
            Image.memory(_tileBytes!, fit: BoxFit.cover)
          else
            Container(
              color: const Color(0xFF1E2A1A),
              child: const Center(child: Icon(Icons.satellite_alt, color: Colors.white24, size: 30)),
            ),
          const Center(
            child: Icon(Icons.location_pin, color: Colors.red, size: 28),
          ),
        ],
      ),
    );
  }
}

class _FlyToGalleryAnimation extends StatefulWidget {
  final String imagePath;
  final Offset startPosition;
  final Offset endPosition;
  final VoidCallback onComplete;
  const _FlyToGalleryAnimation({required this.imagePath, required this.startPosition, required this.endPosition, required this.onComplete});
  @override
  State<_FlyToGalleryAnimation> createState() => _FlyToGalleryAnimationState();
}

class _FlyToGalleryAnimationState extends State<_FlyToGalleryAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    _controller.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Bezier curve point calculation
  Offset _getBezierPath(double t) {
    // Control point adapts to screen size for consistent arc across devices
    final screenSize = MediaQuery.of(context).size;
    final Offset controlPoint = Offset(
      screenSize.width * 0.5,
      widget.startPosition.dy - screenSize.height * 0.25,
    );
    
    // Quadratic Bezier: (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2
    double x = math.pow(1 - t, 2) * widget.startPosition.dx + 
               2 * (1 - t) * t * controlPoint.dx + 
               math.pow(t, 2) * widget.endPosition.dx;
               
    double y = math.pow(1 - t, 2) * widget.startPosition.dy + 
               2 * (1 - t) * t * controlPoint.dy + 
               math.pow(t, 2) * widget.endPosition.dy;
               
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final Offset currentPos = _getBezierPath(_animation.value);
        return Positioned(
          left: currentPos.dx,
          top: currentPos.dy,
          child: Opacity(
          opacity: (1 - _animation.value).clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: _animation.value * 0.5, // Subtle rotation while flying
              child: Transform.scale(
                scale: 1 - _animation.value * 0.8,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    image: DecorationImage(image: FileImage(File(widget.imagePath)), fit: BoxFit.cover),
                    boxShadow: [const BoxShadow(color: Colors.black54, blurRadius: 15, spreadRadius: 2)],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
