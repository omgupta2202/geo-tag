# GeoLens — GPS Map Camera

A Flutter camera app that burns GPS metadata directly onto photos, styled like the reference GPS Map Camera watermark: a dark rounded card in the bottom-right corner with a mini map thumbnail, city headline, full address, coordinates, and timestamp.

---

## Watermark Layout (matches reference image)

```
┌─────────────────────────────────────────────────────┐
│  [Map Thumb]  City, State, Country          GPS Map Camera │
│  [with pin ]  Full street address                         │
│  [& grid   ]  Lat XX.XXXXXX° Long XX.XXXXXX°             │
│               Day, DD/MM/YYYY HH:MM AM/PM GMT +XX:XX      │
└─────────────────────────────────────────────────────┘
```

- Card is bottom-right, semi-transparent dark background
- Map thumbnail on the left with a grid + red pin
- City/State/Country as large white headline
- Full address in smaller text (auto-wraps up to 3 lines)
- Coordinates line
- Date/time with timezone

---

## Project Structure

```
geo_lens/
├── lib/
│   ├── main.dart                    # App entry, Provider setup
│   ├── screens/
│   │   ├── camera_screen.dart       # Main camera UI + capture logic
│   │   ├── gallery_screen.dart      # Staggered photo grid
│   │   ├── photo_view_screen.dart   # Full-screen photo viewer
│   │   └── settings_screen.dart    # Toggle overlays, set caption
│   ├── services/
│   │   ├── watermark_service.dart   # Image processing — burns metadata card
│   │   ├── location_service.dart    # GPS stream + reverse geocoding
│   │   ├── sensor_service.dart      # Compass heading + pitch/roll
│   │   ├── database_service.dart    # SQLite photo records
│   │   └── settings_service.dart   # Overlay toggles (persisted via SharedPrefs)
│   └── utils/
│       ├── tactical_design.dart     # Colors, text styles, design tokens
│       └── rolling_digit.dart       # Animated digit widget
├── android/                         # Android platform config
├── pubspec.yaml
└── README.md
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | 3.x stable |
| Dart SDK | >=3.0.0 |
| Android Studio | Hedgehog or newer |
| Xcode (iOS/macOS) | 15+ |
| Android SDK | API 21+ (minSdk) |

---

## Build & Run on Mobile

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Android permissions

`android/app/src/main/AndroidManifest.xml` must include:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
```

### 3. Accept Android licenses (one-time)

```bash
flutter doctor --android-licenses
```

### 4. Connect your device

Enable **USB Debugging** on your Android phone:
- Settings → About Phone → tap Build Number 7 times
- Settings → Developer Options → USB Debugging ON
- Plug in via USB and tap **Allow** on the authorization dialog

Verify it's detected:

```bash
flutter devices
```

### 5. Run on device

```bash
flutter run
```

Or target a specific device:

```bash
flutter run -d <device_id>
```

### 6. Build release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

Install directly:

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 7. Build Android App Bundle (for Play Store)

```bash
flutter build appbundle --release
```

---

## iOS Build

```bash
cd ios && pod install && cd ..
flutter run -d <iphone_device_id>
```

For release:

```bash
flutter build ipa
```

Open `build/ios/archive/Runner.xcarchive` in Xcode to distribute.

---

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `camera` | Camera preview and capture |
| `geolocator` | GPS position stream |
| `geocoding` | Reverse geocode to address |
| `image` | Pixel-level watermark burning |
| `sqflite` | Local photo database |
| `shared_preferences` | Persist settings across restarts |
| `provider` | State management |
| `flutter_staggered_grid_view` | Masonry gallery layout |
| `sensors_plus` | Accelerometer for parallax HUD |
| `flutter_compass` | Compass heading |
| `path_provider` | App documents directory |
| `share_plus` | Share photos |

---

## Watermark Customization

Edit `lib/services/watermark_service.dart` → `_processImage()`:

- **Card position**: change `cardX`/`cardY` offsets
- **Font sizes**: swap `img.arial48` / `img.arial24` / `img.arial14`
- **Card opacity**: adjust `ColorRgba8(20, 20, 20, 220)` — last value is alpha (0–255)
- **Map thumbnail**: `_drawMapGrid()` draws the grid; replace with a real static map tile by passing a `Uint8List mapTile` in `WatermarkParams`

---

## Settings

In-app settings (Settings screen):

| Toggle | Controls |
|--------|---------|
| GPS Coordinates | Lat/Long line on watermark |
| Compass Heading | Heading in HUD |
| Timestamp | Date/time line on watermark |
| Altitude | Altitude in HUD |
| GPS Accuracy | Accuracy indicator in HUD |
| Custom Caption | Text shown in green at top of old-style bar |

Settings persist across app restarts via `SharedPreferences`.

---

## Troubleshooting

**Black screen on camera**
- Check camera permission is granted in device Settings
- Run `flutter doctor` and resolve any issues

**"Device not authorized"**
- Unplug/replug USB cable
- Look for the "Allow USB Debugging" dialog on your phone

**Android licenses error**
```bash
flutter doctor --android-licenses
```

**Location shows "FETCHING ADDR..."**
- GPS needs a few seconds outdoors to lock
- Make sure Location permission is set to "Always" or "While using app"

**Build fails on Android**
```bash
cd android && ./gradlew clean && cd ..
flutter clean
flutter pub get
flutter run
```
