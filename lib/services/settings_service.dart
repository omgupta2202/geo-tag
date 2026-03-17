import 'package:flutter/foundation.dart';

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

  void setCustomCaption(String value) {
    _customCaption = value;
    notifyListeners();
  }

  void toggleOverlay(String key) {
    _overlays[key] = !(_overlays[key] ?? true);
    notifyListeners();
  }

  bool isOverlayEnabled(String key) {
    return _overlays[key] ?? true;
  }
}
