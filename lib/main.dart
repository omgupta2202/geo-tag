import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geo_lens/services/location_service.dart';
import 'package:geo_lens/services/sensor_service.dart';
import 'package:geo_lens/services/database_service.dart';
import 'package:geo_lens/services/settings_service.dart';
import 'package:geo_lens/screens/camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => SensorService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
        Provider(create: (_) => DatabaseService()),
      ],
      child: const GeoLensApp(),
    ),
  );
}

class GeoLensApp extends StatelessWidget {
  const GeoLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}
