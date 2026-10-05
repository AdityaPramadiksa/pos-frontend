// Uji ujung-ke-ujung dengan server Laravel sungguhan (bukan tiruan).
// Hanya jalan bila E2E_SERVER diisi, mis.:
//   flutter test test/e2e_offline_server_test.dart --dart-define=E2E_SERVER=127.0.0.1:8001
// Server harus memakai database uji (punya kasir PIN 1111 & menu id 1).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_babi_guling/models/menu_model.dart';
import 'package:pos_babi_guling/providers/cart_provider.dart';
import 'package:pos_babi_guling/services/api_service.dart';
import 'package:pos_babi_guling/services/pos_service.dart';
import 'package:pos_babi_guling/services/sync_service.dart';

const String _server = String.fromEnvironment('E2E_SERVER');

void main() {
  setUpAll(() {
    SyncService.periodic = false;
    SharedPreferences.setMockInitialValues({});
    SyncService().debugReset();
  });

  test('offline lalu online ke server sungguhan', () async {
    ApiService.ipAddress = _server;
    final api = ApiService();
    final pos = PosService();

    final login = await api.loginPin('1111');
    expect(login['status'], 'success', reason: '$login');
    final menus = await pos.menus();
    expect(menus, isNotEmpty);
    final MenuModel menu = menus.first;
    final int stockBefore = menu.stock;
    await pos.pendingBills();

    // ---- Sinyal hilang ----
    ApiService.ipAddress = '127.0.0.1:8009';
    expect((await api.loginPin('1111'))['offline'], true);

    CartProvider cart(int qty, String table, {Map<String, dynamic>? appendTo}) {
      final c = CartProvider()..setTaxPercent(10);
      if (appendTo != null) c.startAppend(appendTo);
      for (int i = 0; i < qty; i++) {
        c.addToCart(menu);
      }
      c.setCustomerInfo('', table);
      return c;
    }

    final paid =
        await pos.createOrder(cart(2, '1'), pending: false, amountPaid: 200000);
    expect(paid['queued'], true);
    final String receipt = paid['data']['receipt_number'];

    final bill = await pos.createOrder(cart(1, '2'), pending: true);
    final Map<String, dynamic> localBill = bill['data'];
    await pos.addItemsToBill(localBill, cart(1, '2', appendTo: localBill));
    final bills = await pos.pendingBills();
    final updated =
        bills.items.firstWhere((b) => b['client_uuid'] == localBill['client_uuid']);
    await pos.payBill(updated, method: 'qris');
    await pos.addExpense(amount: 15000, description: 'Uji e2e es batu');
    expect(SyncService().pendingCount, 5);

    // ---- Sinyal kembali ----
    ApiService.ipAddress = _server;
    await SyncService().syncNow();
    expect(SyncService().pendingCount, 0, reason: '${SyncService().ops.map((o) => o.error)}');
    expect(SyncService().failedCount, 0,
        reason: SyncService().failedOps.map((o) => '${o.type}: ${o.error}').join('; '));

    final history = await pos.history();
    expect(history.fresh, true);
    final fromServer = history.items.where((o) => !PosService.isUnsynced(o));
    final order = fromServer.firstWhere((o) => o['receipt_number'] == receipt);
    expect(order['status'], 'paid');
    expect(order['change_amount'], 200000 - toIntTotal(order));
    final paidBill = fromServer
        .firstWhere((o) => o['client_uuid'] == localBill['client_uuid']);
    expect(paidBill['status'], 'paid');
    expect(paidBill['payment_method'], 'qris');
    expect((paidBill['items'] as List).length, 2);

    final expenses = await pos.expenses();
    expect(expenses.items.any((e) => e['description'] == 'Uji e2e es batu'), true);

    // Stok di server berkurang 4 porsi
    final after = (await pos.menus()).firstWhere((m) => m.id == menu.id);
    expect(after.stock, stockBefore - 4);

    // Kirim ulang perintah yang sama tidak membuat data dobel
    final again = await api.send('/orders', {
      'client_uuid': order['client_uuid'],
      'order_type': 'dine_in',
      'items': [
        {'menu_id': menu.id, 'qty': 2}
      ],
    }, token: (await SharedPreferences.getInstance()).getString('token')!);
    expect(again['duplicate'], true);
  }, skip: _server.isEmpty ? 'Isi --dart-define=E2E_SERVER=host:port' : false);
}

int toIntTotal(Map<String, dynamic> o) =>
    int.parse(o['total_price'].toString());
