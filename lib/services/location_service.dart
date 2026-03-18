import 'dart:async';
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

  Timer? _refreshTimer;

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  String? get cityState => _cityState;
  String? get country => _country;
  bool get isLoading => _isLoading || _isFetchingAddress;
  bool get permissionDenied => _permissionDenied;
  bool get serviceDisabled => _serviceDisabled;

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
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    _permissionDenied = false;
    _serviceDisabled = false;

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

    // Get an immediate fix so the HUD is populated fast
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      _currentPosition = pos;
      _isLoading = false;
      notifyListeners();
      _fetchAddress(pos);
    } catch (_) {
      // Fall through to stream if quick fix fails
    }

    // Stream for movement-based updates
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((position) {
      _currentPosition = position;
      _isLoading = false;
      notifyListeners();
      _fetchAddress(position);
    });

    // Periodic refresh every 30 s — keeps address fresh when stationary
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_currentPosition == null) return;
      try {
        final fresh = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 8));
        _currentPosition = fresh;
        notifyListeners();
        _fetchAddress(fresh);
      } catch (_) {}
    });
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
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
      _currentAddress = 'Address unavailable';
      _cityState = 'Unknown Location';
    } finally {
      _isFetchingAddress = false;
      notifyListeners();
    }
  }
}
