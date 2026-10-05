import 'package:flutter/foundation.dart';

/// Halaman yang sedang dibuka di layout utama. Dipakai supaya halaman lain
/// bisa berpindah tab, mis. dari Bill ke Kasir saat menambah pesanan.
class NavProvider with ChangeNotifier {
  static const int kasir = 0;
  static const int bills = 1;
  static const int riwayat = 2;
  static const int kasKeluar = 3;
  static const int rekap = 4;
  static const int printer = 5;

  int _index = kasir;
  int get index => _index;

  void goTo(int index) {
    if (_index == index) return;
    _index = index;
    notifyListeners();
  }
}
