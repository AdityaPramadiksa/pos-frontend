import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/menu_model.dart';
import '../models/category_model.dart';
import '../models/discount_model.dart';
import 'local_store.dart';
import 'sync_service.dart';

/// Hasil GET yang bisa berasal dari server atau dari salinan di perangkat
class ListResult {
  final List<dynamic> data;

  /// true = data terbaru dari server, false = salinan terakhir (offline)
  final bool fresh;
  final DateTime? savedAt;

  const ListResult(this.data, {required this.fresh, this.savedAt});
}

class ApiService {
  // 1. Alamat server bawaan. Bisa diganti dari halaman login tanpa build ulang.
  //    Boleh berupa IP laptop di WiFi warung ("192.168.1.10", port 8000) atau
  //    alamat hosting ("https://pos.namawarung.com").
  static const String defaultIpAddress = "192.168.18.8";
  static const String _serverPrefKey = 'server_address';
  static String ipAddress = defaultIpAddress;

  /// Alamat lengkap server tanpa garis miring di akhir.
  /// IP/localhost tanpa skema -> http dengan port 8000 (php artisan serve),
  /// nama domain tanpa skema -> https (hosting).
  static String get serverRoot {
    String address = ipAddress.trim();
    if (!address.startsWith('http://') && !address.startsWith('https://')) {
      final String hostPart = address.split('/').first;
      final String host = hostPart.split(':').first;
      final bool local = host == 'localhost' ||
          host.endsWith('.local') ||
          RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
      if (local) {
        final String withPort =
            hostPart.contains(':') ? hostPart : '$hostPart:8000';
        address = 'http://${address.replaceFirst(hostPart, withPort)}';
      } else {
        address = 'https://$address';
      }
    }
    return address.replaceFirst(RegExp(r'/+$'), '');
  }

  static String get baseUrl => "$serverRoot/api";
  static String get baseStorageUrl => "$serverRoot/storage/";

  /// Dipanggil sekali saat aplikasi dibuka
  static Future<void> loadServerAddress() async {
    final prefs = await SharedPreferences.getInstance();
    ipAddress = prefs.getString(_serverPrefKey) ?? defaultIpAddress;
  }

  static Future<void> saveServerAddress(String address) async {
    address = address
        .trim()
        .replaceFirst(RegExp(r'/+$'), '')
        .replaceFirst(RegExp(r'/api$'), '');
    if (address.isEmpty) address = defaultIpAddress;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverPrefKey, address);
    ipAddress = address;
  }

  static const Duration _timeout = Duration(seconds: 15);

  Future<String?> _getToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<Map<String, String>> _headers({bool json = false, String? token}) async {
    token ??= await _getToken();
    return {
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Error validasi Laravel (422) tidak punya key 'status', jadi kita lengkapi
  // di sini supaya semua halaman cukup mengecek res['status'] == 'success'.
  // '_http' = kode HTTP, dipakai antrean offline untuk memutuskan kirim ulang.
  Map<String, dynamic> _decode(http.Response response) {
    SyncService().markReachable(true);
    final bool ok = response.statusCode >= 200 && response.statusCode < 300;
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        decoded['status'] ??= ok ? 'success' : 'error';
        if (!ok) decoded['status'] = 'error';
        if (response.statusCode == 401) {
          decoded['message'] = 'Sesi berakhir. Silakan keluar lalu masuk lagi dengan PIN.';
        }
        decoded['_http'] = response.statusCode;
        return decoded;
      }
    } catch (_) {}
    return {
      'status': 'error',
      '_http': response.statusCode,
      'message': 'Respon server tidak valid (${response.statusCode})',
    };
  }

  // Server tidak terjangkau: sinyal hilang, WiFi mati, atau alamat salah
  Map<String, dynamic> _offline(Object e) {
    SyncService().markReachable(false);
    return {
      'status': 'error',
      'offline': true,
      '_http': 0,
      'message': 'Tidak tersambung ke server ($ipAddress). Periksa internet.',
    };
  }

  // --- HELPER PRIVATE UNTUK REQUEST GET ---
  Future<Map<String, dynamic>> _get(String endpoint) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl$endpoint'), headers: await _headers())
          .timeout(_timeout);
      return _decode(response);
    } catch (e) {
      return _offline(e);
    }
  }

  // --- HELPER PRIVATE UNTUK REQUEST POST ---
  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: await _headers(json: true),
            body: json.encode(body),
          )
          .timeout(_timeout);
      return _decode(response);
    } catch (e) {
      return _offline(e);
    }
  }

  /// GET daftar. Berhasil -> disimpan di perangkat. Server tidak terjangkau
  /// -> salinan terakhir yang tersimpan.
  Future<ListResult> _getCachedList(String endpoint, String cacheName) async {
    final res = await _get(endpoint);
    if (res['status'] == 'success' && res['data'] is List) {
      await LocalStore.cachePut(cacheName, res['data']);
      return ListResult(res['data'], fresh: true, savedAt: DateTime.now());
    }
    final cached = await LocalStore.cacheGet(cacheName);
    return ListResult(
      cached?['data'] is List ? cached!['data'] : const [],
      fresh: false,
      savedAt: DateTime.tryParse(cached?['saved_at']?.toString() ?? ''),
    );
  }

  /// GET objek dengan salinan di perangkat. Hasil salinan diberi
  /// 'cached': true dan 'saved_at'.
  Future<Map<String, dynamic>> _getCachedMap(
      String endpoint, String cacheName) async {
    final res = await _get(endpoint);
    if (res['status'] == 'success') {
      await LocalStore.cachePut(cacheName, res['data']);
      return res;
    }
    if (res['offline'] != true) return res;
    final cached = await LocalStore.cacheGet(cacheName);
    if (cached == null || cached['data'] == null) return res;
    return {
      'status': 'success',
      'cached': true,
      'saved_at': cached['saved_at'],
      'data': cached['data'],
    };
  }

  /// Kirim perintah dari antrean offline. Mengembalikan '_http' = 0 bila
  /// server tidak terjangkau.
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> body, {
    required String token,
    bool multipart = false,
    List<int>? fileBytes,
    String? fileName,
    String fileField = 'receipt_image',
    Duration? timeout,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      if (!multipart) {
        final response = await http
            .post(uri,
                headers: await _headers(json: true, token: token),
                body: json.encode(body))
            .timeout(timeout ?? _timeout);
        return _decode(response);
      }

      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _headers(token: token));
      body.forEach((key, value) {
        if (value != null) request.fields[key] = value.toString();
      });
      if (fileBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(fileField, fileBytes,
            filename: fileName ?? 'nota.jpg'));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 40));
      return _decode(await http.Response.fromStream(streamed));
    } catch (e) {
      return _offline(e);
    }
  }

  /// Cek server bisa dihubungi (tanpa token)
  Future<bool> ping() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/ping'), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      final bool ok = response.statusCode == 200;
      SyncService().markReachable(ok);
      return ok;
    } catch (_) {
      SyncService().markReachable(false);
      return false;
    }
  }

  // 1. Login PIN. Tanpa internet, PIN yang pernah masuk di perangkat ini
  //    tetap bisa dipakai.
  Future<Map<String, dynamic>> loginPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/login-pin'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'pin': pin,
              'device_id': await LocalStore.deviceCode(),
            }),
          )
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['data'] != null) {
        final Map<String, dynamic> user =
            Map<String, dynamic>.from(data['data']['user']);
        final String token = data['data']['token'].toString();
        await _saveSession(prefs, user, token);
        await LocalStore.rememberLogin(pin, user, token);
        await SyncService().reauthorize(user['id'], token);
      } else if (response.statusCode == 401) {
        await LocalStore.forgetLogin(pin);
        data['message'] = 'PIN salah. Coba lagi atau tanyakan PIN ke admin.';
      }
      return data;
    } catch (e) {
      _offline(e);
      final saved = await LocalStore.findLogin(pin);
      if (saved == null) {
        return {
          'status': 'error',
          'offline': true,
          'message':
              'Tidak tersambung ke server. PIN ini belum pernah dipakai masuk di perangkat ini, jadi belum bisa dipakai tanpa internet.',
        };
      }
      await _saveSession(
        prefs,
        {'id': saved['user_id'], 'name': saved['name'], 'role': saved['role']},
        saved['token'].toString(),
      );
      return {
        'status': 'success',
        'offline': true,
        'message': 'Masuk tanpa internet. Transaksi dikirim saat sinyal kembali.',
      };
    }
  }

  Future<void> _saveSession(
      SharedPreferences prefs, Map<String, dynamic> user, String token) async {
    await prefs.setString('token', token);
    await prefs.setString('user_name', user['name']?.toString() ?? 'Kasir');
    await prefs.setString('role', user['role']?.toString() ?? 'cashier');
    final int? id = int.tryParse(user['id']?.toString() ?? '');
    if (id != null) {
      await prefs.setInt('user_id', id);
    } else {
      await prefs.remove('user_id');
    }
  }

  // 1b. Keluar. Token di server sengaja tidak dicabut: transaksi offline
  //     kasir ini masih memakainya untuk terkirim nanti. Shift tetap terbuka.
  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  // 2. Ambil Kategori
  Future<List<CategoryModel>> getCategories() async {
    final res = await _getCachedList('/categories', 'categories');
    return res.data.map((item) => CategoryModel.fromJson(item)).toList();
  }

  // 3. Ambil Menu (data mentah, stok disesuaikan antrean oleh PosService)
  Future<ListResult> getMenusRaw() => _getCachedList('/menus', 'menus');

  Future<List<MenuModel>> getMenus() async {
    final res = await getMenusRaw();
    return res.data.map((item) => MenuModel.fromJson(item)).toList();
  }

  // 4. Ambil Diskon
  Future<List<DiscountModel>> getDiscounts() async {
    final res = await _getCachedList('/discounts', 'discounts');
    return res.data.map((item) => DiscountModel.fromJson(item)).toList();
  }

  // 4b. Pengaturan toko (isi struk, pajak, batas stok)
  Future<Map<String, dynamic>> getSettings() => _get('/settings');

  // 6. Settlement Status (membuka shift otomatis di server)
  Future<Map<String, dynamic>> checkSettlementStatus() =>
      _get('/settlement/status');

  // 7. Tutup Shift. actualCash = uang fisik hasil hitung kasir (opsional)
  Future<Map<String, dynamic>> closeSettlement(
    String notes, {
    int? actualCash,
  }) async {
    final response = await _post('/settlement/close', {
      'notes': notes,
      if (actualCash != null) 'actual_cash': actualCash,
    });

    if (response['status'] == 'success') return response;
    return {
      'status': 'error',
      'offline': response['offline'],
      'message': response['offline'] == true
          ? 'Tutup shift butuh koneksi ke server. Sambungkan internet lalu coba lagi.'
          : response['message'] ?? 'Gagal menutup shift',
    };
  }

  // 7b. Laporan shift terakhir yang sudah ditutup (cetak ulang)
  Future<Map<String, dynamic>> getLastSettlement() =>
      _getCachedMap('/settlement/last', 'settlement_last');

  // 8. Order History (hari ini)
  Future<ListResult> getOrderHistory() =>
      _getCachedList('/orders/history', 'order_history');

  // 9. Void Order (wajib online: PIN admin dicek server)
  Future<Map<String, dynamic>> voidOrder(
    int orderId,
    String pin,
    String reason,
  ) async {
    return await _post('/orders/$orderId/void', {
      'admin_pin': pin,
      'void_reason': reason,
    });
  }

  // 10. Sales Recap (shift yang sedang berjalan)
  Future<Map<String, dynamic>> getSalesRecapitulation() =>
      _getCachedMap('/orders/recapitulation', 'recap');

  // 11. Pending Bills
  Future<ListResult> getPendingBills() =>
      _getCachedList('/orders/pending', 'pending_bills');

  // 14. Petty Cash List (shift yang sedang berjalan)
  Future<ListResult> getExpenses() => _getCachedList('/expenses', 'expenses');
}
