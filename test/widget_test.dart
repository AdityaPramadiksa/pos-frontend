import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_babi_guling/models/discount_model.dart';
import 'package:pos_babi_guling/models/menu_model.dart';
import 'package:pos_babi_guling/providers/cart_provider.dart';
import 'package:pos_babi_guling/services/printer_service.dart';

MenuModel _menu(int id, String name, int dineIn, int online, {int stock = 99}) {
  return MenuModel(
    id: id,
    categoryId: 1,
    name: name,
    price: dineIn,
    priceDineIn: dineIn,
    priceOnline: online,
    image: '',
    imageUrl: '',
    stock: stock,
    isAvailable: true,
  );
}

/// Ambil teks yang tercetak dari byte ESC/POS (perintah printer dibuang).
List<String> _printedLines(List<int> bytes) {
  final lines = <String>[];
  final buffer = StringBuffer();
  for (int i = 0; i < bytes.length; i++) {
    final int b = bytes[i];
    if (b == 0x1B || b == 0x1D) {
      i += 2; // ESC/GS + perintah + 1 parameter
    } else if (b == 0x1C) {
      i += 1; // FS + perintah
    } else if (b == 0x0A) {
      lines.add(buffer.toString());
      buffer.clear();
    } else if (b >= 0x20 && b <= 0x7E) {
      buffer.writeCharCode(b);
    }
  }
  return lines;
}

final Map<String, dynamic> _report = {
  'settlement': {
    'id': 7,
    'status': 'closed',
    'cashier': 'Kasir A',
    'opened_at': '2026-10-02 08:00:00',
    'closed_at': '2026-10-02 22:00:00',
    'notes': 'aman',
  },
  'summary': {
    'starting_cash': 500000,
    'payments_in_cash': 90200,
    'total_expenses': 20000,
    'expected_ending_cash': 570200,
    'actual_cash': 570000,
    'cash_difference': -200,
    'non_cash_sales': 111828,
    'gross_sales': 185345,
    'total_tax': 18535,
    'total_discount': 1852,
    'net_sales': 202028,
    'total_bills': 6,
    'void_count': 1,
    'void_total': 38500,
    'pending_count': 1,
    'pending_total': 11000,
  },
  'payments': [
    {'payment_method': 'cash', 'label': 'CASH', 'qty': 2, 'total': 90200},
    {'payment_method': 'qris', 'label': 'QRIS', 'qty': 1, 'total': 11728},
    {'payment_method': 'debit', 'label': 'DEBIT', 'qty': 1, 'total': 38500},
    {'payment_method': 'credit', 'label': 'CREDIT', 'qty': 0, 'total': 0},
    {'payment_method': 'gojek', 'label': 'GOJEK / GOFOOD', 'qty': 1, 'total': 46200},
    {'payment_method': 'grab', 'label': 'GRAB / GRABFOOD', 'qty': 0, 'total': 0},
    {'payment_method': 'shopee', 'label': 'SHOPEEFOOD', 'qty': 1, 'total': 15400},
  ],
  'order_types': [
    {'order_type': 'dine_in', 'label': 'DINE IN', 'qty': 2, 'total': 121000},
    {'order_type': 'to_go', 'label': 'TO GO', 'qty': 1, 'total': 11728},
    {'order_type': 'delivery', 'label': 'DELIVERY', 'qty': 3, 'total': 69300},
  ],
  'platforms': [
    {'platform': 'gojek', 'label': 'GOJEK / GOFOOD', 'qty': 1, 'total': 46200},
  ],
  'expenses': [
    {'description': 'Es batu', 'amount': 20000, 'time': '10:00'},
  ],
  'menus_by_category': [
    {
      'category': 'Makanan',
      'qty': 5,
      'total': 159345,
      'items': [
        {'name': 'Porsi Pisah', 'price': 35000, 'qty': 3, 'total': 105000},
        {'name': 'Nasi Campur Spesial', 'price': 12345, 'qty': 1, 'total': 12345},
        {'name': 'Porsi Pisah', 'price': 42000, 'qty': 1, 'total': 42000},
      ],
    },
    {
      'category': 'Minuman',
      'qty': 4,
      'total': 26000,
      'items': [
        {'name': 'Es Teh', 'price': 7000, 'qty': 3, 'total': 21000},
        {'name': 'Es Teh', 'price': 5000, 'qty': 1, 'total': 5000},
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CartProvider', () {
    test('pajak & diskon dibulatkan sama seperti server', () {
      final cart = CartProvider();
      cart.addToCart(_menu(1, 'Nasi Campur', 12345, 15000));
      cart.setDiscount(
          DiscountModel(id: 1, name: 'Promo', type: 'percentage', value: 15));

      expect(cart.subtotalPrice, 12345);
      expect(cart.taxAmount, 1235); // 1234.5 -> 1235
      expect(cart.discountAmount, 1852); // 1851.75 -> 1852
      expect(cart.totalPrice, 11728);
    });

    test('harga online dipakai untuk delivery & tarif pajak mengikuti server',
        () {
      final cart = CartProvider();
      cart.addToCart(_menu(1, 'Porsi Pisah', 35000, 42000));
      cart.setOrderType('delivery', platform: 'GOJEK');
      cart.setTaxPercent(11);

      expect(cart.deliveryPlatform, 'gojek');
      expect(cart.subtotalPrice, 42000);
      expect(cart.taxAmount, 4620);
      expect(cart.taxPercentLabel, '11');
    });

    test('bill gantung memakai total dari server, bukan hitung ulang', () {
      final cart = CartProvider();
      cart.loadBill({
        'id': 9,
        'customer_name': 'Wayan',
        'table_number': '7',
        'order_type': 'dine_in',
        'subtotal': 70000,
        'tax_amount': 7000,
        'discount_amount': 10000,
        'total_price': 67000,
        'items': [
          {'menu_id': 1, 'price': 35000, 'qty': 2, 'note': null, 'menu': {'name': 'Porsi Pisah'}},
        ],
      });

      expect(cart.isBill, true);
      expect(cart.currentOrderId, 9);
      expect(cart.items.single.quantity, 2);
      expect(cart.discountAmount, 10000);
      expect(cart.totalPrice, 67000);

      cart.clearCart();
      expect(cart.isBill, false);
      expect(cart.totalPrice, 0);
    });
  });

  group('Dua printer', () {
    test('ceker ke printer dapur, struk tetap ke printer struk', () async {
      SharedPreferences.setMockInitialValues({'printer_mac': 'AA:AA'});
      final printer = PrinterService();

      // Belum ada printer dapur: ceker ikut printer struk
      expect(await printer.macFor(PrinterRole.kitchen), 'AA:AA');

      await printer.saveMac('BB:BB', role: PrinterRole.kitchen, name: 'Dapur');
      expect(await printer.macFor(PrinterRole.kitchen), 'BB:BB');
      expect(await printer.macFor(PrinterRole.receipt), 'AA:AA');
      expect(await printer.getSavedName(role: PrinterRole.kitchen), 'Dapur');

      await printer.clearKitchenPrinter();
      expect(await printer.macFor(PrinterRole.kitchen), 'AA:AA');
    });
  });

  group('Struk settlement', () {
    test('2 struk: rekap uang per cara bayar & penjualan per menu', () async {
      final parts = await PrinterService().buildShiftReportBytes(_report);
      final money = _printedLines(parts[0]);
      final menus = _printedLines(parts[1]);

      // ignore: avoid_print
      print([...money, '', '######## STRUK 2 ########', '', ...menus].join('\n'));

      for (final line in [...money, ...menus]) {
        expect(line.length, lessThanOrEqualTo(32), reason: line);
      }

      String find(List<String> lines, String prefix) =>
          lines.firstWhere((l) => l.startsWith(prefix), orElse: () => '');

      expect(find(money, 'CASH (2)'), endsWith('90.200'));
      expect(find(money, 'QRIS (1)'), endsWith('11.728'));
      expect(find(money, 'GOJEK / GOFOOD (1)'), endsWith('46.200'));
      expect(find(money, 'GRAB / GRABFOOD (0)'), endsWith(' 0'));
      expect(find(money, 'SHOPEEFOOD (1)'), endsWith('15.400'));
      expect(find(money, 'Seharusnya di Laci'), endsWith('570.200'));
      expect(find(money, 'Selisih'), endsWith('-200'));
      expect(find(money, 'TOTAL (6 bill)'), endsWith('202.028'));

      expect(find(menus, '  3 x 35.000'), endsWith('105.000'));
      expect(find(menus, '  1 x 42.000'), endsWith('42.000'));
      expect(find(menus, 'TOTAL ITEM TERJUAL'), endsWith(' 9'));
      expect(find(menus, 'TOTAL MENU (KOTOR)'), endsWith('185.345'));
      expect(find(menus, 'TOTAL PENJUALAN'), endsWith('202.028'));
    });

    test('struk pelanggan memuat platform & kembalian dari server', () async {
      final bytes = await PrinterService().buildReceiptBytes({
        'receipt_number': 'INV-20261002-0001',
        'user': {'name': 'Kasir A'},
        'order_type': 'delivery',
        'delivery_platform': 'grab',
        'payment_method': 'cash',
        'subtotal': 7000,
        'tax_amount': 700,
        'discount_amount': 0,
        'total_price': 7700,
        'amount_paid': 10000,
        'change_amount': 2300,
        'items': [
          {'qty': 1, 'price': 7000, 'subtotal': 7000, 'note': 'less ice', 'menu': {'name': 'Es Teh'}},
        ],
      });
      final lines = _printedLines(bytes);

      expect(lines, contains('Tipe : DELIVERY - GRAB'));
      expect(lines.any((l) => l.startsWith('TUNAI') && l.endsWith('Rp 10.000')),
          true);
      expect(lines.any((l) => l.startsWith('KEMBALI') && l.endsWith('Rp 2.300')),
          true);
    });
  });
}
