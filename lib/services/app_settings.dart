import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Isi struk & aturan toko dari panel admin > Pengaturan.
/// Disimpan juga di HP/tablet supaya struk tetap benar saat server sedang
/// tidak terjangkau.
class AppSettings {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  static const String _prefKey = 'app_settings';

  // Nilai bawaan = isi struk lama, dipakai sampai data admin pertama kali termuat
  String shopName = 'WARUNG BABI GULING\nMEN GEDE';
  String shopAddress = 'Jl. Poppies I, Kuta, Kec. Kuta\nKab. Badung, Bali 80361';
  String shopPhone = '0822-3660-6374';
  String receiptFooter = 'Matur Suksma!\nTerima kasih atas kunjungan Anda';
  bool showCashierOnReceipt = true;
  double taxPercent = 10;
  int lowStockThreshold = 10;

  void _apply(Map<String, dynamic> data) {
    final receipt = data['receipt'];
    if (receipt is Map) {
      String text(String key, String fallback) {
        final value = receipt[key]?.toString().trim() ?? '';
        return value.isEmpty ? fallback : value;
      }

      shopName = text('shop_name', shopName);
      shopAddress = text('shop_address', shopAddress);
      shopPhone = text('shop_phone', shopPhone);
      receiptFooter = text('footer', receiptFooter);
      showCashierOnReceipt = receipt['show_cashier'] != false;
    }
    final tax = data['tax_rate'];
    if (tax is num && tax >= 0) taxPercent = tax.toDouble();
    final threshold = data['low_stock_threshold'];
    if (threshold is num && threshold >= 0) lowStockThreshold = threshold.toInt();
  }

  /// Muat salinan terakhir dari penyimpanan perangkat
  Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) _apply(jsonDecode(raw));
    } catch (e) {
      debugPrint('Pengaturan tersimpan tidak terbaca: $e');
    }
  }

  /// Ambil pengaturan terbaru dari server. true bila berhasil.
  Future<bool> refresh() async {
    final res = await ApiService().getSettings();
    if (res['status'] != 'success' || res['data'] is! Map<String, dynamic>) {
      return false;
    }
    _apply(res['data']);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(res['data']));
    } catch (_) {}
    return true;
  }
}
