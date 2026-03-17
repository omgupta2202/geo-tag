import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math' as math;

class SensorService with ChangeNotifier {
  double _heading = 0.0;
  double _pitch = 0.0;
  double _roll = 0.0;

  double get heading => _heading;
  double get pitch => _pitch;
  double get roll => _roll;

  SensorService() {
    FlutterCompass.events?.listen((event) {
      double newHeading = event.heading ?? 0.0;
      // Only notify if change is significant (> 0.5 degrees)
      if ((newHeading - _heading).abs() > 0.5) {
        _heading = newHeading;
        notifyListeners();
      }
    });

    accelerometerEvents.listen((event) {
      double newPitch = math.atan2(event.y, event.z) * 180 / math.pi;
      double newRoll = math.atan2(event.x, event.z) * 180 / math.pi;
      
      // Significant tilt change (> 1.0 degrees)
      if ((newPitch - _pitch).abs() > 1.0 || (newRoll - _roll).abs() > 1.0) {
        _pitch = newPitch;
        _roll = newRoll;
        notifyListeners();
      }
    });
  }

  String getHeadingDirection() {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'];
    int index = ((_heading + 22.5) % 360 / 45).floor();
    return directions[index];
  }
}
