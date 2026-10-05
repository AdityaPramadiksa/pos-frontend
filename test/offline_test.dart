// Uji mode offline: transaksi tetap jalan tanpa server, tersimpan di
// perangkat, lalu terkirim berurutan (tanpa dobel) saat sinyal kembali.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_babi_guling/models/menu_model.dart';
import 'package:pos_babi_guling/providers/cart_provider.dart';
import 'package:pos_babi_guling/services/api_service.dart';
import 'package:pos_babi_guling/services/pos_service.dart';
import 'package:pos_babi_guling/services/sync_service.dart';

/// Server tiruan yang bisa "mati" (sinyal hilang)
class FakeServer {
  bool online = true;
  final List<({String method, String path, Map<String, dynamic> body})> calls =
      [];
  int _nextId = 100;

  Map<String, dynamic> menu(int id, String name, int price, int stock) => {
        'id': id,
        'category_id': 1,
        'name': name,
        'price': price,
        'price_dine_in': price,
        'price_online': price + 5000,
        'image': '',
        'image_url': '',
        'stock': stock,
        'is_available': true,
      };

  Map<String, dynamic> serverBill(dynamic id) => {
        'id': id,
        'client_uuid': null,
        'receipt_number': 'INV-20261005-0007',
        'customer_name': 'Pelanggan Umum',
        'table_number': '7',
        'order_type': 'dine_in',
        'subtotal': 70000,
        'tax_amount': 7000,
        'discount_amount': 0,
        'total_price': 77000,
        'status': 'pending',
        'created_at': '2026-10-05T03:00:00.000000Z',
        'items': [
          {
            'menu_id': 1,
            'qty': 2,
            'price': 35000,
            'subtotal': 70000,
            'menu': {'name': 'Nasi Campur'}
          }
        ],
      };

  List<Map<String, dynamic>> get writes =>
      calls.where((c) => c.method == 'POST').map((c) => {
            'path': c.path,
            ...c.body,
          }).toList();

  MockClient get client => MockClient((request) async {
        if (!online) throw http.ClientException('Network is unreachable');
        Map<String, dynamic> body = {};
        if (request.headers['content-type']?.contains('json') ?? false) {
          body = request.body.isEmpty ? {} : jsonDecode(request.body);
        } else if (request.method == 'POST') {
          body = {'multipart': true};
        }
        calls.add((method: request.method, path: request.url.path, body: body));
        final (int code, Object data) = _handle(request.method, request.url.path, body);
        return http.Response(jsonEncode(data), code,
            headers: {'content-type': 'application/json'});
      });

  (int, Object) _handle(String method, String path, Map<String, dynamic> body) {
    if (path == '/api/ping') return (200, {'status': 'success'});
    if (path == '/api/login-pin') {
      if (body['pin'] == '1111') {
        return (
          200,
          {
            'status': 'success',
            'data': {
              'user': {'id': 5, 'name': 'Kasir Komang', 'role': 'cashier'},
              'token': 'token-komang',
            }
          }
        );
      }
      return (401, {'status': 'error', 'message': 'PIN salah'});
    }
    if (path == '/api/menus') {
      return (
        200,
        {
          'status': 'success',
          'data': [menu(1, 'Nasi Campur', 35000, 20), menu(2, 'Es Teh', 5000, 3)]
        }
      );
    }
    if (path == '/api/categories') {
      return (200, {'status': 'success', 'data': [{'id': 1, 'name': 'Makanan'}]});
    }
    if (path == '/api/orders/pending') {
      return (200, {'status': 'success', 'data': [serverBill(7)]});
    }
    if (path == '/api/orders/history' || path == '/api/expenses') {
      return (200, {'status': 'success', 'data': []});
    }
    if (method == 'POST' && path == '/api/orders') {
      if ((body['items'] as List).any((i) => i['menu_id'] == 2) &&
          body['offline'] != true) {
        return (400, {'status': 'error', 'message': 'Stok Es Teh tidak cukup (sisa 3).'});
      }
      return (
        201,
        {
          'status': 'success',
          'data': {
            'id': _nextId++,
            'client_uuid': body['client_uuid'],
            'receipt_number': body['receipt_number'],
            'status': body['is_pending'] == true ? 'pending' : 'paid',
            'items': [],
          }
        }
      );
    }
    if (method == 'POST' && path.startsWith('/api/orders/')) {
      if (path.contains('/999/')) {
        return (400, {'status': 'error', 'message': 'Pesanan ini sudah lunas atau dibatalkan.'});
      }
      return (200, {'status': 'success', 'data': serverBill(7)});
    }
    if (method == 'POST' && path == '/api/expenses') {
      return (201, {'status': 'success', 'data': {}});
    }
    if (method == 'POST' && path == '/api/settlement/close') {
      return (200, {'status': 'success', 'data': {}});
    }
    return (404, {'status': 'error', 'message': 'Tidak dikenal $path'});
  }
}

MenuModel _model(Map<String, dynamic> m) => MenuModel.fromJson(m);

CartProvider _cart(FakeServer server, List<(int, int)> lines,
    {String table = '5', Map<String, dynamic>? appendTo}) {
  final cart = CartProvider()..setTaxPercent(10);
  if (appendTo != null) cart.startAppend(appendTo);
  for (final (id, qty) in lines) {
    final menu = _model(id == 1
        ? server.menu(1, 'Nasi Campur', 35000, 20)
        : server.menu(2, 'Es Teh', 5000, 3));
    for (int i = 0; i < qty; i++) {
      cart.addToCart(menu);
    }
  }
  cart.setCustomerInfo('', table);
  return cart;
}

void main() {
  late FakeServer server;

  setUpAll(() => SyncService.periodic = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'token': 'token-komang',
      'user_name': 'Kasir Komang',
      'user_id': 5,
    });
    SyncService().debugReset();
    server = FakeServer();
  });

  Future<T> run<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => server.client);

  test('alamat server: IP pakai http:8000, domain pakai https', () {
    final saved = ApiService.ipAddress;
    ApiService.ipAddress = '192.168.1.10';
    expect(ApiService.baseUrl, 'http://192.168.1.10:8000/api');
    ApiService.ipAddress = '192.168.1.10:8080';
    expect(ApiService.baseUrl, 'http://192.168.1.10:8080/api');
    ApiService.ipAddress = 'pos.mengede.com';
    expect(ApiService.baseUrl, 'https://pos.mengede.com/api');
    ApiService.ipAddress = 'https://mengede.com/kasir';
    expect(ApiService.baseUrl, 'https://mengede.com/kasir/api');
    ApiService.ipAddress = saved;
  });

  test('masuk tanpa internet hanya dengan PIN yang pernah masuk online', () async {
    await run(() async {
      server.online = false;
      final first = await ApiService().loginPin('1111');
      expect(first['status'], 'error');
      expect(first['message'], contains('belum pernah'));

      server.online = true;
      expect((await ApiService().loginPin('1111'))['status'], 'success');

      server.online = false;
      final offline = await ApiService().loginPin('1111');
      expect(offline['status'], 'success');
      expect(offline['offline'], true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), 'token-komang');
      expect(prefs.getInt('user_id'), 5);

      // PIN lain tetap ditolak
      expect((await ApiService().loginPin('2222'))['status'], 'error');
    });
  });

  test('transaksi offline tersimpan, tampil di aplikasi, lalu terkirim berurutan',
      () async {
    await run(() async {
      final pos = PosService();
      // Data sempat termuat saat online
      await pos.menus();
      await pos.pendingBills();

      server.online = false;

      // 1. Pesanan langsung bayar tunai
      final paid = await pos.createOrder(_cart(server, [(1, 2)]),
          pending: false, amountPaid: 100000);
      expect(paid['status'], 'success');
      expect(paid['queued'], true);
      final order = paid['data'] as Map<String, dynamic>;
      expect(order['receipt_number'],
          matches(RegExp(r'^INV-\d{8}-[A-Z0-9]{4}-001$')));
      expect(order['total_price'], 77000);
      expect(order['change_amount'], 23000);
      expect(order['items'][0]['menu']['name'], 'Nasi Campur');

      // Stok di kasir ikut berkurang walau server belum tahu
      final menus = await pos.menus();
      expect(menus.firstWhere((m) => m.id == 1).stock, 18);

      // 2. Simpan bill baru, tambah pesanan, lalu lunasi bill server
      final bill = await pos.createOrder(_cart(server, [(1, 1)], table: '9'),
          pending: true);
      expect(bill['queued'], true);
      final localBill = bill['data'] as Map<String, dynamic>;

      var bills = await pos.pendingBills();
      expect(bills.fresh, false);
      expect(bills.items.map((b) => b['table_number']), containsAll(['9', '7']));

      final added = await pos.addItemsToBill(
          localBill, _cart(server, [(2, 2)], table: '9', appendTo: localBill));
      expect(added['queued'], true);
      // 35000 + 2 x 5000 = 45000, pajak 4500
      expect(added['data']['total_price'], 49500);
      expect(added['data']['new_items'].length, 1);

      final serverBill = bills.items.firstWhere((b) => b['id'] == 7);
      final payServer = await pos.payBill(serverBill, method: 'qris');
      expect(payServer['queued'], true);

      bills = await pos.pendingBills();
      expect(bills.items.any((b) => b['id'] == 7), false,
          reason: 'bill yang sudah dilunasi offline tidak muncul lagi');

      // 3. Kas keluar
      final expense =
          await pos.addExpense(amount: 25000, description: 'Beli es batu');
      expect(expense['queued'], true);
      expect((await pos.expenses()).items.first['description'], 'Beli es batu');

      // Riwayat menampilkan transaksi yang belum terkirim
      final history = await pos.history();
      expect(history.items.where(PosService.isUnsynced).length,
          greaterThanOrEqualTo(3));

      // Tutup shift ditahan sampai semua terkirim
      final close = await pos.closeShift('');
      expect(close['status'], 'error');
      expect(close['message'], contains('belum terkirim'));
      expect(SyncService().pendingCount, 5);
      expect(SyncService().isOnline, false);

      // Sinyal kembali
      server.online = true;
      await SyncService().syncNow();

      expect(SyncService().pendingCount, 0);
      expect(SyncService().failedCount, 0);
      expect(SyncService().isOnline, true);
      expect(SyncService().syncedTick, greaterThan(0));

      final writes = server.writes;
      expect(writes.map((w) => w['path']).toList(), [
        '/api/orders',
        '/api/orders',
        '/api/orders/${localBill['client_uuid']}/items',
        '/api/orders/7/pay',
        '/api/expenses',
      ]);
      // Server menerima apa adanya: tanda offline, uuid, nomor struk, harga
      expect(writes[0]['offline'], true);
      expect(writes[0]['client_uuid'], order['client_uuid']);
      expect(writes[0]['receipt_number'], order['receipt_number']);
      expect(writes[0]['amount_paid'], 100000);
      expect(writes[0]['tax_amount'], 7000);
      expect(writes[0]['items'][0]['price'], 35000);
      expect(writes[1]['is_pending'], true);
      expect(writes[2]['batch_uuid'], isNotNull);
      expect(writes[2]['items'], [
        {'menu_id': 2, 'qty': 2, 'note': null, 'price': 5000}
      ]);
      expect(writes[3]['op_uuid'], isNotNull);
      expect(writes[3]['payment_method'], 'qris');
      expect(writes[4]['multipart'], true);

      // Setelah terkirim, tutup shift boleh
      expect((await pos.closeShift(''))['status'], 'success');
    });
  });

  test('saat online, penolakan server langsung tampil dan tidak diantrekan',
      () async {
    await run(() async {
      final res = await PosService()
          .createOrder(_cart(server, [(2, 4)]), pending: false, amountPaid: 50000);
      expect(res['status'], 'error');
      expect(res['message'], contains('Stok Es Teh'));
      expect(SyncService().ops, isEmpty);

      final ok = await PosService()
          .createOrder(_cart(server, [(1, 1)]), pending: false, amountPaid: 50000);
      expect(ok['status'], 'success');
      expect(ok['queued'], isNull);
      expect(ok['data']['id'], 100);
      expect(SyncService().ops, isEmpty);
    });
  });

  test('ditolak saat dikirim belakangan: ditandai gagal, bisa dihapus', () async {
    await run(() async {
      server.online = false;
      final bill = server.serverBill(999);
      final res = await PosService().payBill(bill, method: 'cash', amountPaid: 80000);
      expect(res['queued'], true);

      server.online = true;
      await SyncService().syncNow();
      expect(SyncService().failedCount, 1);
      expect(SyncService().failedOps.first.error, contains('sudah lunas'));
      // Riwayat menandai transaksi yang gagal
      final history = await PosService().history();
      expect(history.items.first['_failed'], true);

      await SyncService().discard(SyncService().failedOps.first.id);
      expect(SyncService().ops, isEmpty);
    });
  });

  test('antrean tetap ada setelah aplikasi ditutup', () async {
    await run(() async {
      await PosService().menus(); // salinan menu tersimpan saat online
      server.calls.clear();
      server.online = false;
      await PosService().updateStock(
          _model(server.menu(2, 'Es Teh', 5000, 3)), 0);
      expect(SyncService().pendingCount, 1);

      // Aplikasi dibuka ulang: antrean dibaca dari penyimpanan
      SyncService().debugReset();
      await SyncService().load();
      expect(SyncService().pendingCount, 1);
      final menus = await PosService().menus();
      expect(menus.firstWhere((m) => m.id == 2).stock, 0);

      server.online = true;
      await SyncService().syncNow();
      expect(SyncService().pendingCount, 0);
      expect(server.writes.single['path'], '/api/menus/2/stock');
    });
  });
}
