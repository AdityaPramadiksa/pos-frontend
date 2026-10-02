import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/menu_model.dart';
import '../models/category_model.dart';
import '../models/discount_model.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiService {
// 1. IP server (Laravel) bawaan. Bisa diganti dari halaman login (ikon gear)
//    tanpa build ulang, mis. saat laptop pindah WiFi dan IP-nya berubah.
  static const String defaultIpAddress = "192.168.43.67";
  static const String _serverPrefKey = 'server_address';
  static String ipAddress = defaultIpAddress;

  // 2. Alamat boleh "192.168.1.10" (port 8000) atau lengkap "192.168.1.10:8080"
  static String get _host =>
      ipAddress.contains(':') ? ipAddress : "$ipAddress:8000";
  static String get baseUrl => "http://$_host/api";
  static String get baseStorageUrl => "http://$_host/storage/";

  /// Dipanggil sekali saat aplikasi dibuka
  static Future<void> loadServerAddress() async {
    final prefs = await SharedPreferences.getInstance();
    ipAddress = prefs.getString(_serverPrefKey) ?? defaultIpAddress;
  }

  static Future<void> saveServerAddress(String address) async {
    address = address
        .trim()
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/.*$'), '');
    if (address.isEmpty) address = defaultIpAddress;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverPrefKey, address);
    ipAddress = address;
  }

  static const Duration _timeout = Duration(seconds: 20);

  Future<String?> _getToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    String? token = await _getToken();
    return {
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Error validasi Laravel (422) tidak punya key 'status', jadi kita lengkapi
  // di sini supaya semua halaman cukup mengecek res['status'] == 'success'.
  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        decoded['status'] ??= (response.statusCode >= 200 &&
                response.statusCode < 300)
            ? 'success'
            : 'error';
        return decoded;
      }
    } catch (_) {}
    return {
      'status': 'error',
      'message': 'Respon server tidak valid (${response.statusCode})',
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
      return {'status': 'error', 'message': 'Koneksi gagal: $e'};
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
      return {'status': 'error', 'message': 'Koneksi gagal: $e'};
    }
  }

  Future<List<dynamic>> _getList(String endpoint) async {
    final res = await _get(endpoint);
    if (res['status'] == 'success' && res['data'] is List) {
      return res['data'];
    }
    return [];
  }

  // 1. Login PIN
  Future<Map<String, dynamic>> loginPin(String pin) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/login-pin'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'pin': pin}),
          )
          .timeout(_timeout);
      final data = _decode(response);
      if (response.statusCode == 200 && data['data'] != null) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['data']['token'].toString());
        await prefs.setString(
          'user_name',
          data['data']['user']['name'].toString(),
        );
        await prefs.setString('role', data['data']['user']['role'].toString());
      }
      return data;
    } catch (e) {
      return {'status': 'error', 'message': 'Gagal terhubung ke server: $e'};
    }
  }

  // 1b. Logout (shift tetap terbuka, hanya token yang dihapus)
  Future<void> logout() async {
    await _post('/logout', {});
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  // 2. Ambil Kategori
  Future<List<CategoryModel>> getCategories() async {
    final data = await _getList('/categories');
    return data.map((item) => CategoryModel.fromJson(item)).toList();
  }

  // 3. Ambil Menu
  Future<List<MenuModel>> getMenus() async {
    final data = await _getList('/menus');
    return data.map((item) => MenuModel.fromJson(item)).toList();
  }

  // 4. Ambil Diskon
  Future<List<DiscountModel>> getDiscounts() async {
    final data = await _getList('/discounts');
    return data.map((item) => DiscountModel.fromJson(item)).toList();
  }

  // 4b. Pengaturan toko (tarif pajak)
  Future<Map<String, dynamic>> getSettings() => _get('/settings');

  // 5. Simpan Transaksi
  // isPending = true  -> simpan ke meja (belum bayar)
  // amountPaid        -> uang tunai yang diterima (khusus cash)
  Future<Map<String, dynamic>> saveTransaction({
    required List<dynamic> items,
    required String orderType,
    String? paymentMethod,
    String deliveryPlatform = '',
    String customerName = 'Pelanggan Umum',
    String tableNumber = '-',
    int? discountId,
    int? amountPaid,
    bool isPending = false,
  }) async {
    String formattedOrderType = orderType.toLowerCase().trim().replaceAll(
          ' ',
          '_',
        );
    if (formattedOrderType.contains('dine')) formattedOrderType = 'dine_in';
    if (formattedOrderType.contains('go')) formattedOrderType = 'to_go';
    if (formattedOrderType.contains('deliv')) formattedOrderType = 'delivery';

    return await _post('/orders', {
      "order_type": formattedOrderType,
      if (formattedOrderType == 'delivery')
        "delivery_platform": deliveryPlatform.toLowerCase(),
      if (!isPending && paymentMethod != null)
        "payment_method": paymentMethod.toLowerCase(),
      "is_pending": isPending,
      "customer_name": customerName,
      "table_number": tableNumber,
      if (amountPaid != null) "amount_paid": amountPaid,
      "discount_id": discountId,
      "items": items
          .map(
            (item) => {
              "menu_id": item.menu.id,
              "qty": item.quantity,
              "note": item.note,
            },
          )
          .toList(),
    });
  }

  // 6. Settlement Status
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

    if (response['status'] == 'success') {
      return response;
    } else {
      return {
        'status': 'error',
        'message': response['message'] ?? 'Gagal menutup shift'
      };
    }
  }

  // 7b. Laporan shift terakhir yang sudah ditutup (cetak ulang)
  Future<Map<String, dynamic>> getLastSettlement() => _get('/settlement/last');

  // 8. Order History
  Future<List<dynamic>> getOrderHistory() => _getList('/orders/history');

  // 9. Void Order
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
      _get('/orders/recapitulation');

  // 11. Pending Bills
  Future<List<dynamic>> getPendingBills() => _getList('/orders/pending');

// 12. Pay Pending
  Future<Map<String, dynamic>> payPendingBill(
    int orderId,
    String paymentMethod,
    int? amountPaid,
  ) async {
    return await _post('/orders/$orderId/pay', {
      'payment_method': paymentMethod.toLowerCase(),
      // Kalau amountPaid ada nilainya kirim, kalau tidak jangan kirim
      if (amountPaid != null) 'amount_paid': amountPaid,
    });
  }

  // 13. Petty Cash Add
  Future<Map<String, dynamic>> addExpense({
    required int amount,
    required String description,
    XFile? imageFile,
  }) async {
    try {
      String? token = await _getToken();
      var uri = Uri.parse('$baseUrl/expenses');
      var request = http.MultipartRequest('POST', uri);
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      request.fields['amount'] = amount.toString();
      request.fields['description'] = description;

      if (imageFile != null) {
        if (kIsWeb) {
          var bytes = await imageFile.readAsBytes();
          request.files.add(
            http.MultipartFile.fromBytes(
              'receipt_image',
              bytes,
              filename: imageFile.name,
            ),
          );
        } else {
          request.files.add(
            await http.MultipartFile.fromPath('receipt_image', imageFile.path),
          );
        }
      }
      var streamedResponse = await request.send().timeout(_timeout);
      var response = await http.Response.fromStream(streamedResponse);
      return _decode(response);
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // 14. Petty Cash List (shift yang sedang berjalan)
  Future<Map<String, dynamic>> getExpenses() => _get('/expenses');
}
