import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TacticalDesign {
  // Colors
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF121212);
  static const Color accentGreen = Color(0xFF00E676);
  static const Color alertRed = Color(0xFFFF5252);
  
  // HUD Text Styles
  static TextStyle get hudText => GoogleFonts.shareTechMono(
    color: Colors.white,
    fontSize: 12,
  );

  static TextStyle get heading => GoogleFonts.outfit(
    color: Colors.white,
    fontWeight: FontWeight.bold,
    letterSpacing: 2,
  );

  // Glassmorphism effects
  static BoxDecoration get glassPill => BoxDecoration(
    color: Colors.white.withOpacity(0.1),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: Colors.white.withOpacity(0.1)),
  );
}
