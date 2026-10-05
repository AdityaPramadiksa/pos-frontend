import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan kecil di HP/tablet untuk mode offline: salinan data server,
/// kode perangkat, nomor struk, dan PIN kasir yang pernah masuk.
class LocalStore {
  static final Random _random = Random.secure();

  static Future<dynamic> readJson(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      return raw == null ? null : jsonDecode(raw);
    } catch (e) {
      debugPrint('Data lokal $key tidak terbaca: $e');
      return null;
    }
  }

  static Future<void> writeJson(String key, Object? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(value));
    }
  }

  // ---------------- Salinan data server ----------------

  static String _cacheKey(String name) => 'cache_$name';

  static Future<void> cachePut(String name, Object? data) =>
      writeJson(_cacheKey(name), {
        'saved_at': DateTime.now().toIso8601String(),
        'data': data,
      });

  /// {'saved_at': ..., 'data': ...} atau null bila belum pernah tersimpan
  static Future<Map<String, dynamic>?> cacheGet(String name) async {
    final value = await readJson(_cacheKey(name));
    return value is Map<String, dynamic> ? value : null;
  }

  // ---------------- Identitas perangkat ----------------

  /// UUID v4 untuk menandai transaksi supaya tidak tercatat dobel di server
  static String newUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Kode 4 huruf unik per HP/tablet, bagian dari nomor struk
  static Future<String> deviceCode() async {
    final prefs = await SharedPreferences.getInstance();
    String? code = prefs.getString('device_code');
    if (code == null || code.length != 4) {
      // Tanpa huruf yang mirip angka (O/0, I/1)
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      code = List.generate(4, (_) => chars[_random.nextInt(chars.length)])
          .join();
      await prefs.setString('device_code', code);
    }
    return code;
  }

  /// Nomor struk dibuat di perangkat supaya struk yang dicetak saat offline
  /// sama dengan yang nanti tercatat di server. Contoh: INV-20261005-K7AB-012
  static Future<String> nextReceiptNumber([DateTime? at]) async {
    final prefs = await SharedPreferences.getInstance();
    final String date = DateFormat('yyyyMMdd').format(at ?? DateTime.now());
    final String code = await deviceCode();
    const String seqKey = 'receipt_seq';
    final Map<String, dynamic> seq =
        (await readJson(seqKey) as Map<String, dynamic>?) ?? {};
    final int next = (seq['date'] == date ? (seq['n'] as int? ?? 0) : 0) + 1;
    await prefs.setString(seqKey, jsonEncode({'date': date, 'n': next}));
    return 'INV-$date-$code-${next.toString().padLeft(3, '0')}';
  }

  // ---------------- Masuk tanpa internet ----------------

  static const String _loginsKey = 'offline_logins';

  static Future<String> _pinHash(String pin) async {
    final String salt = await deviceCode();
    return sha256.convert(utf8.encode('$salt:men-gede:$pin')).toString();
  }

  /// Simpan sesi kasir yang berhasil masuk online, supaya PIN yang sama bisa
  /// dipakai masuk saat sinyal hilang. PIN tidak disimpan, hanya hash-nya.
  static Future<void> rememberLogin(
      String pin, Map<String, dynamic> user, String token) async {
    final String hash = await _pinHash(pin);
    final int? userId = int.tryParse(user['id']?.toString() ?? '');
    final List<dynamic> logins =
        (await readJson(_loginsKey) as List<dynamic>?) ?? [];
    logins.removeWhere((l) => l['pin_hash'] == hash || l['user_id'] == userId);
    logins.add({
      'pin_hash': hash,
      'user_id': userId,
      'name': user['name']?.toString() ?? 'Kasir',
      'role': user['role']?.toString() ?? 'cashier',
      'token': token,
    });
    await writeJson(_loginsKey, logins);
  }

  static Future<Map<String, dynamic>?> findLogin(String pin) async {
    final String hash = await _pinHash(pin);
    final List<dynamic> logins =
        (await readJson(_loginsKey) as List<dynamic>?) ?? [];
    for (final l in logins) {
      if (l is Map<String, dynamic> && l['pin_hash'] == hash) return l;
    }
    return null;
  }

  /// PIN ditolak server (sudah diganti admin): jangan bisa dipakai offline lagi
  static Future<void> forgetLogin(String pin) async {
    final String hash = await _pinHash(pin);
    final List<dynamic> logins =
        (await readJson(_loginsKey) as List<dynamic>?) ?? [];
    logins.removeWhere((l) => l['pin_hash'] == hash);
    await writeJson(_loginsKey, logins);
  }
}
