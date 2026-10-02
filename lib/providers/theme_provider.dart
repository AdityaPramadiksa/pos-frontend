import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  // 1. Ganti default ke true agar saat pertama install langsung Dark Mode
  bool _isDarkMode = true;

  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadTheme();
  }

  void toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }

  void _loadTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // 2. Gunakan ?? true agar jika data kosong, otomatis jadi Dark Mode
    _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    notifyListeners();
  }

  // --- WARNA TEMA GEN Z (JAEGAR POS VIBES) ---

  // Warna Background Utama (Dark: Deep Navy, Light: Soft Grey)
  Color get backgroundColor =>
      _isDarkMode ? const Color(0xFF1F1D2B) : const Color(0xFFF9F9F9);

  // Warna Card/Container (Dark: Lighter Navy, Light: White)
  Color get cardColor => _isDarkMode ? const Color(0xFF2D303E) : Colors.white;

  // Warna Border (Dark: Greyish, Light: Light Grey)
  Color get borderColor =>
      _isDarkMode ? const Color(0xFF393C49) : const Color(0xFFE0E0E0);

  // Warna Text Utama
  Color get textColor => _isDarkMode ? Colors.white : const Color(0xFF2D303E);

  // Warna Text Sekunder (Grey)
  Color get secondaryTextColor =>
      _isDarkMode ? const Color(0xFFABBBC2) : Colors.grey;

  // Warna Aksen Utama (Orange Jaegar)
  Color get primaryColor => const Color(0xFFEA7C69);
}
