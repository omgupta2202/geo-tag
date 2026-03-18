# GeoLens — GPS Map Camera

> Capture photos with GPS metadata, satellite map thumbnails, and timestamps burned permanently into every image — just like GPS Map Camera.

---

## Features

- **Live GPS HUD** — Satellite map tile, city name, address, coordinates and timestamp overlaid on the camera viewfinder in real-time
- **Burned-in watermark** — Metadata is permanently embedded as a card at the bottom of every saved photo (not just EXIF)
- **Satellite map tile** — Real Esri World Imagery tile fetched per location, displayed in HUD and burned into photos
- **Pre-cached tile** — Map tile is fetched as soon as GPS locks; capture is nearly instant (no network wait at shutter)
- **Auto location refresh** — Coordinates and address refresh every 30 seconds even when stationary
- **Permission recovery** — Red banner appears if GPS is off or permission denied; tapping it opens Settings. App auto-retries when returning from background
- **Gallery** — Staggered masonry grid with long-press multi-select, select-all, bulk delete, and share
- **Settings** — Toggle each overlay (location, coordinates, timestamp, altitude, compass, accuracy) and set a custom caption
- **Tactical dark UI** — Black + accent green + red theme throughout

---

## Watermark Layout

```
┌────────────────────────────────────────────────────────────┐
│                                          GPS Map Camera 📷  │
│  ┌──────────┐   City, State, Country                       │
│  │ Satellite│   Full street address, Postal code, Country  │
│  │  Map     │   Lat XX.XXXXXX°  Long XX.XXXXXX°            │
│  │  [pin]   │   Friday, 19/03/2026 03:15 AM GMT +05:30     │
│  └──────────┘                                              │
└────────────────────────────────────────────────────────────┘
```

- Dark semi-transparent rounded card appended below the photo
- Satellite map tile (Esri World Imagery) on the left with a red pin
- Large bold city/state/country headline
- Full address in smaller text (wraps up to 2 lines)
- Coordinates with degree symbol
- Day + date + time + GMT offset

---

## Project Structure

```
geo_lens/
├── lib/
│   ├── main.dart                      # App entry, Provider setup
│   ├── screens/
│   │   ├── camera_screen.dart         # Camera viewfinder, GPS HUD, capture
│   │   ├── gallery_screen.dart        # Masonry grid, multi-select, delete
│   │   ├── photo_view_screen.dart     # Full-screen viewer + info panel
│   │   └── settings_screen.dart      # Overlay toggles, custom caption
│   ├── services/
│   │   ├── watermark_service.dart     # Pixel-level metadata card rendering
│   │   ├── location_service.dart      # GPS stream, reverse geocoding, auto-retry
│   │   ├── map_tile_service.dart      # Fetches Esri satellite tiles
│   │   ├── sensor_service.dart        # Compass heading, pitch/roll
│   │   ├── database_service.dart      # SQLite photo records
│   │   └── settings_service.dart     # Overlay toggles (SharedPreferences)
│   └── utils/
│       └── tactical_design.dart       # Colors, fonts, design tokens
├── tool/
│   └── generate_icon.dart             # Script to regenerate app icon
├── assets/
│   └── icon/
│       └── icon.png                   # 1024×1024 master app icon
├── android/
│   ├── app/build.gradle.kts           # Release signing config
│   └── key.properties                 # Keystore credentials (git-ignored)
├── pubspec.yaml
└── README.md
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | 3.x stable |
| Dart SDK | ≥ 3.0.0 |
| Android Studio | Hedgehog or newer |
| Android SDK | API 21+ (minSdk) |
| Java | 17 |

---

## Getting Started

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Accept Android licenses (one-time)

```bash
flutter doctor --android-licenses
```

### 3. Connect your Android device

Enable **USB Debugging** on the phone:
- Settings → About Phone → tap **Build Number** 7 times
- Settings → Developer Options → **USB Debugging ON**
- Plug in via USB and tap **Allow** on the dialog

Verify detection:

```bash
flutter devices
```

### 4. Run (debug)

```bash
flutter run
```

---

## Release Build

### Set up signing (one-time)

**1. Generate keystore**

```bash
keytool -genkey -v \
  -keystore ~/geo_lens_release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias geo_lens
```

> ⚠️ Back up `geo_lens_release.jks`. Losing it means you can never update the app on Play Store.

**2. Create `android/key.properties`**

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=geo_lens
storeFile=/absolute/path/to/geo_lens_release.jks
```

This file is git-ignored — never commit it.

### Build Android App Bundle (Play Store)

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

### Build APK (direct install)

```bash
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## App Icon

The icon is generated programmatically from `tool/generate_icon.dart` using the `image` package.

To regenerate (e.g. after design changes):

```bash
dart run tool/generate_icon.dart     # creates assets/icon/icon.png
dart run flutter_launcher_icons      # slices into all mipmap sizes
```

Icon design: black background · green camera lens rings · HUD crosshair corners · red GPS pin with white center ring.

---

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `camera` | Camera preview and capture |
| `geolocator` | GPS position stream + permission handling |
| `geocoding` | Reverse geocode coordinates to address |
| `image` | Pixel-level watermark rendering |
| `flutter_map` | Satellite map thumbnail in HUD |
| `sqflite` | Local SQLite photo records |
| `shared_preferences` | Persist settings across restarts |
| `provider` | State management |
| `flutter_staggered_grid_view` | Masonry gallery layout |
| `sensors_plus` | Accelerometer (pitch/roll) |
| `flutter_compass` | Compass heading |
| `google_fonts` | Outfit + ShareTechMono fonts |
| `share_plus` | Share watermarked photos |
| `http` | Fetch satellite map tiles |
| `flutter_launcher_icons` | Generate all icon sizes from master PNG |

---

## How Capture Works

```
Shutter press
    │
    ├─ takePicture()              ~0.3s  camera hardware
    ├─ readAsBytes()              ~0.1s  file I/O
    ├─ use _cachedMapTile         ~0s    pre-fetched when GPS locked
    ├─ WatermarkService.burn()    ~2-3s  image processing (separate isolate)
    ├─ writeAsBytes()             ~0.3s  save to documents dir
    └─ db.insertPhoto()           ~0ms   record metadata
```

The satellite tile is pre-fetched and cached as soon as GPS locks — it is **not** fetched at capture time, keeping shutter response fast.

---

## Location Service Behaviour

| Event | Response |
|-------|---------|
| App starts | `getCurrentPosition()` for immediate fix, then stream |
| Device moves 10m | Stream update → re-geocode address |
| 30 seconds elapsed | Periodic timer → fresh position + address |
| App resumes from background | `didChangeAppLifecycleState` → auto-retry if GPS was off |
| Permission denied | Red banner shown → tap to re-request or open Settings |
| GPS service off | Red banner shown → tap to open Location Settings |

---

## Settings Reference

| Toggle | What it controls |
|--------|-----------------|
| Location | City/address/coordinates in HUD and watermark |
| Timestamp | Date/time line in watermark |
| Altitude | Altitude row in HUD |
| Compass | Bearing row in HUD |
| GPS Accuracy | Accuracy indicator in HUD |
| Custom Caption | Text label stored with each photo |

---

## Troubleshooting

**Black camera screen**
```
Settings → Apps → GeoLens → Permissions → Camera → Allow
```

**"SEARCHING GNSS..." never resolves**
```
Settings → Apps → GeoLens → Permissions → Location → Allow while using app
```
Go outdoors — GPS needs line-of-sight to satellites.

**App doesn't detect GPS after enabling it**
The app uses `WidgetsBindingObserver` — just switch back to the app and it will auto-retry within 1 second.

**Build fails — Gradle error**
```bash
cd android && ./gradlew clean && cd ..
flutter clean && flutter pub get
flutter run
```

**Watermark coordinates missing degree symbol**
The `image` package bitmap fonts include Latin-1 (U+00B0 `°`). If it renders blank, the device's font rendering is bypassed — this is expected for very old Android versions.

---

## Play Store

- **App ID:** `com.geolens.app`
- **Min SDK:** 21 (Android 5.0)
- **Target SDK:** latest Flutter default
- **Permissions required:** Camera, Fine Location
- **Privacy policy required:** Yes (app handles GPS + photos)

### Suggested keywords
`gps camera, geotag photo, location stamp, map camera, timestamp camera, field photo, site documentation`
