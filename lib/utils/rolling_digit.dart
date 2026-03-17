import 'package:flutter/material.dart';

class RollingDigit extends StatelessWidget {
  final double value;
  final int precision;
  final String suffix;
  final TextStyle style;

  const RollingDigit({
    super.key,
    required this.value,
    this.precision = 2,
    this.suffix = '',
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '${value.toStringAsFixed(precision)}$suffix',
      style: style,
    );
  }
}
