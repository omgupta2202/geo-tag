import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geo_lens/services/settings_service.dart';
import 'package:geo_lens/utils/tactical_design.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    final service = Provider.of<SettingsService>(context, listen: false);
    _captionController = TextEditingController(text: service.customCaption);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);

    return Scaffold(
      backgroundColor: TacticalDesign.background,
      appBar: AppBar(
        title: Text('SETTINGS', style: TacticalDesign.heading.copyWith(fontSize: 18, letterSpacing: 2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _captionField(settingsService),
          const SizedBox(height: 20),
          _tile(settingsService, 'GPS Coordinates', 'location'),
          _tile(settingsService, 'Compass Heading', 'compass'),
          _tile(settingsService, 'Timestamp', 'timestamp'),
          _tile(settingsService, 'Altitude', 'altitude'),
          _tile(settingsService, 'GPS Accuracy', 'accuracy'),
        ],
      ),
    );
  }

  Widget _captionField(SettingsService service) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CUSTOM CAPTION', style: TacticalDesign.hudText.copyWith(color: TacticalDesign.accentGreen, fontSize: 12, letterSpacing: 2)),
        const SizedBox(height: 12),
        TextField(
          controller: _captionController,
          style: TacticalDesign.hudText,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            hintText: 'Enter caption...',
          ),
          onChanged: (val) => service.setCustomCaption(val),
        ),
      ],
    );
  }

  Widget _tile(SettingsService service, String title, String key) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(title, style: TacticalDesign.hudText),
          value: service.isOverlayEnabled(key),
          activeColor: TacticalDesign.accentGreen,
          onChanged: (val) => service.toggleOverlay(key),
        ),
        const Divider(color: Colors.white10),
      ],
    );
  }
}
