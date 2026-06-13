import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService with ChangeNotifier, WidgetsBindingObserver {
  Position? _currentPosition;
  String? _currentAddress;
  String? _cityState;
  String? _country;
  bool _isLoading = true;
  bool _isFetchingAddress = false;
  bool _permissionDenied = false;
  bool _serviceDisabled = false;

  StreamSubscription<Position>? _positionSub;
  bool _starting = false;

  // Throttle reverse-geocoding: only re-resolve the address after we have
  // moved a meaningful distance, otherwise the platform geocoder gets
  // hammered (and rate-limited) on every GPS tick.
  Position? _lastGeocodedPos;
  static const double _geocodeMinMove = 40.0; // metres

  // A fix is considered "locked" (accurate enough to rely on) once its
  // reported accuracy is within this radius.
  static const double _accurateThreshold = 30.0; // metres

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  String? get cityState => _cityState;
  String? get country => _country;
  bool get isLoading => _isLoading || _isFetchingAddress;
  bool get permissionDenied => _permissionDenied;
  bool get serviceDisabled => _serviceDisabled;

  /// Reported horizontal accuracy of the current fix, in metres (null if no fix).
  double? get accuracyMeters => _currentPosition?.accuracy;

  /// True once we have a fix tight enough to trust (≤ [_accurateThreshold] m).
  bool get hasAccurateFix =>
      _currentPosition != null && _currentPosition!.accuracy <= _accurateThreshold;

  LocationService() {
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
  }

  /// Auto-retry when user returns to the app after enabling GPS / granting permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_permissionDenied || _serviceDisabled || _currentPosition == null)) {
      retryPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    super.dispose();
  }

  /// Platform-tuned settings asking for the highest accuracy the device offers.
  LocationSettings _bestSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0, // stream every fix so accuracy can converge while still
        intervalDuration: const Duration(seconds: 1),
        useMSLAltitude: true, // true mean-sea-level altitude (better than ellipsoidal)
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best);
  }

  Future<void> _initLocation() async {
    if (_starting) return; // guard against overlapping starts (resume/retry spam)
    _starting = true;
    _permissionDenied = false;
    _serviceDisabled = false;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _isLoading = false;
        _serviceDisabled = true;
        _currentAddress = 'Location services are off';
        _cityState = 'Enable GPS';
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _isLoading = false;
        _permissionDenied = true;
        _currentAddress = 'Location permission denied';
        _cityState = 'Tap to allow';
        notifyListeners();
        return;
      }

      // Get an immediate fix so the HUD is populated fast.
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: _bestSettings(),
        ).timeout(const Duration(seconds: 10));
        _handlePosition(pos);
      } catch (_) {
        // Fall through to the stream if the quick fix fails/times out.
      }

      // Single position stream — cancel any previous one first so repeated
      // starts (app resume, permission retry) never stack subscriptions.
      await _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: _bestSettings(),
      ).listen(
        _handlePosition,
        onError: (e) => debugPrint('Position stream error: $e'),
      );
    } finally {
      _starting = false;
    }
  }

  /// Single sink for every incoming fix. Keeps the best reading and avoids
  /// letting a worse/jittery fix clobber a good one.
  void _handlePosition(Position pos) {
    if (_shouldAccept(pos)) {
      _currentPosition = pos;
      _isLoading = false;
      notifyListeners();
      _maybeFetchAddress(pos);
    } else if (_isLoading) {
      // Even a rejected fix clears the spinner once we have something.
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Decide whether [n] is worth promoting to the current fix.
  bool _shouldAccept(Position n) {
    final c = _currentPosition;
    if (c == null) return true;

    // Clearly tighter accuracy — always take it.
    if (n.accuracy + 1 < c.accuracy) return true;

    final moved = Geolocator.distanceBetween(
        c.latitude, c.longitude, n.latitude, n.longitude);

    // Genuine movement (beyond GPS noise), as long as the new fix isn't far worse.
    if (moved > 5 && n.accuracy <= c.accuracy + 20) return true;

    // Refresh a stale fix.
    final age = n.timestamp.difference(c.timestamp);
    if (age > const Duration(seconds: 12) && n.accuracy <= c.accuracy + 20) {
      return true;
    }

    return false;
  }

  /// Re-request permission and restart location (call after user taps the banner).
  Future<void> retryPermission() async {
    _isLoading = true;
    _permissionDenied = false;
    _serviceDisabled = false;
    notifyListeners();
    await _initLocation();
  }

  /// Open device location/app settings so user can grant permission.
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  /// Returns true if [s] looks like a Plus Code (e.g. "H9FQ+WQH")
  static bool _isPlusCode(String s) {
    return RegExp(r'^[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}$')
        .hasMatch(s.trim().toUpperCase());
  }

  /// Only reverse-geocode when we've moved far enough (or haven't resolved an
  /// address yet) — protects against the platform geocoder's rate limits.
  void _maybeFetchAddress(Position position) {
    if (_isFetchingAddress) return;
    if (_lastGeocodedPos != null) {
      final moved = Geolocator.distanceBetween(
        _lastGeocodedPos!.latitude,
        _lastGeocodedPos!.longitude,
        position.latitude,
        position.longitude,
      );
      if (moved < _geocodeMinMove) return;
    }
    _fetchAddress(position);
  }

  Future<void> _fetchAddress(Position position) async {
    _isFetchingAddress = true;
    notifyListeners();
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks[0];

        String? safeName;
        if (p.name != null &&
            p.name!.isNotEmpty &&
            !_isPlusCode(p.name!) &&
            p.name != p.street) {
          safeName = p.name;
        }

        final addrParts = <String>[];
        if (safeName != null) addrParts.add(safeName);
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          addrParts.add(p.subLocality!);
        }
        if (p.street != null &&
            p.street!.isNotEmpty &&
            !_isPlusCode(p.street!) &&
            p.street != safeName) {
          addrParts.add(p.street!);
        }
        if (p.locality != null && p.locality!.isNotEmpty) {
          addrParts.add(p.locality!);
        }
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
          addrParts.add(p.administrativeArea!);
        }
        if (p.postalCode != null && p.postalCode!.isNotEmpty) {
          addrParts.add(p.postalCode!);
        }
        if (p.country != null && p.country!.isNotEmpty) {
          addrParts.add(p.country!);
        }

        final deduped = <String>[];
        for (final part in addrParts) {
          if (deduped.isEmpty || deduped.last != part) deduped.add(part);
        }
        _currentAddress = deduped.join(', ');

        final headline = <String>[];
        if (p.locality != null && p.locality!.isNotEmpty) {
          headline.add(p.locality!);
        }
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
          headline.add(p.administrativeArea!);
        }
        if (p.country != null && p.country!.isNotEmpty) {
          headline.add(p.country!);
        }
        _cityState = headline.isNotEmpty ? headline.join(', ') : 'Unknown Location';
        _country = p.country;

        // Remember where this address was resolved so we can throttle the next call.
        _lastGeocodedPos = position;
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
      // Leave any previously resolved address in place; only show the fallback
      // if we never managed to resolve one.
      _currentAddress ??= 'Address unavailable';
      _cityState ??= 'Unknown Location';
    } finally {
      _isFetchingAddress = false;
      notifyListeners();
    }
  }
}
