import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Token warna aplikasi kasir. Tampilan utama terang (mudah dibaca di siang
/// hari); mode gelap tetap tersedia lewat [toggleTheme].
class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = false;

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
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    notifyListeners();
  }

  Color _pick(int light, int dark) => Color(_isDarkMode ? dark : light);

  // --- Permukaan ---
  Color get backgroundColor => _pick(0xFFF5F6F4, 0xFF1B1F1E);
  Color get cardColor => _pick(0xFFFFFFFF, 0xFF252A29);
  Color get subtleColor => _pick(0xFFF0F2EF, 0xFF2D3332);
  Color get borderColor => _pick(0xFFE2E6E3, 0xFF353C3A);
  Color get fieldBorderColor => _pick(0xFFD5DBD7, 0xFF424A48);

  // --- Teks ---
  Color get textColor => _pick(0xFF1D2422, 0xFFF1F3F2);
  Color get secondaryTextColor => _pick(0xFF5D6965, 0xFFA9B3AF);
  Color get faintTextColor => _pick(0xFF8A9591, 0xFF7C8783);

  /// Latar gelap untuk tombol sekunder kuat, chip terpilih, dan bar keranjang
  Color get inkColor => _pick(0xFF1D2422, 0xFFF1F3F2);
  Color get onInkColor => _pick(0xFFFFFFFF, 0xFF1D2422);

  // --- Aksen (cokelat karamel kulit babi guling) ---
  Color get primaryColor => const Color(0xFF9A5317);
  Color get primaryDarkColor => _pick(0xFF7A4011, 0xFFE0A06A);
  Color get primarySoftColor => _pick(0xFFF6EDE4, 0xFF3A2A1C);

  // --- Status ---
  Color get successColor => _pick(0xFF2E7D4F, 0xFF5FBF88);
  Color get successSoftColor => _pick(0xFFE7F2EB, 0xFF1F3628);
  Color get warningColor => _pick(0xFFA86A00, 0xFFE5A93C);
  Color get warningSoftColor => _pick(0xFFFBF1DC, 0xFF3A2F17);
  Color get warningInkColor => _pick(0xFF6E4600, 0xFFF1CB82);
  Color get dangerColor => _pick(0xFFB83A2B, 0xFFE8796B);
  Color get dangerSoftColor => _pick(0xFFFBE9E6, 0xFF3D221E);

  // --- Foto menu kosong ---
  Color get placeholderColor => _pick(0xFFF1F1EF, 0xFF2D3332);
  Color get placeholderIconColor => _pick(0xFFA3A8A5, 0xFF6F7975);
}
