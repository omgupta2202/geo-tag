import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

class WatermarkParams {
  final Uint8List imageBytes;
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final double heading;
  final String caption;
  final String timestamp;
  final String address;
  final String cityState;
  final String country;
  final Map<String, bool> visibility;
  final Uint8List? mapTileBytes;

  WatermarkParams({
    required this.imageBytes,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    this.accuracy = 0.0,
    required this.heading,
    required this.caption,
    required this.timestamp,
    required this.address,
    required this.cityState,
    required this.country,
    required this.visibility,
    this.mapTileBytes,
  });
}

class WatermarkService {
  static Future<Uint8List> burnMetadata(WatermarkParams params) async {
    return await compute(_processImage, params);
  }

  static Uint8List _processImage(WatermarkParams params) {
    img.Image? original = img.decodeImage(params.imageBytes);
    if (original == null) return params.imageBytes;

    final int origW = original.width;
    final int origH = original.height;

    // ── Strategy: render the card on a 1100px-wide stamp canvas ─────────
    // Wider canvas gives ~28 chars/line for arial48, so city names like
    // "Noida, Uttar Pradesh, India" fit on one line without ugly wrapping.
    // Stamp is then scaled up to the full image width.

    const int stampW = 1100;

    // ── Fonts ──────────────────────────────────────────────────────────────
    final fontHeadline = img.arial48; // 48px — city/state
    final fontBody     = img.arial24; // 24px — address, coords, time
    final fontSmall    = img.arial14; // 14px — brand

    const int hHeadline = 54;  // line height
    const int hBody     = 28;
    const int hSmall    = 18;

    // arial48 avg char width ≈ 28px, arial24 ≈ 14px
    const int avgHeadW  = 28;
    const int avgBodyW  = 14;

    // ── Layout on stamp (px) ───────────────────────────────────────────────
    const int outerPad   = 10;
    const int padH       = 18;
    const int padV       = 16;
    const int innerGap   = 16;
    const int lineGap    = 8;
    const int sectionGap = 12;
    const int radius     = 16;

    final int cardW = stampW - outerPad * 2;

    // ── First pass: estimate thumb size to compute text column ─────────────
    // Thumb is square: side = cardH - 2*padV, but cardH depends on text lines.
    // Use a fixed thumb estimate of 180px for the first pass.
    const int thumbEst = 180;
    final int textColWEst = cardW - padH * 2 - thumbEst - innerGap;

    // Wrap headline (arial48 ~28px/char)
    final int headChars = (textColWEst / avgHeadW).floor().clamp(8, 60);
    final List<String> headLinesEst = _wrapText(params.cityState.isNotEmpty
        ? params.cityState : 'Unknown Location', headChars);

    // Wrap address (arial24 ~14px/char)
    final int bodyChars = (textColWEst / avgBodyW).floor().clamp(10, 80);
    final List<String> addrLinesEst = _wrapText(params.address, bodyChars);

    // ── Card height from content ───────────────────────────────────────────
    int cardH = padV;
    cardH += hSmall + lineGap + sectionGap;                   // brand
    for (var _ in headLinesEst) cardH += hHeadline + lineGap; // headline (wrapped)
    for (var _ in addrLinesEst) cardH += hBody + lineGap;     // address
    cardH += sectionGap;
    cardH += hBody + lineGap + sectionGap;                    // coords
    cardH += hBody + padV;                                    // datetime

    // ── Square thumb: side = cardH - 2*padV ───────────────────────────────
    final int thumbSide = cardH - padV * 2;
    final int thumbW    = thumbSide;
    final int thumbH    = thumbSide;

    // ── Recompute text column with actual thumb width ──────────────────────
    final int textColW = cardW - padH * 2 - thumbW - innerGap;
    final int headCharsF = (textColW / avgHeadW).floor().clamp(8, 60);
    final int bodyCharsF = (textColW / avgBodyW).floor().clamp(10, 80);
    final List<String> headLines = _wrapText(params.cityState.isNotEmpty
        ? params.cityState : 'Unknown Location', headCharsF);
    final List<String> addrLines = _wrapText(params.address, bodyCharsF);

    // ── Create stamp canvas ────────────────────────────────────────────────
    final int stampH = cardH + outerPad * 2;
    final img.Image stamp = img.Image(width: stampW, height: stampH);
    // Fill transparent
    img.fill(stamp, color: img.ColorRgba8(0, 0, 0, 0));

    final int cardX = outerPad;
    final int cardY = outerPad;

    // ── Card background ────────────────────────────────────────────────────
    _fillRoundedRect(stamp, cardX, cardY, cardX + cardW, cardY + cardH,
        img.ColorRgba8(15, 15, 15, 235), radius);

    // ── Map thumbnail ──────────────────────────────────────────────────────
    final int thumbX = cardX + padH;
    final int thumbY = cardY + (cardH - thumbH) ~/ 2;
    final int thumbRadius = (radius * 0.65).toInt();

    if (params.mapTileBytes != null) {
      _drawRealTile(stamp, params.mapTileBytes!,
          thumbX, thumbY, thumbW, thumbH, thumbRadius);
    } else {
      _drawFallbackThumb(stamp, thumbX, thumbY, thumbW, thumbH, thumbRadius);
    }

    // ── Text block ────────────────────────────────────────────────────────
    final int textX = thumbX + thumbW + innerGap;

    int textBlockH = hSmall + lineGap + sectionGap;
    for (var _ in headLines) textBlockH += hHeadline + lineGap;
    for (var _ in addrLines) textBlockH += hBody + lineGap;
    textBlockH += sectionGap + hBody + lineGap + sectionGap + hBody;

    int textY = cardY + (cardH - textBlockH) ~/ 2;

    // Brand
    const String brand = 'GPS Map Camera';
    final int brandPxW = brand.length * 8;
    final int brandX = (cardX + cardW - padH - brandPxW).clamp(textX, cardX + cardW - padH);
    img.drawString(stamp, brand, font: fontSmall,
        x: brandX, y: textY, color: img.ColorRgba8(160, 160, 160, 200));
    textY += hSmall + lineGap + sectionGap;

    // Headline (wrapped)
    if (params.visibility['location'] ?? true) {
      for (final line in headLines) {
        img.drawString(stamp, line, font: fontHeadline,
            x: textX, y: textY, color: img.ColorRgba8(255, 255, 255, 255));
        textY += hHeadline + lineGap;
      }

      for (final line in addrLines) {
        img.drawString(stamp, line, font: fontBody,
            x: textX, y: textY, color: img.ColorRgba8(210, 210, 210, 230));
        textY += hBody + lineGap;
      }
      textY += sectionGap;

      final String accSuffix = params.accuracy > 0
          ? '  (\u00b1${params.accuracy.round()}m)'
          : '';
      final String coordLine =
          'Lat ${params.latitude.toStringAsFixed(6)}\u00b0  '
          'Long ${params.longitude.toStringAsFixed(6)}\u00b0$accSuffix';
      img.drawString(stamp, coordLine, font: fontBody,
          x: textX, y: textY, color: img.ColorRgba8(190, 190, 190, 215));
      textY += hBody + lineGap + sectionGap;
    }

    if (params.visibility['timestamp'] ?? true) {
      img.drawString(stamp, params.timestamp, font: fontBody,
          x: textX, y: textY, color: img.ColorRgba8(160, 160, 160, 200));
    }

    // ── Scale stamp up to full image width ────────────────────────────────
    final int scaledStampH = (stampH * origW / stampW).round();
    final img.Image scaledStamp = img.copyResize(
      stamp,
      width: origW,
      height: scaledStampH,
      interpolation: img.Interpolation.linear,
    );

    // ── Composite onto original image ─────────────────────────────────────
    // Expand canvas by scaledStampH at the bottom
    final int finalH = origH + scaledStampH;
    final img.Image result = img.Image(width: origW, height: finalH);

    // Copy original into top
    img.compositeImage(result, original, dstX: 0, dstY: 0);

    // Fill bottom strip black first
    for (int y = origH; y < finalH; y++) {
      for (int x = 0; x < origW; x++) {
        result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
      }
    }

    // Composite stamp onto bottom strip
    img.compositeImage(result, scaledStamp, dstX: 0, dstY: origH);

    return Uint8List.fromList(img.encodeJpg(result, quality: 95));
  }

  // ── Real satellite tile ────────────────────────────────────────────────────
  static void _drawRealTile(img.Image canvas, Uint8List tileBytes,
      int tx, int ty, int tw, int th, int radius) {
    final img.Image? tile = img.decodeImage(tileBytes);
    if (tile == null) {
      _drawFallbackThumb(canvas, tx, ty, tw, th, radius);
      return;
    }
    final img.Image resized = img.copyResize(tile, width: tw, height: th,
        interpolation: img.Interpolation.linear);

    for (int y = 0; y < th; y++) {
      for (int x = 0; x < tw; x++) {
        if (_inRoundedRect(x, y, tw, th, radius)) {
          canvas.setPixel(tx + x, ty + y, resized.getPixel(x, y));
        }
      }
    }
    // Border
    for (int y = ty; y < ty + th; y++) {
      for (int x = tx; x < tx + tw; x++) {
        final lx = x - tx; final ly = y - ty;
        if (_inRoundedRect(lx, ly, tw, th, radius) &&
            !_inRoundedRect(lx - 1, ly - 1, tw - 2, th - 2, radius)) {
          canvas.setPixel(x, y, img.ColorRgba8(255, 255, 255, 60));
        }
      }
    }
    _drawPin(canvas, tx + tw ~/ 2, ty + th ~/ 2);
  }

  // ── Fallback drawn thumbnail ───────────────────────────────────────────────
  static void _drawFallbackThumb(img.Image canvas,
      int tx, int ty, int tw, int th, int radius) {
    _fillRoundedRect(canvas, tx, ty, tx + tw, ty + th,
        img.ColorRgba8(52, 68, 46, 255), radius);
    final palette = [
      img.ColorRgba8(50, 68, 44, 255), img.ColorRgba8(58, 76, 50, 255),
      img.ColorRgba8(66, 84, 56, 255), img.ColorRgba8(44, 61, 38, 255),
      img.ColorRgba8(76, 91, 61, 255), img.ColorRgba8(86, 96, 66, 255),
    ];
    int seed = 37;
    int rnd(int mod) { seed = (seed * 1664525 + 1013904223) & 0x7fffffff; return seed % mod; }
    for (int gy = ty; gy < ty + th; gy += 14) {
      for (int gx = tx; gx < tx + tw; gx += 14) {
        final c = palette[rnd(palette.length)];
        for (int py = gy; py < gy + 14 && py < ty + th; py++) {
          for (int px = gx; px < gx + 14 && px < tx + tw; px++) {
            if (_inRoundedRect(px - tx, py - ty, tw, th, radius)) canvas.setPixel(px, py, c);
          }
        }
      }
    }
    final road = img.ColorRgba8(190, 181, 150, 190);
    img.drawLine(canvas, x1: tx, y1: ty + th * 2 ~/ 5, x2: tx + tw, y2: ty + th * 2 ~/ 5, color: road, thickness: 2);
    img.drawLine(canvas, x1: tx + tw * 2 ~/ 5, y1: ty, x2: tx + tw * 2 ~/ 5, y2: ty + th, color: road, thickness: 2);
    _drawPin(canvas, tx + tw ~/ 2, ty + th ~/ 2);
  }

  static void _drawPin(img.Image canvas, int cx, int cy) {
    img.fillCircle(canvas, x: cx + 1, y: cy + 1, radius: 10, color: img.ColorRgba8(0, 0, 0, 80));
    img.fillCircle(canvas, x: cx, y: cy, radius: 10, color: img.ColorRgba8(220, 38, 38, 255));
    img.fillCircle(canvas, x: cx - 3, y: cy - 3, radius: 3, color: img.ColorRgba8(255, 120, 120, 170));
    img.fillCircle(canvas, x: cx, y: cy, radius: 3, color: img.ColorRgba8(255, 255, 255, 230));
  }

  static bool _inRoundedRect(int x, int y, int w, int h, int r) {
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    if (x < r && y < r)       return (x-r)*(x-r)+(y-r)*(y-r) <= r*r;
    if (x >= w-r && y < r)    return (x-(w-r-1))*(x-(w-r-1))+(y-r)*(y-r) <= r*r;
    if (x < r && y >= h-r)    return (x-r)*(x-r)+(y-(h-r-1))*(y-(h-r-1)) <= r*r;
    if (x >= w-r && y >= h-r) return (x-(w-r-1))*(x-(w-r-1))+(y-(h-r-1))*(y-(h-r-1)) <= r*r;
    return true;
  }

  static List<String> _wrapText(String text, int charsPerLine) {
    if (text.length <= charsPerLine) return [text];
    final List<String> lines = [];
    String remaining = text;
    while (remaining.length > charsPerLine) {
      String chunk = remaining.substring(0, charsPerLine);
      int breakAt = chunk.lastIndexOf(', ');
      if (breakAt == -1) breakAt = chunk.lastIndexOf(' ');
      if (breakAt == -1) breakAt = charsPerLine;
      lines.add(remaining.substring(0, breakAt).trim());
      remaining = remaining.substring(breakAt).replaceFirst(RegExp(r'^[, ]+'), '');
    }
    if (remaining.isNotEmpty) lines.add(remaining.trim());
    return lines.take(3).toList();
  }

  static void _fillRoundedRect(img.Image image, int x1, int y1, int x2, int y2,
      img.Color color, int radius) {
    x1 = x1.clamp(0, image.width);  y1 = y1.clamp(0, image.height);
    x2 = x2.clamp(0, image.width);  y2 = y2.clamp(0, image.height);
    if (x2 <= x1 || y2 <= y1) return;
    radius = radius.clamp(0, ((x2-x1)/2).floor()).clamp(0, ((y2-y1)/2).floor());
    for (int y = y1; y < y2; y++) {
      int left = x1, right = x2;
      if (y < y1 + radius) {
        final dy = (y1 + radius - y).toDouble();
        final sq = radius * radius - dy * dy;
        final dx = sq < 0 ? radius : (radius - _sqrtD(sq)).toInt();
        left = x1 + dx; right = x2 - dx;
      } else if (y >= y2 - radius) {
        final dy = (y - (y2 - radius - 1)).toDouble();
        final sq = radius * radius - dy * dy;
        final dx = sq < 0 ? radius : (radius - _sqrtD(sq)).toInt();
        left = x1 + dx; right = x2 - dx;
      }
      for (int x = left; x < right; x++) image.setPixel(x, y, color);
    }
  }

  static double _sqrtD(double v) {
    if (v <= 0) return 0;
    double z = v / 2;
    for (int i = 0; i < 20; i++) z = z - (z * z - v) / (2 * z);
    return z;
  }
}
