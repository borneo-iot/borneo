import 'dart:math';
import 'package:flutter/material.dart';

/// Converts a wavelength (nm) to a Flutter Color.
///
/// Wavelength Ranges:
/// - 380 ~ 780 nm: Visible spectrum colors.
/// - > 1000 nm: Treated as Color Temperature (value interpreted as Kelvin).
/// - Other ranges: Returns Black.
Color wavelengthToColor(double wavelength) {
  // Infrared/High values: Treat as Color Temperature (Kelvin)
  if (wavelength > 1000) {
    // Standard range 1000K to 40000K
    double temp = wavelength.clamp(1000, 40000);
    return _colorTemperatureToColor(temp);
  }

  // Visible spectrum range
  return _spectrumToColor(wavelength);
}

/// Converts visible spectrum wavelength (380-780nm) to Color.
Color _spectrumToColor(double wavelength) {
  if (wavelength < 380 || wavelength > 780) {
    return Colors.black;
  }

  double r = 0, g = 0, b = 0;

  // Piecewise linear approximation of the visible spectrum
  if (wavelength < 440) {
    r = -(wavelength - 440) / (440 - 380);
    g = 0.0;
    b = 1.0;
  } else if (wavelength < 490) {
    r = 0.0;
    g = (wavelength - 440) / (490 - 440);
    b = 1.0;
  } else if (wavelength < 510) {
    r = 0.0;
    g = 1.0;
    b = -(wavelength - 510) / (510 - 490);
  } else if (wavelength < 580) {
    r = (wavelength - 510) / (580 - 510);
    g = 1.0;
    b = 0.0;
  } else if (wavelength < 645) {
    r = 1.0;
    g = -(wavelength - 645) / (645 - 580);
    b = 0.0;
  } else {
    r = 1.0;
    g = 0.0;
    b = 0.0;
  }

  // Intensity factor to dim colors near the edges of visibility (380nm and 780nm)
  double factor = 1.0;
  if (wavelength < 420) {
    factor = 0.3 + 0.7 * (wavelength - 380) / (420 - 380);
  } else if (wavelength > 700) {
    factor = 0.3 + 0.7 * (780 - wavelength) / (780 - 700);
  }

  return Color.fromRGBO(
    (r * factor * 255).round().clamp(0, 255),
    (g * factor * 255).round().clamp(0, 255),
    (b * factor * 255).round().clamp(0, 255),
    1.0,
  );
}

/// Converts Color Temperature (K) to Color (1000K to 40000K).
/// Based on Tanner Helland's approximation algorithm.
Color _colorTemperatureToColor(double temperature) {
  temperature = temperature.clamp(1000, 40000) / 100;

  double r, g, b;

  // Calculate Red
  if (temperature <= 66) {
    r = 255;
  } else {
    r = temperature - 60;
    r = 329.698727446 * pow(r, -0.1332047592);
  }

  // Calculate Green
  if (temperature <= 66) {
    g = 99.4708025861 * log(temperature) - 161.1195681661;
  } else {
    g = temperature - 60;
    g = 288.1221695283 * pow(g, -0.0755148492);
  }

  // Calculate Blue
  if (temperature >= 66) {
    b = 255;
  } else if (temperature <= 19) {
    b = 0;
  } else {
    b = temperature - 10;
    b = 138.5177312231 * log(b) - 305.0447927307;
  }

  return Color.fromRGBO(r.round().clamp(0, 255), g.round().clamp(0, 255), b.round().clamp(0, 255), 1.0);
}
