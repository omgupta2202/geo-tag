import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService with ChangeNotifier {
  Position? _currentPosition;
  String? _currentAddress;
  String? _cityState;
  String? _country;
  bool _isLoading = true;
  bool _isFetchingAddress = false;

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  String? get cityState => _cityState;
  String? get country => _country;
  bool get isLoading => _isLoading || _isFetchingAddress;

  LocationService() {
    _initLocation();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _isLoading = false;
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
      _currentAddress = 'Location permission denied';
      _cityState = 'Unknown Location';
      notifyListeners();
      return;
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      _currentPosition = position;
      _isLoading = false;
      notifyListeners();
      _fetchAddress(position);
    });
  }

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

        // ── Full address — skip Plus Codes and blank fields ──────────────
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

        // Deduplicate consecutive identical parts
        final deduped = <String>[];
        for (final part in addrParts) {
          if (deduped.isEmpty || deduped.last != part) deduped.add(part);
        }
        _currentAddress = deduped.join(', ');

        // ── City, State, Country headline ────────────────────────────────
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
