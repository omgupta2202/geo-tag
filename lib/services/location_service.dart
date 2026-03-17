import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService with ChangeNotifier {
  Position? _currentPosition;
  String? _currentAddress;
  bool _isLoading = true;

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  bool get isLoading => _isLoading;

  LocationService() {
    _initLocation();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Increased filter to avoid excessive geocoding calls
      ),
    ).listen((Position position) {
      _currentPosition = position;
      _isLoading = false;
      _fetchAddress(position);
      notifyListeners();
    });
  }

  Future<void> _fetchAddress(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        
        // Construct a comprehensive address while avoiding duplicates
        final parts = <String>{};
        if (place.name != null && place.name!.isNotEmpty) parts.add(place.name!);
        if (place.subLocality != null && place.subLocality!.isNotEmpty) parts.add(place.subLocality!);
        if (place.street != null && place.street!.isNotEmpty) parts.add(place.street!);
        if (place.locality != null && place.locality!.isNotEmpty) parts.add(place.locality!);
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) parts.add(place.administrativeArea!);
        
        _currentAddress = parts.join(", ");
      }
    } catch (e) {
      debugPrint("Geocoding error: $e");
      _currentAddress = "ADDRESS UNAVAILABLE";
    }
    notifyListeners();
  }
}
