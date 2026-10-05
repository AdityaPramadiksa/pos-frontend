import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/category_model.dart';
import '../models/discount_model.dart';
import '../models/menu_model.dart';
import '../providers/cart_provider.dart';
import '../utils/formatters.dart';
import 'api_service.dart';
import 'app_settings.dart';
import 'local_store.dart';
import 'sync_service.dart';

/// Hasil daftar untuk halaman, beserta keterangan apakah data dari server
class PosList {
  final List<Map<String, dynamic>> items;
  final bool fresh;
  final DateTime? savedAt;
  const PosList(this.items, {required this.fresh, this.savedAt});
}

/// Semua transaksi kasir lewat sini. Transaksi disimpan di perangkat dulu,
/// lalu dikirim ke server (langsung bila online, otomatis nanti bila offline).
/// Daftar yang ditampilkan = data server (atau salinannya) + transaksi
/// yang belum terkirim.
class PosService {
  final ApiService _api = ApiService();
  final SyncService _sync = SyncService();

  static const String _billsKey = 'local_bills';

  /// Kunci bill: client_uuid (dibuat aplikasi) atau id server (bill lama)
  static String billKey(Map<String, dynamic> bill) =>
      (bill['client_uuid']?.toString().isNotEmpty ?? false)
          ? bill['client_uuid'].toString()
          : bill['id'].toString();

  /// true bila transaksi ini belum sampai di server
  static bool isUnsynced(Map<String, dynamic> data) => data['_unsynced'] == true;

  Future<({int? id, String name, String token})> _session() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      id: prefs.getInt('user_id'),
      name: prefs.getString('user_name') ?? 'Kasir',
      token: prefs.getString('token') ?? '',
    );
  }

  static String _utcNow(DateTime at) => at.toUtc().toIso8601String();

  // ============================ BACA DATA ============================

  Future<List<CategoryModel>> categories() => _api.getCategories();

  Future<List<DiscountModel>> discounts() => _api.getDiscounts();

  /// Menu dengan stok yang sudah dikurangi pesanan yang belum terkirim
  Future<List<MenuModel>> menus() async {
    await _sync.load();
    final res = await _api.getMenusRaw();
    final Map<int, Map<String, dynamic>> byId = {
      for (final m in res.data)
        toInt(m['id']): Map<String, dynamic>.from(m as Map),
    };

    for (final op in _sync.pendingOps) {
      if (op.type == 'stock') {
        final menu = byId[toInt(op.body['menu_id'])];
        if (menu != null) menu['stock'] = toInt(op.body['stock']);
      } else if (op.type == 'order' || op.type == 'add_items') {
        for (final item in (op.body['items'] as List? ?? [])) {
          final menu = byId[toInt(item['menu_id'])];
          if (menu == null) continue;
          final int left = toInt(menu['stock']) - toInt(item['qty']);
          menu['stock'] = left < 0 ? 0 : left;
        }
      }
    }
    return byId.values.map(MenuModel.fromJson).toList();
  }

  /// Bill belum dibayar: dari server, ditambah perubahan yang belum terkirim
  Future<PosList> pendingBills() async {
    await _sync.load();
    final res = await _api.getPendingBills();
    final List<Map<String, dynamic>> local = await _localBills();
    final Set<String> touched = _sync.touchedBillKeys;

    if (!res.fresh) {
      return PosList(local, fresh: false, savedAt: res.savedAt);
    }

    final merged = <Map<String, dynamic>>[
      // Bill dari server yang tidak sedang diubah di perangkat ini
      for (final b in res.data)
        if (!touched.contains(billKey(Map<String, dynamic>.from(b))))
          Map<String, dynamic>.from(b),
      // Bill yang masih punya perubahan lokal: pakai versi perangkat
      for (final b in local)
        if (touched.contains(billKey(b))) b,
    ];
    merged.sort((a, b) => _time(b).compareTo(_time(a)));
    await _saveLocalBills(merged);
    return PosList(merged, fresh: true, savedAt: DateTime.now());
  }

  /// Riwayat hari ini: server (atau salinannya) + transaksi belum terkirim
  Future<PosList> history() async {
    await _sync.load();
    final res = await _api.getOrderHistory();
    final Map<String, Map<String, dynamic>> byKey = {
      for (final o in res.data)
        billKey(Map<String, dynamic>.from(o)): Map<String, dynamic>.from(o),
    };
    for (final op in _sync.ops) {
      if ((op.type == 'order' || op.type == 'pay' || op.type == 'add_items') &&
          op.snapshot != null) {
        final snap = Map<String, dynamic>.from(op.snapshot!)
          ..remove('new_items');
        snap['_unsynced'] = true;
        snap['_failed'] = op.isFailed;
        byKey[billKey(snap)] = snap;
      }
    }
    final list = byKey.values.toList()
      ..sort((a, b) => _time(b).compareTo(_time(a)));
    return PosList(list, fresh: res.fresh, savedAt: res.savedAt);
  }

  /// Kas keluar shift berjalan + yang belum terkirim
  Future<PosList> expenses() async {
    await _sync.load();
    final res = await _api.getExpenses();
    final list = <Map<String, dynamic>>[
      for (final op in _sync.ops)
        if (op.type == 'expense' && op.snapshot != null)
          {...op.snapshot!, '_unsynced': true, '_failed': op.isFailed},
      for (final e in res.data) Map<String, dynamic>.from(e),
    ];
    return PosList(list, fresh: res.fresh, savedAt: res.savedAt);
  }

  static DateTime _time(Map<String, dynamic> o) =>
      DateTime.tryParse(o['created_at']?.toString() ?? '')?.toLocal() ??
      DateTime(2000);

  Future<List<Map<String, dynamic>>> _localBills() async {
    final saved = await LocalStore.readJson(_billsKey);
    return saved is List
        ? saved.map((b) => Map<String, dynamic>.from(b)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<void> _saveLocalBills(List<Map<String, dynamic>> bills) =>
      LocalStore.writeJson(_billsKey, bills);

  Future<void> _putLocalBill(Map<String, dynamic> bill) async {
    final bills = await _localBills();
    final String key = billKey(bill);
    bills.removeWhere((b) => billKey(b) == key);
    bills.insert(0, Map<String, dynamic>.from(bill)..remove('new_items'));
    await _saveLocalBills(bills);
  }

  Future<void> _removeLocalBill(String key) async {
    final bills = await _localBills();
    bills.removeWhere((b) => billKey(b) == key);
    await _saveLocalBills(bills);
  }

  // ============================ TRANSAKSI ============================

  Map<String, dynamic> _itemSnapshot(CartProvider cart, CartItem item) {
    final int price = cart.priceOf(item.menu);
    return {
      'menu_id': item.menu.id,
      'qty': item.quantity,
      'price': price,
      'subtotal': price * item.quantity,
      'note': item.note,
      'menu': {
        'id': item.menu.id,
        'name': item.menu.name,
        'image_url': item.menu.imageUrl,
      },
    };
  }

  /// Pesanan baru dari keranjang. [pending] = simpan sebagai bill (belum bayar).
  Future<Map<String, dynamic>> createOrder(
    CartProvider cart, {
    required bool pending,
    int? amountPaid,
  }) async {
    if (cart.items.isEmpty) {
      return {'status': 'error', 'message': 'Keranjang masih kosong.'};
    }
    final session = await _session();
    final DateTime now = DateTime.now();
    final String uuid = LocalStore.newUuid();
    final String receipt = await LocalStore.nextReceiptNumber(now);
    final String orderType = cart.orderType;
    final bool isDelivery = orderType == 'delivery';
    final String? method = pending ? null : cart.paymentMethod.toLowerCase();

    final int total = cart.totalPrice;
    int paid = 0;
    int change = 0;
    if (!pending) {
      if (method == 'cash') {
        paid = amountPaid ?? total;
        change = paid > total ? paid - total : 0;
      } else {
        paid = total;
      }
    }

    final items = [for (final i in cart.items) _itemSnapshot(cart, i)];
    final snapshot = <String, dynamic>{
      'id': null,
      'client_uuid': uuid,
      'receipt_number': receipt,
      'user_id': session.id,
      'user': {'id': session.id, 'name': session.name},
      'customer_name': cart.customerName,
      'table_number': cart.tableNumber,
      'order_type': orderType,
      'delivery_platform': isDelivery ? cart.deliveryPlatform : null,
      'subtotal': cart.subtotalPrice,
      'tax_amount': cart.taxAmount,
      'discount_amount': cart.discountAmount,
      'total_price': total,
      'payment_method': method,
      'amount_paid': paid,
      'change_amount': change,
      'status': pending ? 'pending' : 'paid',
      'created_at': now.toIso8601String(),
      'paid_at': pending ? null : now.toIso8601String(),
      'items': items,
    };

    final body = <String, dynamic>{
      'client_uuid': uuid,
      'receipt_number': receipt,
      'created_at': _utcNow(now),
      'order_type': orderType,
      if (isDelivery) 'delivery_platform': cart.deliveryPlatform,
      if (method != null) 'payment_method': method,
      'is_pending': pending,
      'customer_name': cart.customerName,
      'table_number': cart.tableNumber,
      if (method == 'cash') 'amount_paid': paid,
      'discount_id': cart.selectedDiscount?.id,
      'discount_amount': cart.discountAmount,
      'tax_amount': cart.taxAmount,
      'items': [
        for (final i in items)
          {
            'menu_id': i['menu_id'],
            'qty': i['qty'],
            'note': i['note'],
            'price': i['price'],
          }
      ],
    };

    final res = await _sync.submit(SyncOp(
      id: LocalStore.newUuid(),
      type: 'order',
      path: '/orders',
      body: body,
      label: pending ? 'Bill ${_billLabel(snapshot)}' : 'Pesanan $receipt',
      createdAt: now,
      token: session.token,
      userId: session.id,
      userName: session.name,
      snapshot: snapshot,
      billKey: pending ? uuid : null,
    ));

    if (res['status'] == 'success' && res['queued'] == true) {
      res['data'] = {...snapshot, '_unsynced': true};
    }
    if (res['status'] == 'success' && pending && res['data'] is Map) {
      await _putLocalBill(Map<String, dynamic>.from(res['data']));
    }
    return res;
  }

  /// Lunasi bill (dari server atau yang dibuat offline)
  Future<Map<String, dynamic>> payBill(
    Map<String, dynamic> bill, {
    required String method,
    int? amountPaid,
  }) async {
    final session = await _session();
    final DateTime now = DateTime.now();
    final String key = billKey(bill);
    method = method.toLowerCase();
    final int total = toInt(bill['total_price']);
    final int paid = method == 'cash' ? (amountPaid ?? total) : total;

    final snapshot = <String, dynamic>{
      ...bill,
      'status': 'paid',
      'payment_method': method,
      'amount_paid': paid,
      'change_amount': paid > total ? paid - total : 0,
      'paid_at': now.toIso8601String(),
    }..remove('_unsynced');

    final opId = LocalStore.newUuid();
    final res = await _sync.submit(SyncOp(
      id: opId,
      type: 'pay',
      path: '/orders/$key/pay',
      body: {
        'payment_method': method,
        if (method == 'cash') 'amount_paid': paid,
        'op_uuid': opId,
        'paid_at': _utcNow(now),
      },
      label: 'Pelunasan ${_billLabel(bill)}',
      createdAt: now,
      token: session.token,
      userId: session.id,
      userName: session.name,
      snapshot: snapshot,
      billKey: key,
    ));

    if (res['status'] == 'success') {
      if (res['queued'] == true) res['data'] = {...snapshot, '_unsynced': true};
      await _removeLocalBill(key);
    }
    return res;
  }

  /// Tambah item keranjang ke bill yang belum dibayar.
  /// Hasil 'data' = bill terbaru + 'new_items' untuk ceker dapur.
  Future<Map<String, dynamic>> addItemsToBill(
      Map<String, dynamic> bill, CartProvider cart) async {
    if (cart.items.isEmpty) {
      return {'status': 'error', 'message': 'Pilih menu tambahan dulu.'};
    }
    final session = await _session();
    final DateTime now = DateTime.now();
    final String key = billKey(bill);
    final newItems = [for (final i in cart.items) _itemSnapshot(cart, i)];

    final allItems = [...(bill['items'] as List? ?? []), ...newItems];
    final int subtotal =
        allItems.fold(0, (sum, i) => sum + toInt((i as Map)['subtotal']));
    final int tax = (subtotal * (AppSettings().taxPercent / 100)).round();
    final int oldDiscount = toInt(bill['discount_amount']);
    final int discount = oldDiscount > subtotal ? subtotal : oldDiscount;
    final int total = subtotal + tax - discount;

    final snapshot = <String, dynamic>{
      ...bill,
      'items': allItems,
      'subtotal': subtotal,
      'tax_amount': tax,
      'discount_amount': discount,
      'total_price': total < 0 ? 0 : total,
      'new_items': newItems,
    }..remove('_unsynced');

    final res = await _sync.submit(SyncOp(
      id: LocalStore.newUuid(),
      type: 'add_items',
      path: '/orders/$key/items',
      body: {
        'batch_uuid': LocalStore.newUuid(),
        'items': [
          for (final i in newItems)
            {
              'menu_id': i['menu_id'],
              'qty': i['qty'],
              'note': i['note'],
              'price': i['price'],
            }
        ],
      },
      label: 'Tambahan ${_billLabel(bill)}',
      createdAt: now,
      token: session.token,
      userId: session.id,
      userName: session.name,
      snapshot: snapshot,
      billKey: key,
    ));

    if (res['status'] == 'success') {
      if (res['queued'] == true) res['data'] = {...snapshot, '_unsynced': true};
      if (res['data'] is Map) {
        await _putLocalBill(Map<String, dynamic>.from(res['data']));
      }
    }
    return res;
  }

  /// Catat kas keluar (foto nota ikut dikirim bila masih ada di perangkat)
  Future<Map<String, dynamic>> addExpense({
    required int amount,
    required String description,
    XFile? photo,
  }) async {
    final session = await _session();
    final DateTime now = DateTime.now();
    final String uuid = LocalStore.newUuid();
    return _sync.submit(SyncOp(
      id: LocalStore.newUuid(),
      type: 'expense',
      path: '/expenses',
      body: {
        'amount': amount,
        'description': description,
        'client_uuid': uuid,
        'created_at': _utcNow(now),
      },
      label: 'Kas keluar ${rupiah(amount)}',
      createdAt: now,
      token: session.token,
      userId: session.id,
      userName: session.name,
      filePath: photo?.path,
      snapshot: {
        'client_uuid': uuid,
        'amount': amount,
        'description': description,
        'created_at': now.toIso8601String(),
        'user': {'name': session.name},
        'receipt_image': null,
      },
    ));
  }

  /// Ubah sisa stok (0 = habis)
  Future<Map<String, dynamic>> updateStock(MenuModel menu, int stock) async {
    final session = await _session();
    final res = await _sync.submit(SyncOp(
      id: LocalStore.newUuid(),
      type: 'stock',
      path: '/menus/${menu.id}/stock',
      body: {'menu_id': menu.id, 'stock': stock},
      label: stock > 0 ? 'Stok ${menu.name} → $stock' : '${menu.name} habis',
      createdAt: DateTime.now(),
      token: session.token,
      userId: session.id,
      userName: session.name,
    ));
    if (res['queued'] == true) {
      res['message'] = stock > 0
          ? 'Stok ${menu.name} jadi $stock porsi (dikirim saat online)'
          : '${menu.name} ditandai habis (dikirim saat online)';
    }
    return res;
  }

  /// Tutup shift: semua transaksi kasir ini harus sudah sampai di server
  /// supaya rekap & uang tunai yang dihitung benar.
  Future<Map<String, dynamic>> closeShift(String notes, {int? actualCash}) async {
    final session = await _session();
    await _sync.syncNow();
    if (_sync.hasUnsentFor(session.id)) {
      final int count =
          _sync.pendingOps.where((o) => o.userId == session.id).length;
      return {
        'status': 'error',
        'message':
            'Masih ada $count transaksi yang belum terkirim ke server. Sambungkan internet dan tunggu sampai terkirim, lalu tutup shift.',
      };
    }
    return _api.closeSettlement(notes, actualCash: actualCash);
  }

  static String _billLabel(Map<String, dynamic> bill) {
    final String table = bill['table_number']?.toString() ?? '';
    if (table.isNotEmpty && table != '-') return 'meja $table';
    final String name = bill['customer_name']?.toString() ?? '';
    if (name.isNotEmpty && name != 'Pelanggan Umum') return name;
    return bill['receipt_number']?.toString() ?? '';
  }
}
