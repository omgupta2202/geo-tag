// Run with: dart run tool/generate_icon.dart
// Generates assets/icon/icon.png (1024x1024) and assets/icon/play_store_512.png.
//
// Design — "Aperture + GPS":
//   • Deep emerald gradient background with a soft green glow
//   • Metallic camera lens barrel ring
//   • Faceted hexagonal aperture (6 green/teal blades) — reads as "camera"
//   • Glossy teal "glass" center with faint radar rings — reads as "GPS / scope"
//   • Glossy red location pin floating on the glass — reads as "geotag"
//
// Everything is centered and kept within the Android adaptive-icon safe zone
// (central ~72%) so nothing important is cropped on round / squircle masks.
//
// Rendered at 2x and downscaled for clean anti-aliased edges.

import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

// ── Work canvas (2x supersample) ───────────────────────────────────────────
const int W = 2048;
const int C = W ~/ 2; // center

img.ColorRgba8 rgba(int r, int g, int b, [int a = 255]) =>
    img.ColorRgba8(r, g, b, a);

img.ColorRgba8 lerp(img.ColorRgba8 a, img.ColorRgba8 b, double t) {
  t = t.clamp(0.0, 1.0);
  int m(num x, num y) => (x + (y - x) * t).round();
  return rgba(m(a.r, b.r), m(a.g, b.g), m(a.b, b.b), m(a.a, b.a));
}

void main() {
  final icon = img.Image(width: W, height: W, numChannels: 4);

  // ── Background: diagonal emerald gradient + smooth radial glow ───────────
  final bgTop = rgba(10, 20, 16);
  final bgBot = rgba(3, 24, 16);
  final glow = rgba(0, 210, 115);
  const glowR = 1000.0;
  for (int y = 0; y < W; y++) {
    for (int x = 0; x < W; x++) {
      final base = lerp(bgTop, bgBot, (x + y) / (2.0 * W));
      final dx = x - C, dy = y - C;
      final d = math.sqrt(dx * dx + dy * dy);
      // smooth (squared) falloff — no banding
      final g = d >= glowR ? 0.0 : math.pow(1 - d / glowR, 2.2) * 0.30;
      icon.setPixel(x, y, lerp(base, glow, g.toDouble()));
    }
  }

  // ── Lens barrel: metallic grey ring (outer 748 → inner 668) ──────────────
  const lensOuterR = 748;
  const barrelInner = 668;
  final barrelDark = rgba(26, 30, 29);
  final barrelLite = rgba(82, 90, 88);
  for (int r = lensOuterR; r >= barrelInner; r--) {
    final t = (lensOuterR - r) / (lensOuterR - barrelInner);
    // bright at the outer edge, dropping into a dark recess at the inner edge
    final c = lerp(barrelLite, barrelDark, t);
    img.drawCircle(icon, x: C, y: C, radius: r, color: c, antialias: true);
  }
  // crisp bright outer rim + dark inner recess line
  img.drawCircle(icon,
      x: C, y: C, radius: lensOuterR, color: rgba(120, 130, 128), antialias: true);
  img.drawCircle(icon,
      x: C, y: C, radius: barrelInner, color: rgba(8, 10, 10), antialias: true);

  // ── Faceted hexagonal aperture ───────────────────────────────────────────
  const hexR = 660; // vertex radius
  const glassR = 384; // round opening (glass) radius

  // 6 facet shades — alternating bright/dark for a gem-like aperture pop
  final facets = <img.ColorRgba8>[
    rgba(0, 240, 130),
    rgba(0, 140, 130),
    rgba(0, 215, 140),
    rgba(0, 120, 115),
    rgba(0, 230, 135),
    rgba(0, 150, 145),
  ];

  img.Point hexVertex(int k) {
    final ang = (-90 + k * 60) * math.pi / 180.0;
    return img.Point(C + hexR * math.cos(ang), C + hexR * math.sin(ang));
  }

  // Fill each facet as a triangle from the center to an outer edge.
  for (int k = 0; k < 6; k++) {
    final v1 = hexVertex(k);
    final v2 = hexVertex((k + 1) % 6);
    img.fillPolygon(icon,
        vertices: [img.Point(C, C), v1, v2], color: facets[k]);
  }

  // ── Glass center: teal radial gradient ───────────────────────────────────
  final glassCore = rgba(60, 235, 200);
  final glassEdge = rgba(4, 56, 48);
  for (int y = C - glassR; y <= C + glassR; y++) {
    for (int x = C - glassR; x <= C + glassR; x++) {
      final dx = x - C, dy = y - C;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= glassR) {
        icon.setPixel(x, y, lerp(glassCore, glassEdge, d / glassR));
      }
    }
  }

  // Blade divider lines (from glass rim out to each hex vertex)
  for (int k = 0; k < 6; k++) {
    final ang = (-90 + k * 60) * math.pi / 180.0;
    final x1 = C + glassR * math.cos(ang);
    final y1 = C + glassR * math.sin(ang);
    final v = hexVertex(k);
    img.drawLine(icon,
        x1: x1.round(),
        y1: y1.round(),
        x2: v.x.round(),
        y2: v.y.round(),
        color: rgba(4, 34, 30, 200),
        thickness: 7,
        antialias: true);
  }

  // Glass bezel ring
  for (int t = 0; t < 8; t++) {
    img.drawCircle(icon,
        x: C, y: C, radius: glassR - t, color: rgba(150, 255, 220, 230),
        antialias: true);
  }

  // Faint radar rings inside the glass (GPS / scope vibe)
  for (final rr in [130, 250, 360]) {
    for (int t = 0; t < 3; t++) {
      img.drawCircle(icon,
          x: C, y: C, radius: rr - t, color: rgba(150, 255, 210, 90),
          antialias: true);
    }
  }

  // ── Glossy GPS location pin, floating on the glass ───────────────────────
  const pinCX = C;
  const pinCY = C - 48;
  const pinR = 158;
  final red = rgba(226, 44, 44);
  final redDark = rgba(168, 22, 22);

  // Soft drop shadow
  img.fillCircle(icon,
      x: pinCX + 14, y: pinCY + 18, radius: pinR, color: rgba(0, 0, 0, 90),
      antialias: true);

  // Pin head
  img.fillCircle(icon, x: pinCX, y: pinCY, radius: pinR, color: red,
      antialias: true);

  // Pin tail — triangle tapering to a point
  const tailTop = pinCY + pinR - 14;
  const tailBottom = pinCY + pinR + 264;
  for (int y = tailTop; y <= tailBottom; y++) {
    final t = (y - tailTop) / (tailBottom - tailTop);
    final halfW = (pinR * (1.0 - t) * 0.86).round();
    final c = lerp(red, redDark, t);
    for (int x = pinCX - halfW; x <= pinCX + halfW; x++) {
      if (x >= 0 && x < W && y >= 0 && y < W) icon.setPixel(x, y, c);
    }
  }

  // Specular highlight on the head (upper-left)
  img.fillCircle(icon,
      x: pinCX - 52, y: pinCY - 56, radius: 46, color: rgba(255, 150, 140, 150),
      antialias: true);

  // White ring + center dot
  for (int t = 0; t < 12; t++) {
    img.drawCircle(icon,
        x: pinCX, y: pinCY, radius: 74 + t, color: rgba(255, 255, 255, 235),
        antialias: true);
  }
  img.fillCircle(icon, x: pinCX, y: pinCY, radius: 30,
      color: rgba(255, 255, 255, 255), antialias: true);
  img.fillCircle(icon, x: pinCX, y: pinCY, radius: 12, color: red,
      antialias: true);

  // ── Downscale & save ─────────────────────────────────────────────────────
  final master = img.copyResize(icon,
      width: 1024, height: 1024, interpolation: img.Interpolation.average);
  final store = img.copyResize(icon,
      width: 512, height: 512, interpolation: img.Interpolation.average);

  Directory('assets/icon').createSync(recursive: true);
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(master));
  File('assets/icon/play_store_512.png').writeAsBytesSync(img.encodePng(store));

  print('✓  assets/icon/icon.png              (1024x1024)');
  print('✓  assets/icon/play_store_512.png    (512x512, for Play Console)');
}
