import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:geo_lens/services/location_service.dart';
import 'package:geo_lens/services/sensor_service.dart';
import 'package:geo_lens/services/database_service.dart';
import 'package:geo_lens/services/settings_service.dart';
import 'package:geo_lens/services/watermark_service.dart';
import 'package:geo_lens/utils/rolling_digit.dart';
import 'package:geo_lens/utils/tactical_design.dart';
import 'package:geo_lens/screens/settings_screen.dart';
import 'package:geo_lens/screens/gallery_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _initCamera();
    _shutterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _gpsPulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _rippleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
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
    _shutterController.dispose();
    _gpsPulseController.dispose();
    _rippleController.dispose();
    _zoomTimer?.cancel();
    _controller?.dispose();
    super.dispose();
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
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      
      _triggerFlyToGallery(imageFile.path);

      final Uint8List burnedBytes = await WatermarkService.burnMetadata(
        WatermarkParams(
          imageBytes: originalBytes,
          latitude: location.currentPosition?.latitude ?? 0.0,
          longitude: location.currentPosition?.longitude ?? 0.0,
          altitude: location.currentPosition?.altitude ?? 0.0,
          heading: sensor.heading,
          caption: settings.customCaption,
          timestamp: timestamp,
          address: location.currentAddress ?? 'UNKNOWN LOCATION',
          visibility: settings.overlays,
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final String filePath = path.join(directory.path, 'GEOLENS_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(filePath).writeAsBytes(burnedBytes);

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
    // Parallax logic: Tilt the card based on phone orientation
    // We use a small factor to keep it subtle
    double tiltX = (sensor.pitch / 90.0).clamp(-0.1, 0.1);
    double tiltY = (sensor.roll / 90.0).clamp(-0.1, 0.1);

    return Positioned(
      bottom: 125,
      left: 16,
      child: Transform(
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001) // perspective
          ..rotateX(tiltX)
          ..rotateY(tiltY),
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              width: 280,
              decoration: BoxDecoration(
                color: Colors.black, // Fully opaque
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   if (settings.isOverlayEnabled('accuracy'))
                     Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('SATELLITE TELEMETRY', style: TacticalDesign.hudText.copyWith(fontSize: 8, color: TacticalDesign.accentGreen, letterSpacing: 1.5)),
                        Text('±${location.currentPosition?.accuracy.toStringAsFixed(1) ?? '0.0'}M', style: TacticalDesign.hudText.copyWith(fontSize: 9, color: Colors.white70)),
                      ],
                    ),
                  if (settings.isOverlayEnabled('accuracy'))
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Divider(color: Colors.white10, height: 1),
                    ),
                  // Current Address (Human Readable)
                  if (settings.isOverlayEnabled('location'))
                    Text(
                      location.currentAddress?.toUpperCase() ?? 'FETCHING ADDR...',
                      style: TacticalDesign.hudText.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        shadows: [const Shadow(color: Colors.black45, blurRadius: 2, offset: Offset(1, 1))],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (settings.isOverlayEnabled('location')) const SizedBox(height: 10),
                  if (settings.isOverlayEnabled('location'))
                    Row(
                      children: [
                        Expanded(child: _spatialData('LATITUDE', (location.currentPosition?.latitude ?? 0.0).toStringAsFixed(6))),
                        Expanded(child: _spatialData('LONGITUDE', (location.currentPosition?.longitude ?? 0.0).toStringAsFixed(6))),
                      ],
                    ),
                  if (settings.isOverlayEnabled('location') && (settings.isOverlayEnabled('altitude') || settings.isOverlayEnabled('compass')))
                    const SizedBox(height: 12),
                  Row(
                    children: [
                      if (settings.isOverlayEnabled('altitude'))
                        Expanded(child: _spatialData('ALTITUDE', '${location.currentPosition?.altitude.toStringAsFixed(1) ?? '0.0'}M')),
                      if (settings.isOverlayEnabled('compass'))
                        Expanded(child: _spatialData('BEARING', '${sensor.heading.toStringAsFixed(0)}° ${sensor.getHeadingDirection()}')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _spatialData(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TacticalDesign.hudText.copyWith(fontSize: 7, color: Colors.white38)),
        Text(
          value,
          style: TacticalDesign.hudText.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            shadows: [
              const Shadow(color: TacticalDesign.accentGreen, blurRadius: 4),
            ],
          ),
        ),
      ],
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
    // Control point to create a "liquid" curve towards the gallery dock
    final Offset controlPoint = Offset(widget.startPosition.dx + 100, widget.startPosition.dy - 200);
    
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
            opacity: 1 - _animation.value.clamp(0.8, 1.0) * 5 + 4,
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
