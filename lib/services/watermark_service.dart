import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

class WatermarkParams {
  final Uint8List imageBytes;
  final double latitude;
  final double longitude;
  final double altitude;
  final double heading;
  final String caption;
  final String timestamp;
  final String address;
  final Map<String, bool> visibility;

  WatermarkParams({
    required this.imageBytes,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.heading,
    required this.caption,
    required this.timestamp,
    required this.address,
    required this.visibility,
  });
}

class WatermarkService {
  static Future<Uint8List> burnMetadata(WatermarkParams params) async {
    return await compute(_processImage, params);
  }

  static Uint8List _processImage(WatermarkParams params) {
    img.Image? image = img.decodeImage(params.imageBytes);
    if (image == null) return params.imageBytes;

    final String coords = 'LAT: ${params.latitude.toStringAsFixed(6)} | LNG: ${params.longitude.toStringAsFixed(6)}';
    final String altHeading = 'ALT: ${params.altitude.toStringAsFixed(1)}m | HDG: ${params.heading.toStringAsFixed(0)}°';
    
    final font = img.arial48;
    // Draw semi-transparent background bar for contrast (Bottom 18%)
    final int barHeight = (image.height * 0.18).toInt();
    img.fillRect(
      image,
      x1: 0,
      y1: image.height - barHeight,
      x2: image.width,
      y2: image.height,
      color: img.ColorRgba8(0, 0, 0, 255),
    );

    // Padding and vertical steps
    const int padding = 80;
    int currentY = image.height - barHeight + 60;
    const int lineSpacing = 80;
    
    // Draw Text with high contrast and logical grouping
    // Line 1: Caption (Bold color)
    if (params.visibility['caption'] ?? true) {
      img.drawString(image, params.caption.toUpperCase(), font: font, x: padding, y: currentY, color: img.ColorRgba8(0, 230, 118, 255));
      currentY += lineSpacing;
    }
    
    // Address Wrapping Logic
    if (params.visibility['location'] ?? true) {
      String addressStr = params.address.toUpperCase();
      int maxCharsPerLine = (image.width - (padding * 2)) ~/ 35; // Rough estimate for arial48
      if (addressStr.length > maxCharsPerLine) {
        // Split into two lines
        String line1 = addressStr.substring(0, maxCharsPerLine);
        int lastSpace = line1.lastIndexOf(", ");
        if (lastSpace != -1) {
          line1 = addressStr.substring(0, lastSpace + 2);
          String line2 = addressStr.substring(lastSpace + 2);
          img.drawString(image, line1, font: font, x: padding, y: currentY, color: img.ColorRgba8(255, 255, 255, 255));
          currentY += lineSpacing;
          img.drawString(image, line2, font: font, x: padding, y: currentY, color: img.ColorRgba8(255, 255, 255, 255));
        } else {
          img.drawString(image, addressStr, font: font, x: padding, y: currentY, color: img.ColorRgba8(255, 255, 255, 255));
        }
      } else {
        img.drawString(image, addressStr, font: font, x: padding, y: currentY, color: img.ColorRgba8(255, 255, 255, 255));
      }
      currentY += lineSpacing;

      // Coordinates Line
      img.drawString(image, coords, font: font, x: padding, y: currentY, color: img.ColorRgba8(255, 255, 255, 200));
      currentY += lineSpacing;
    }

    // Altitude & Heading
    bool showAlt = params.visibility['altitude'] ?? true;
    bool showCompass = params.visibility['compass'] ?? true;
    if (showAlt || showCompass) {
      String line = "";
      if (showAlt) line += "ALT: ${params.altitude.toStringAsFixed(1)}m ";
      if (showAlt && showCompass) line += "| ";
      if (showCompass) line += "HDG: ${params.heading.toStringAsFixed(0)}°";
      
      img.drawString(image, line, font: font, x: padding, y: currentY, color: img.ColorRgba8(255, 255, 255, 180));
      currentY += lineSpacing;
    }

    // Line 5: Timestamp
    if (params.visibility['timestamp'] ?? true) {
      img.drawString(image, params.timestamp, font: font, x: padding, y: currentY, color: img.ColorRgba8(255, 255, 255, 150));
    }
    

    // Encode back to JPG with high quality
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }
}
