// Run with: dart run tool/generate_icon.dart
// Generates assets/icon/icon.png — a 1024x1024 GeoLens app icon.
//
// Design:
//   • Black background
//   • Camera lens rings (grey barrel + green accent)
//   • HUD crosshair corners in green
//   • Red GPS location pin at center

import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const int sz = 1024;
  const int cx = sz ~/ 2;
  const int cy = sz ~/ 2;

  final icon = img.Image(width: sz, height: sz);

  // ── Background ──────────────────────────────────────────────────────────
  img.fill(icon, color: img.ColorRgba8(8, 8, 8, 255));

  // Subtle green radial glow behind the lens
  for (int r = 420; r >= 0; r -= 2) {
    final a = (18 * r / 420).clamp(0, 18).toInt();
    img.drawCircle(icon, x: cx, y: cy, radius: r,
        color: img.ColorRgba8(0, 200, 100, a));
  }

  // ── Camera lens barrel (dark grey ring) ─────────────────────────────────
  for (int t = 0; t < 28; t++) {
    img.drawCircle(icon, x: cx, y: cy, radius: 430 + t,
        color: img.ColorRgba8(38, 38, 38, 255));
  }

  // ── Green accent ring ────────────────────────────────────────────────────
  for (int t = 0; t < 7; t++) {
    img.drawCircle(icon, x: cx, y: cy, radius: 398 + t,
        color: img.ColorRgba8(0, 230, 118, 255));
  }

  // ── Inner lens rim ───────────────────────────────────────────────────────
  for (int t = 0; t < 3; t++) {
    img.drawCircle(icon, x: cx, y: cy, radius: 310 + t,
        color: img.ColorRgba8(50, 50, 50, 200));
  }

  // ── HUD crosshair corners (green tick marks) ──────────────────────────
  final green = img.ColorRgba8(0, 230, 118, 240);
  const int tickLen = 70;
  const int tickOff = 355; // distance from center to tick start
  const int tickThick = 6;

  void hLine(int x1, int x2, int y) {
    for (int t = 0; t < tickThick; t++) {
      img.drawLine(icon, x1: x1, y1: y + t, x2: x2, y2: y + t, color: green);
    }
  }
  void vLine(int x, int y1, int y2) {
    for (int t = 0; t < tickThick; t++) {
      img.drawLine(icon, x1: x + t, y1: y1, x2: x + t, y2: y2, color: green);
    }
  }

  // top-left
  hLine(cx - tickOff - tickLen, cx - tickOff, cy - tickOff);
  vLine(cx - tickOff, cy - tickOff - tickLen, cy - tickOff);
  // top-right
  hLine(cx + tickOff, cx + tickOff + tickLen, cy - tickOff);
  vLine(cx + tickOff, cy - tickOff - tickLen, cy - tickOff);
  // bottom-left
  hLine(cx - tickOff - tickLen, cx - tickOff, cy + tickOff);
  vLine(cx - tickOff, cy + tickOff, cy + tickOff + tickLen);
  // bottom-right
  hLine(cx + tickOff, cx + tickOff + tickLen, cy + tickOff);
  vLine(cx + tickOff, cy + tickOff, cy + tickOff + tickLen);

  // ── GPS Location Pin ─────────────────────────────────────────────────────
  const int pinCX = cx;
  const int pinCY = cy - 30;
  const int pinR  = 155;
  final red   = img.ColorRgba8(220, 38,  38,  255);
  final redDark = img.ColorRgba8(160, 20, 20, 255);

  // Drop shadow
  img.fillCircle(icon, x: pinCX + 10, y: pinCY + 12, radius: pinR,
      color: img.ColorRgba8(0, 0, 0, 90));

  // Pin circle head
  img.fillCircle(icon, x: pinCX, y: pinCY, radius: pinR, color: red);

  // Pin tail — scan-line triangle tapering to a point
  const int tailTop    = pinCY + pinR - 10;
  const int tailBottom = pinCY + pinR + 200;
  for (int y = tailTop; y <= tailBottom; y++) {
    final t = (y - tailTop) / (tailBottom - tailTop);
    final halfW = (pinR * (1.0 - t) * 0.85).round();
    final c = t > 0.5 ? redDark : red;
    for (int x = pinCX - halfW; x <= pinCX + halfW; x++) {
      if (x >= 0 && x < sz && y >= 0 && y < sz) icon.setPixel(x, y, c);
    }
  }

  // White ring (inner lens of the pin)
  for (int t = 0; t < 8; t++) {
    img.drawCircle(icon, x: pinCX, y: pinCY, radius: 72 + t,
        color: img.ColorRgba8(255, 255, 255, 230));
  }

  // White filled center dot
  img.fillCircle(icon, x: pinCX, y: pinCY, radius: 28,
      color: img.ColorRgba8(255, 255, 255, 255));

  // Small red dot in white center
  img.fillCircle(icon, x: pinCX, y: pinCY, radius: 10,
      color: red);

  // ── Save ────────────────────────────────────────────────────────────────
  final out = File('assets/icon/icon.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(img.encodePng(icon));
  print('✓  Icon saved → assets/icon/icon.png  (${sz}x$sz)');
}
