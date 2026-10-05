// Uji tampilan HP & tablet: semua halaman dibuka dengan data contoh.
// Test otomatis gagal jika ada layout yang meluber (RenderFlex overflow).
//
// Untuk menyimpan screenshot tiap halaman (opsional):
//   flutter test test/mobile_layout_test.dart --dart-define=SCREENSHOT_DIR=C:/folder/screenshot
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:pos_babi_guling/main.dart';
import 'package:pos_babi_guling/providers/cart_provider.dart';
import 'package:pos_babi_guling/providers/nav_provider.dart';
import 'package:pos_babi_guling/providers/theme_provider.dart';
import 'package:pos_babi_guling/services/printer_service.dart';
import 'package:pos_babi_guling/views/login_page.dart';
import 'package:pos_babi_guling/views/main_layout.dart';
import 'package:pos_babi_guling/views/printer_settings_page.dart';

const String _screenshotDir = String.fromEnvironment('SCREENSHOT_DIR');

Map<String, dynamic> _menu(int id, int cat, String name, int price,
        {int stock = 50}) =>
    {
      'id': id,
      'category_id': cat,
      'name': name,
      'price': price,
      'price_dine_in': price,
      'price_online': price + 7000,
      'image': '',
      'image_url': '',
      'stock': stock,
      'is_available': true,
    };

Map<String, dynamic> _order(int id, String status, String type,
    {String? platform, String? method = 'cash', int total = 82500}) {
  return {
    'id': id,
    'receipt_number': 'INV-20261005-000$id',
    'customer_name': id == 1 ? 'Pak Wayan Sudirta Kusuma' : 'Pelanggan Umum',
    'table_number': '12',
    'order_type': type,
    'delivery_platform': platform,
    'payment_method': method,
    'subtotal': 75000,
    'tax_amount': 7500,
    'discount_amount': 0,
    'total_price': total,
    'amount_paid': 100000,
    'change_amount': 17500,
    'status': status,
    'void_reason': status == 'void' ? 'Salah input menu' : null,
    'created_at': '2026-10-05T04:15:00.000000Z',
    'user': {'name': 'Kasir A'},
    'items': [
      {
        'menu_id': 1,
        'qty': 2,
        'price': 35000,
        'subtotal': 70000,
        'note': 'Pedas, kulit dipisah',
        'menu': {'name': 'Nasi Babi Guling Spesial Komplit'},
      },
      {
        'menu_id': 5,
        'qty': 1,
        'price': 5000,
        'subtotal': 5000,
        'note': null,
        'menu': {'name': 'Es Teh'},
      },
    ],
  };
}

final Map<String, dynamic> _report = {
  'settlement': {
    'id': 3,
    'status': 'open',
    'cashier': 'Kasir A',
    'opened_at': '2026-10-05 08:00:00',
    'closed_at': null,
    'notes': null,
  },
  'summary': {
    'starting_cash': 500000,
    'payments_in_cash': 1290200,
    'total_expenses': 120000,
    'expected_ending_cash': 1670200,
    'actual_cash': null,
    'cash_difference': null,
    'non_cash_sales': 2111828,
    'gross_sales': 3093345,
    'total_tax': 309335,
    'total_discount': 1852,
    'net_sales': 3402028,
    'total_bills': 64,
    'void_count': 1,
    'void_total': 38500,
    'pending_count': 2,
    'pending_total': 121000,
  },
  'payments': [
    for (final p in [
      ['cash', 'CASH', 30, 1290200],
      ['qris', 'QRIS', 12, 611728],
      ['debit', 'DEBIT', 5, 338500],
      ['credit', 'CREDIT', 0, 0],
      ['gojek', 'GOJEK / GOFOOD', 9, 646200],
      ['grab', 'GRAB / GRABFOOD', 4, 300000],
      ['shopee', 'SHOPEEFOOD', 4, 215400],
    ])
      {'payment_method': p[0], 'label': p[1], 'qty': p[2], 'total': p[3]},
  ],
  'order_types': [
    {'order_type': 'dine_in', 'label': 'DINE IN', 'qty': 40, 'total': 2121000},
    {'order_type': 'to_go', 'label': 'TO GO', 'qty': 7, 'total': 119428},
    {'order_type': 'delivery', 'label': 'DELIVERY', 'qty': 17, 'total': 1161600},
  ],
  'platforms': [],
  'expenses': [],
  'menus_by_category': [
    {
      'category': 'Makanan',
      'qty': 60,
      'total': 2400000,
      'items': [
        {'name': 'Nasi Babi Guling Spesial Komplit', 'price': 35000, 'qty': 40, 'total': 1400000},
        {'name': 'Porsi Pisah', 'price': 42000, 'qty': 20, 'total': 840000},
      ],
    },
    {
      'category': 'Minuman',
      'qty': 30,
      'total': 150000,
      'items': [
        {'name': 'Es Teh', 'price': 5000, 'qty': 30, 'total': 150000},
      ],
    },
  ],
};

Object _apiResponse(String method, String path) {
  if (method == 'POST' && RegExp(r'^/api/menus/\d+/stock$').hasMatch(path)) {
    return {
      'status': 'success',
      'message': 'Stok diperbarui',
      'data': _menu(2, 1, 'Porsi Pisah', 35000, stock: 0),
    };
  }
  if (method == 'POST' && RegExp(r'^/api/orders/\d+/items$').hasMatch(path)) {
    final order = _order(7, 'pending', 'dine_in', method: null, total: 121000);
    return {
      'status': 'success',
      'data': {...order, 'new_items': order['items']},
    };
  }
  switch (path) {
    case '/api/settlement/status':
      return {'status': 'success', 'data': {'starting_cash': 500000}};
    case '/api/settings':
      return {
        'status': 'success',
        'data': {
          'tax_rate': 10,
          'low_stock_threshold': 10,
          'receipt': {
            'shop_name': 'WARUNG BABI GULING\nMEN GEDE',
            'shop_address': 'Jl. Poppies I, Kuta',
            'shop_phone': '0822-3660-6374',
            'footer': 'Matur Suksma!',
            'show_cashier': true,
          },
        },
      };
    case '/api/categories':
      return {
        'status': 'success',
        'data': [
          {'id': 1, 'name': 'Makanan'},
          {'id': 2, 'name': 'Minuman'},
          {'id': 3, 'name': 'Paket Hemat Keluarga'},
        ],
      };
    case '/api/menus':
      return {
        'status': 'success',
        'data': [
          _menu(1, 1, 'Nasi Babi Guling Spesial Komplit', 35000),
          _menu(2, 1, 'Porsi Pisah', 35000),
          _menu(3, 1, 'Sate Babi', 25000, stock: 0),
          _menu(4, 3, 'Paket Keluarga Besar Isi 5 Orang', 250000, stock: 4),
          _menu(5, 2, 'Es Teh', 5000),
          _menu(6, 2, 'Kopi Bali', 8000),
        ],
      };
    case '/api/discounts':
      return {'status': 'success', 'data': []};
    case '/api/orders/history':
      return {
        'status': 'success',
        'data': [
          _order(1, 'paid', 'dine_in'),
          _order(2, 'paid', 'delivery',
              platform: 'gojek', method: 'delivery', total: 1250000),
          _order(3, 'void', 'to_go', method: 'qris'),
        ],
      };
    case '/api/orders/pending':
      return {
        'status': 'success',
        'data': [
          _order(7, 'pending', 'dine_in', method: null),
          _order(8, 'pending', 'dine_in', method: null, total: 1121000),
        ],
      };
    case '/api/orders/recapitulation':
      return {'status': 'success', 'data': _report};
    case '/api/expenses':
      return {
        'status': 'success',
        'data': [
          {
            'description': 'Beli es batu & gas elpiji 3kg',
            'amount': 120000,
            'created_at': '2026-10-05T03:00:00.000000Z',
          },
        ],
      };
  }
  return {'status': 'error', 'message': 'Tidak dikenal: $path'};
}

final MockClient _mockApi = MockClient((request) async => http.Response(
    jsonEncode(_apiResponse(request.method, request.url.path)), 200,
    headers: {'content-type': 'application/json'}));

Future<void> _loadFonts() async {
  ByteData read(String path) =>
      ByteData.sublistView(File(path).readAsBytesSync());

  // Font aplikasi (ikut dibundel di assets/fonts)
  final loader = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(Future.value(read('assets/fonts/PlusJakartaSans-$w.ttf')));
  }
  await loader.load();

  final String material =
      '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter'}/bin/cache/artifacts/material_fonts';
  if (Directory(material).existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(read('$material/materialicons-regular.otf'))))
        .load();
  }
}

void _mockPlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel('groons.web.app/print'), (call) async {
    switch (call.method) {
      case 'pairedbluetooths':
        return ['RPP02N#DC:0D:51:8A:7C:DA', 'Speaker JBL#00:11:22:33:44:55'];
      case 'connectionstatus':
      case 'bluetoothenabled':
        return false;
    }
    return false;
  });
  messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => <int, int>{});
  // Dipakai plugin printer saat membaca daftar perangkat ter-pairing
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path);
}

Widget _app(Widget home) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => CartProvider()),
      ChangeNotifierProvider(create: (_) => NavProvider()),
    ],
    child: Consumer<ThemeProvider>(
      builder: (context, theme, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(theme),
        home: home,
      ),
    ),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (_screenshotDir.isEmpty) return;
  await expectLater(find.byType(MaterialApp).first,
      matchesGoldenFile(Uri.file('$_screenshotDir/$name.png')));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
}

/// Tunggu snackbar hilang supaya tidak menutupi tombol berikutnya
Future<void> _waitSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await _settle(tester);
}

void _setSize(WidgetTester tester, Size logicalSize) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = logicalSize * 2;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    autoUpdateGoldenFiles = _screenshotDir.isNotEmpty;
    await _loadFonts();
    await initializeDateFormatting('id');
    PrinterService.debugDisabled = true;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'token': 'uji', 'user_name': 'Kasir A', 'role': 'cashier'});
    _mockPlugins();
  });

  testWidgets('HP: semua halaman rapi & alur kasir jalan', (tester) async {
    _setSize(tester, const Size(360, 760));

    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const MainLayout()));
      await _settle(tester);

      // Navigasi bawah (bukan rail) di HP
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Lainnya'), findsOneWidget);
      // Menu tanpa foto memakai ikon sendok-garpu
      expect(find.byIcon(Icons.restaurant_menu), findsWidgets);
      await _shot(tester, '01_kasir');

      // Stok habis tidak bisa ditambah
      await tester.tap(find.text('Sate Babi'));
      await _settle(tester);
      expect(find.textContaining('Sate Babi habis'), findsOneWidget);
      await _waitSnack(tester);

      // Ubah stok dari kasir: tekan lama kartu menu
      await tester.longPress(find.text('Porsi Pisah'));
      await _settle(tester);
      expect(find.text('Stok Porsi Pisah'), findsOneWidget);
      expect(find.text('Tandai habis'), findsOneWidget);
      await _shot(tester, '01b_ubah_stok');
      await tester.tap(find.text('Tandai habis'));
      await _settle(tester);
      expect(find.text('Stok Porsi Pisah'), findsNothing);
      await _waitSnack(tester);

      await tester.tap(find.text('Nasi Babi Guling Spesial Komplit'));
      await tester.tap(find.text('Nasi Babi Guling Spesial Komplit'));
      await tester.scrollUntilVisible(find.text('Es Teh'), 150,
          scrollable: find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first);
      await tester.tap(find.text('Es Teh'));
      await _settle(tester);
      expect(find.text('Lihat pesanan'), findsOneWidget);
      await _shot(tester, '02_kasir_isi_keranjang');

      // Lembar pesanan
      await tester.tap(find.text('Lihat pesanan'));
      await _settle(tester);
      expect(find.text('Makan di sini'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Meja'), '12');
      await _settle(tester);
      await _shot(tester, '03_lembar_pesanan');

      // Ke halaman pembayaran
      await tester.tap(find.text('Bayar'));
      await _settle(tester);
      expect(find.text('Pembayaran'), findsOneWidget);
      await _shot(tester, '04_pembayaran');
      await tester.scrollUntilVisible(find.text('Kembalian'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Uang pas'));
      await _settle(tester);
      await _shot(tester, '05_pembayaran_bawah');
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await _settle(tester);

      // Bill: detail lalu tambah pesanan ke bill
      await tester.tap(find.text('Bill'));
      await _settle(tester);
      await _shot(tester, '06_bills');
      await tester.tap(find.text('Pelanggan umum').first);
      await _settle(tester);
      expect(find.text('Bayar bill'), findsOneWidget);
      await _shot(tester, '07_bills_detail');
      await tester.tap(find.text('Tambah pesanan'));
      await _settle(tester);
      expect(find.text('Ke bill Meja 12'), findsOneWidget);
      await tester.tap(find.text('Nasi Babi Guling Spesial Komplit'));
      await _settle(tester);
      await tester.tap(find.text('Lihat pesanan'));
      await _settle(tester);
      expect(find.text('Tambahkan ke bill'), findsOneWidget);
      await _shot(tester, '07b_tambah_ke_bill');
      await tester.tap(find.text('Tambahkan ke bill'));
      await _settle(tester);
      // Selesai: kembali ke daftar bill dan keranjang kosong
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await _settle(tester);
      expect(find.text('Bill belum dibayar'), findsOneWidget);
      await _waitSnack(tester);

      // Riwayat: kartu, bukan tabel
      await tester.tap(find.text('Riwayat'));
      await _settle(tester);
      await _shot(tester, '08_riwayat');
      await tester.tap(find.text('INV-20261005-0001'));
      await _settle(tester);
      expect(find.text('Cetak ulang struk'), findsOneWidget);
      await _shot(tester, '09_riwayat_detail');
      await tester.tap(find.byIcon(Icons.close).last);
      await _settle(tester);

      // Rekap & dialog tutup shift
      await tester.tap(find.text('Rekap'));
      await _settle(tester);
      expect(find.text('Uang tunai'), findsOneWidget);
      await _shot(tester, '10_rekap');
      await tester.tap(find.byIcon(Icons.receipt_long_outlined).first);
      await _settle(tester);
      expect(find.text('Cetak rekap shift ini'), findsOneWidget);
      expect(find.text('Cetak ulang settlement terakhir'), findsOneWidget);
      await _shot(tester, '10b_rekap_menu_cetak');
      await tester.tapAt(const Offset(5, 400));
      await _settle(tester);
      await tester.scrollUntilVisible(find.text('Penjualan per menu'), 300,
          scrollable: find.byType(Scrollable).first);
      await _settle(tester);
      await _shot(tester, '11_rekap_menu');
      await tester.tap(find.text('Tutup shift').first);
      await _settle(tester);
      expect(find.text('Tutup shift?'), findsOneWidget);
      await _shot(tester, '12_tutup_shift');
      await tester.tap(find.text('Batal'));
      await _settle(tester);

      // Menu Lainnya -> Kas keluar & Printer
      await tester.tap(find.text('Lainnya'));
      await _settle(tester);
      await _shot(tester, '13_lainnya');
      await tester.tap(find.text('Kas keluar').last);
      await _settle(tester);
      expect(find.text('Pengeluaran shift ini'), findsOneWidget);
      await _shot(tester, '14_kas_keluar');

      await tester.tap(find.text('Lainnya'));
      await _settle(tester);
      await tester.tap(find.text('Printer').last);
      await _settle(tester);
      expect(find.text('Printer Struk'), findsOneWidget);
      expect(find.text('Printer Ceker Dapur'), findsOneWidget);
      expect(find.text('Buka pengaturan Bluetooth'), findsOneWidget);
      await _shot(tester, '15_printer');
    }, () => _mockApi);
  });

  testWidgets('HP: halaman printer dengan printer dapur terpisah',
      (tester) async {
    _setSize(tester, const Size(360, 760));
    SharedPreferences.setMockInitialValues({
      'token': 'uji',
      'printer_mac': 'DC:0D:51:8A:7C:DA',
      'printer_name': 'RPP02N Kasir',
      'kitchen_printer_mac': '00:11:22:33:44:55',
      'kitchen_printer_name': 'Printer Dapur',
    });

    await tester.pumpWidget(_app(const PrinterSettingsPage()));
    await _settle(tester);

    expect(find.text('Tes cetak'), findsNWidgets(2));
    expect(find.text('Pakai printer struk'), findsOneWidget);
    expect(find.textContaining('Printer Dapur'), findsOneWidget);
    await _shot(tester, '16_printer_dua');
  });

  testWidgets('HP: halaman login', (tester) async {
    _setSize(tester, const Size(360, 760));
    await tester.pumpWidget(_app(const LoginPage()));
    await _settle(tester);
    expect(find.text('Masukkan PIN 4 angka'), findsOneWidget);
    await _shot(tester, '00_login');
  });

  testWidgets('Tablet: layout lebar tetap pakai rail & tidak meluber',
      (tester) async {
    _setSize(tester, const Size(1280, 800));

    await http.runWithClient(() async {
      await tester.pumpWidget(_app(const MainLayout()));
      await _settle(tester);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.text('Nasi Babi Guling Spesial Komplit'));
      await tester.tap(find.text('Es Teh'));
      await _settle(tester);
      await _shot(tester, '20_tablet_kasir');

      for (final page in ['Bill', 'Riwayat', 'Kas keluar', 'Printer', 'Rekap']) {
        await tester.tap(find.text(page).first);
        await _settle(tester);
        await _shot(tester, '2x_tablet_${page.replaceAll(' ', '_').toLowerCase()}');
      }
    }, () => _mockApi);
  });
}
