import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService with ChangeNotifier {
  Map<String, bool> _overlays = {
    'location': true,
    'timestamp': true,
    'compass': true,
    'altitude': true,
    'caption': true,
    'accuracy': true,
  };

  String _customCaption = 'GeoLens Capture';

  Map<String, bool> get overlays => _overlays;
  String get customCaption => _customCaption;

  SettingsService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _customCaption = prefs.getString('caption') ?? 'GeoLens Capture';
    for (final key in _overlays.keys) {
      _overlays[key] = prefs.getBool('overlay_$key') ?? true;
    }
    notifyListeners();
  }

  Future<void> setCustomCaption(String value) async {
    _customCaption = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('caption', value);
    notifyListeners();
  }

  Future<void> toggleOverlay(String key) async {
    _overlays[key] = !(_overlays[key] ?? true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlay_$key', _overlays[key]!);
    notifyListeners();
  }

  bool isOverlayEnabled(String key) {
    return _overlays[key] ?? true;
  }
}
