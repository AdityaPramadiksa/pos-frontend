import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/formatters.dart';
import 'app_settings.dart';

/// Printer struk: struk pelanggan, bill, rekap & settlement.
/// Printer dapur: ceker dapur. Kalau belum diatur, ceker ikut ke printer struk.
enum PrinterRole { receipt, kitchen }

class PrinterService {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  static const String defaultMacAddress = "DC:0D:51:8A:7C:DA";
  static const String _macPrefKey = 'printer_mac';
  static const String _namePrefKey = 'printer_name';
  static const String _kitchenMacPrefKey = 'kitchen_printer_mac';
  static const String _kitchenNamePrefKey = 'kitchen_printer_name';

  // Kertas 58mm = 32 karakter per baris (font A)
  static const int _width = 32;
  static const String _dash = "--------------------------------";
  static const String _double = "================================";

  // Plugin Bluetooth hanya bisa memegang SATU koneksi. Untuk 2 printer,
  // koneksi dipindah bergantian, dan semua cetakan diantre supaya tidak bentrok.
  String? _activeMac;
  Future<void>? _queue;

  /// MAC printer yang sedang tersambung (sepengetahuan aplikasi)
  String? get activeMac => _activeMac;

  Future<T> _serialize<T>(Future<T> Function() job) {
    final Future<void>? previous = _queue;
    final Future<T> result =
        previous == null ? job() : previous.then((_) => job());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Kosongkan antrean cetak (antar test, supaya tidak tersangkut)
  @visibleForTesting
  void debugReset() {
    _queue = null;
    _activeMac = null;
  }

  // --- PENGATURAN PRINTER ---
  Future<String> getSavedMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_macPrefKey) ?? defaultMacAddress;
  }

  Future<String?> getSavedName({PrinterRole role = PrinterRole.receipt}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(
        role == PrinterRole.kitchen ? _kitchenNamePrefKey : _namePrefKey);
  }

  /// MAC printer dapur yang diatur khusus (null = pakai printer struk)
  Future<String?> getKitchenMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kitchenMacPrefKey);
  }

  Future<String> macFor(PrinterRole role) async {
    if (role == PrinterRole.kitchen) {
      final String? kitchen = await getKitchenMac();
      if (kitchen != null && kitchen.isNotEmpty) return kitchen;
    }
    return getSavedMac();
  }

  Future<void> saveMac(String mac,
      {PrinterRole role = PrinterRole.receipt, String? name}) async {
    final prefs = await SharedPreferences.getInstance();
    if (role == PrinterRole.kitchen) {
      await prefs.setString(_kitchenMacPrefKey, mac);
      await prefs.setString(_kitchenNamePrefKey, name ?? '');
    } else {
      await prefs.setString(_macPrefKey, mac);
      await prefs.setString(_namePrefKey, name ?? '');
    }
  }

  /// Ceker dapur kembali dicetak di printer struk
  Future<void> clearKitchenPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kitchenMacPrefKey);
    await prefs.remove(_kitchenNamePrefKey);
  }

  Future<bool> _hasSeparateKitchenPrinter() async =>
      await macFor(PrinterRole.kitchen) != await getSavedMac();

  /// Dimatikan di test: plugin Bluetooth berjalan lewat jalur Windows di laptop
  @visibleForTesting
  static bool debugDisabled = false;

  // --- KONEKSI ---
  Future<bool> _connectTo(String mac) async {
    if (kIsWeb || debugDisabled) return false;
    try {
      if (_activeMac == mac && await PrintBluetoothThermal.connectionStatus) {
        return true;
      }
      if (!await PrintBluetoothThermal.bluetoothEnabled) return false;

      // Lepas koneksi lama (printer lain / koneksi nyangkut) sebelum pindah
      await PrintBluetoothThermal.disconnect;
      await Future.delayed(const Duration(milliseconds: 400));

      final bool connected =
          await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      _activeMac = connected ? mac : null;
      return connected;
    } catch (e) {
      debugPrint("Gagal sambung printer $mac: $e");
      _activeMac = null;
      return false;
    }
  }

  /// Pastikan printer untuk peran tsb tersambung (sambung/pindah bila perlu).
  Future<bool> ensureConnected({PrinterRole role = PrinterRole.receipt}) =>
      _serialize(() async => _connectTo(await macFor(role)));

  /// Sambung ke printer tertentu (dari halaman pengaturan printer)
  Future<bool> connectMac(String mac) => _serialize(() => _connectTo(mac));

  Future<void> disconnect() => _serialize(() async {
        try {
          await PrintBluetoothThermal.disconnect;
        } catch (_) {}
        _activeMac = null;
      });

  Future<bool> _sendToPrinter(List<int> bytes,
      {PrinterRole role = PrinterRole.receipt}) {
    return _serialize(() async {
      if (!await _connectTo(await macFor(role))) {
        debugPrint("Printer ${role.name} tidak terhubung.");
        return false;
      }
      return await PrintBluetoothThermal.writeBytes(bytes);
    });
  }

  Future<Generator> _generator() async {
    final profile = await CapabilityProfile.load();
    return Generator(PaperSize.mm58, profile);
  }

  Future<img.Image?> _loadLogo() async {
    try {
      final ByteData data = await rootBundle.load('assets/logobegul.png');
      final Uint8List bytes = data.buffer.asUint8List();
      return img.decodeImage(bytes);
    } catch (e) {
      debugPrint("Gagal load logo: $e");
      return null;
    }
  }

  // --- 1. STRUK PELANGGAN (KASIR) ---
  // isBill    -> tagihan sementara untuk bill yang belum lunas
  // isReprint -> cetak ulang dari riwayat
  Future<bool> printCustomerCopy(Map<String, dynamic> order,
      {int? cashAmount,
      int? changeAmount,
      bool isBill = false,
      bool isReprint = false}) async {
    try {
      final g = await _generator();
      final img.Image? logoImage = await _loadLogo();

      List<int> bytes = _buildReceiptBytes(g, order, logoImage,
          cash: cashAmount,
          change: changeAmount,
          isBill: isBill,
          isReprint: isReprint);
      bytes += g.feed(4);
      bytes += g.cut();
      return await _sendToPrinter(bytes);
    } catch (e) {
      debugPrint("Error print receipt: $e");
      return false;
    }
  }

  // --- 2. STRUK MERCHANT ---
  Future<void> printMerchantCopy(Map<String, dynamic> order) async {
    debugPrint("Merchant copy skip (Request User)");
  }

  // --- 3. CEKER DAPUR ---
  Future<bool> printKitchenOrder(Map<String, dynamic> order) async {
    try {
      final g = await _generator();
      List<int> bytes = _buildKitchenBytes(g, order);
      if (!await _hasSeparateKitchenPrinter()) {
        // Satu printer tanpa auto-cut: beri jarak & garis sobek supaya
        // ceker tidak menyambung dengan struk pelanggan sesudahnya.
        bytes += g.feed(2);
        bytes += g.text("- - - - sobek di sini - - - -",
            styles: const PosStyles(align: PosAlign.center));
        bytes += g.feed(4);
      } else {
        bytes += g.feed(4);
      }
      bytes += g.cut();
      return await _sendToPrinter(bytes, role: PrinterRole.kitchen);
    } catch (e) {
      debugPrint("Error print kitchen order: $e");
      return false;
    }
  }

  // --- BUILDER STRUK TRANSAKSI ---
  List<int> _buildReceiptBytes(
      Generator g, Map<String, dynamic> order, img.Image? logo,
      {int? cash, int? change, bool isBill = false, bool isReprint = false}) {
    List<int> bytes = [];
    if (logo != null) {
      img.Image resizedLogo = img.copyResize(logo, width: 200);
      bytes += g.imageRaster(resizedLogo, align: PosAlign.center);
      bytes += g.feed(1);
    }

    // Identitas warung dari panel admin > Pengaturan
    final shop = AppSettings();
    final List<String> nameLines = _lines(shop.shopName);
    for (int i = 0; i < nameLines.length; i++) {
      // Baris terakhir nama dicetak besar bila muat (maks 16 huruf ukuran ganda)
      final bool big = i == nameLines.length - 1 && nameLines[i].length <= 16;
      bytes += g.text(_safe(nameLines[i]),
          styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: big ? PosTextSize.size2 : PosTextSize.size1,
              width: big ? PosTextSize.size2 : PosTextSize.size1));
    }
    for (final line in _lines(shop.shopAddress)) {
      bytes += g.text(_safe(line),
          styles: const PosStyles(align: PosAlign.center));
    }
    if (shop.shopPhone.trim().isNotEmpty) {
      bytes += g.text(_safe("Telp: ${shop.shopPhone.trim()}"),
          styles: const PosStyles(align: PosAlign.center));
    }
    bytes += g.text(_dash);
    if (isBill) {
      bytes += g.text("TAGIHAN (BELUM LUNAS)",
          styles: const PosStyles(align: PosAlign.center, bold: true));
    }
    if (isReprint) {
      bytes += g.text("** CETAK ULANG **",
          styles: const PosStyles(align: PosAlign.center, bold: true));
    }
    bytes += g.text("Inv  : ${order['receipt_number'] ?? '-'}");
    if (shop.showCashierOnReceipt) {
      bytes += g.text(_safe("Kasir: ${order['user']?['name'] ?? 'Kasir'}"));
    }
    bytes += g.text(
        "Waktu: ${_formatTime(order['paid_at'] ?? order['created_at'])}");
    bytes += g.text(_safe("Tipe : ${_orderTypeLabel(order)}"));
    final String table = order['table_number']?.toString() ?? '';
    if (table.isNotEmpty && table != '-') {
      bytes += g.text(_safe("Meja : $table"));
    }
    final String customer = order['customer_name']?.toString() ?? '';
    if (customer.isNotEmpty && customer != 'Pelanggan Umum') {
      bytes += g.text(_safe("Nama : $customer"));
    }
    bytes += g.text(_dash);

    for (var item in (order['items'] as List? ?? [])) {
      bytes += g.text(_safe("${item['menu']?['name'] ?? 'Menu'}"),
          styles: const PosStyles(bold: true));
      bytes += g.text(_lr(
          "${item['qty']} x ${formatNumber(item['price'])}",
          formatNumber(item['subtotal'])));
      final String itemNote = item['note']?.toString() ?? "";
      if (itemNote.isNotEmpty) {
        bytes += g.text(_safe("  * $itemNote"),
            styles: const PosStyles(fontType: PosFontType.fontB));
      }
    }

    bytes += g.text(_dash);
    bytes += g.text(_lr("SUBTOTAL", formatNumber(order['subtotal'])));

    int tax = toInt(order['tax_amount']);
    if (tax > 0) {
      bytes += g.text(_lr("PAJAK (PB1)", formatNumber(tax)));
    }

    int disc = toInt(order['discount_amount']);
    if (disc > 0) {
      bytes += g.text(_lr("DISKON", "-${formatNumber(disc)}"));
    }

    bytes += g.text(_dash);
    bytes += g.row([
      PosColumn(
          text: "TOTAL",
          width: 5,
          styles: const PosStyles(bold: true, height: PosTextSize.size2)),
      PosColumn(
          text: rupiah(order['total_price']),
          width: 7,
          styles: const PosStyles(
              align: PosAlign.right, bold: true, height: PosTextSize.size2)),
    ]);

    if (!isBill) {
      final String method = (order['payment_method'] ?? '').toString();
      // Nominal tunai & kembalian mengikuti yang tersimpan di server
      cash ??= method == 'cash' ? toInt(order['amount_paid']) : null;
      change ??= method == 'cash' ? toInt(order['change_amount']) : null;

      if (cash != null && cash > 0) {
        bytes += g.feed(1);
        bytes += g.text(_lr("TUNAI", rupiah(cash)));
        bytes += g.text(_lr("KEMBALI", rupiah(change ?? 0)));
      }

      bytes += g.feed(1);
      bytes += g.text(_safe("Metode: ${_paymentLabel(order)}"),
          styles: const PosStyles(align: PosAlign.center));
    }

    // Catatan kaki dari Pengaturan: baris pertama tebal, sisanya huruf kecil
    bytes += g.feed(1);
    final List<String> footer = _lines(shop.receiptFooter);
    for (int i = 0; i < footer.length; i++) {
      bytes += g.text(_safe(footer[i]),
          styles: i == 0
              ? const PosStyles(align: PosAlign.center, bold: true)
              : const PosStyles(
                  align: PosAlign.center, fontType: PosFontType.fontB));
    }

    return bytes;
  }

  List<String> _lines(String text) => text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  // --- BUILDER CEKER DAPUR ---
  List<int> _buildKitchenBytes(Generator g, Map<String, dynamic> order) {
    List<int> bytes = [];
    final String table = order['table_number']?.toString() ?? '';
    final String customer = order['customer_name']?.toString() ?? '';

    bytes += g.text("CEKER DAPUR",
        styles: const PosStyles(
            align: PosAlign.center, bold: true, height: PosTextSize.size2));
    if (order['kitchen_title'] != null) {
      // Mis. "TAMBAHAN": pesanan susulan untuk bill yang sudah ada
      bytes += g.text(_safe("** ${order['kitchen_title']} **"),
          styles: const PosStyles(align: PosAlign.center, bold: true));
    }
    bytes += g.text(_safe("Meja: ${table.isEmpty ? '-' : table}"),
        styles:
            const PosStyles(align: PosAlign.center, height: PosTextSize.size2));
    bytes += g.text(_safe("Tipe: ${_orderTypeLabel(order)}"),
        styles: const PosStyles(align: PosAlign.center));
    if (customer.isNotEmpty && customer != 'Pelanggan Umum') {
      bytes += g.text(_safe("Nama: $customer"),
          styles: const PosStyles(align: PosAlign.center));
    }
    if (order['receipt_number'] != null) {
      bytes += g.text("${order['receipt_number']}",
          styles: const PosStyles(align: PosAlign.center));
    }
    bytes += g.text(_dash);

    for (var item in (order['items'] as List? ?? [])) {
      bytes += g.text(
          _safe("${item['qty']} x ${item['menu']?['name'] ?? 'Menu'}"),
          styles: const PosStyles(height: PosTextSize.size2, bold: true));
      final String itemNote = item['note']?.toString() ?? "";
      if (itemNote.isNotEmpty) {
        bytes += g.text(_safe("  CATATAN: $itemNote"),
            styles: const PosStyles(bold: true));
      }
    }

    bytes += g.text(_dash);
    bytes += g.text(DateFormat('dd/MM/yy HH:mm').format(DateTime.now()),
        styles: const PosStyles(align: PosAlign.center));
    return bytes;
  }

  // --- 4. LAPORAN SHIFT: 2 STRUK ---
  //   Struk 1 = rekap uang per cara bayar (cash, QRIS, Gojek, Grab, ShopeeFood, dll)
  //   Struk 2 = penjualan per menu (qty, harga, total)
  // Dipakai untuk tutup shift, cetak rekap berjalan, dan cetak ulang.
  Future<bool> printShiftReport(Map<String, dynamic> report) async {
    try {
      final g = await _generator();

      List<int> moneyBytes = _buildMoneyReportBytes(g, report);
      moneyBytes += g.feed(4);
      moneyBytes += g.cut();
      if (!await _sendToPrinter(moneyBytes)) return false;

      // Jeda supaya struk pertama bisa disobek dulu
      await Future.delayed(const Duration(seconds: 3));

      List<int> menuBytes = _buildMenuReportBytes(g, report);
      menuBytes += g.feed(4);
      menuBytes += g.cut();
      return await _sendToPrinter(menuBytes);
    } catch (e) {
      debugPrint("Gagal cetak laporan settlement: $e");
      return false;
    }
  }

  // Tetap ada supaya pemanggil lama tidak rusak
  Future<bool> printClosingReport(Map<String, dynamic> report) =>
      printShiftReport(report);

  @visibleForTesting
  Future<List<List<int>>> buildShiftReportBytes(
      Map<String, dynamic> report) async {
    final g = await _generator();
    return [
      _buildMoneyReportBytes(g, report),
      _buildMenuReportBytes(g, report),
    ];
  }

  @visibleForTesting
  Future<List<int>> buildReceiptBytes(Map<String, dynamic> order) async =>
      _buildReceiptBytes(await _generator(), order, null);

  List<int> _buildReportHeader(
      Generator g, Map<String, dynamic> report, String part) {
    List<int> bytes = [];
    final settlement = report['settlement'] ?? {};
    final bool isClosed = settlement['status'] == 'closed';

    bytes += g.text(_double);
    bytes += g.text(isClosed ? "LAPORAN TUTUP SHIFT" : "REKAP SHIFT BERJALAN",
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += g.text(part,
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += g.text(_double);
    bytes += g.text(_safe(_lines(AppSettings().shopName).join(' ')));
    bytes += g.text(_safe("Kasir : ${settlement['cashier'] ?? 'Kasir'}"));
    bytes += g.text("Shift : #${settlement['id'] ?? '-'}");
    bytes += g.text("Buka  : ${_formatTime(settlement['opened_at'])}");
    if (isClosed) {
      bytes += g.text("Tutup : ${_formatTime(settlement['closed_at'])}");
    }
    bytes += g.text("Cetak : ${_formatTime(null)}");
    bytes += g.text(_double);
    return bytes;
  }

  List<int> _buildMoneyReportBytes(Generator g, Map<String, dynamic> report) {
    List<int> bytes = _buildReportHeader(g, report, "1/2 - REKAP UANG");
    const bold = PosStyles(bold: true);

    final settlement = report['settlement'] ?? {};
    final s = report['summary'] ?? {};
    final payments = report['payments'] as List? ?? [];
    final orderTypes = report['order_types'] as List? ?? [];
    final platforms = report['platforms'] as List? ?? [];
    final expenses = report['expenses'] as List? ?? [];

    // --- Uang tunai di laci ---
    bytes += g.text("KAS TUNAI (LACI)", styles: bold);
    bytes += g.text(_lr("Modal Awal", formatNumber(s['starting_cash'])));
    bytes += g.text(_lr("Penjualan Cash", formatNumber(s['payments_in_cash'])));
    bytes +=
        g.text(_lr("Kas Keluar", "-${formatNumber(s['total_expenses'])}"));
    bytes += g.text(_dash);
    bytes += g.text(
        _lr("Seharusnya di Laci", formatNumber(s['expected_ending_cash'])),
        styles: bold);
    if (s['actual_cash'] != null) {
      final int diff = toInt(s['cash_difference']);
      bytes += g.text(_lr("Uang Fisik", formatNumber(s['actual_cash'])));
      bytes += g.text(
          _lr("Selisih", "${diff > 0 ? '+' : ''}${formatNumber(diff)}"));
    }
    bytes += g.text(_double);

    // --- Uang masuk per cara bayar ---
    bytes += g.text("RINCIAN PEMBAYARAN", styles: bold);
    bytes += g.text(_dash);
    for (var p in payments) {
      bytes += g.text(_lr(
          "${p['label']} (${p['qty']})", formatNumber(p['total'])));
    }
    bytes += g.text(_dash);
    bytes += g.text(
        _lr("TOTAL (${s['total_bills'] ?? 0} bill)",
            formatNumber(s['net_sales'])),
        styles: bold);
    bytes +=
        g.text(_lr("  Non Tunai", formatNumber(s['non_cash_sales'])));
    bytes += g.text(_double);

    // --- Penjualan per tipe order ---
    bytes += g.text("TIPE ORDER", styles: bold);
    bytes += g.text(_dash);
    for (var t in orderTypes) {
      bytes += g.text(_lr(
          "${t['label']} (${t['qty']})", formatNumber(t['total'])));
    }
    for (var p in platforms) {
      bytes += g.text(_lr(
          "  - ${p['label']} (${p['qty']})", formatNumber(p['total'])));
    }
    bytes += g.text(_double);

    // --- Ringkasan ---
    bytes += g.text("RINGKASAN PENJUALAN", styles: bold);
    bytes += g.text(_dash);
    bytes += g.text(_lr("Penjualan Kotor", formatNumber(s['gross_sales'])));
    bytes +=
        g.text(_lr("Diskon", "-${formatNumber(s['total_discount'])}"));
    bytes += g.text(_lr("Pajak (PB1)", formatNumber(s['total_tax'])));
    bytes += g.text(_dash);
    bytes += g.text(_lr("TOTAL PENJUALAN", formatNumber(s['net_sales'])),
        styles: bold);
    bytes += g.text(_lr(
        "Void (${s['void_count'] ?? 0})", formatNumber(s['void_total'])));
    bytes += g.text(_lr("Bill Gantung (${s['pending_count'] ?? 0})",
        formatNumber(s['pending_total'])));

    if (expenses.isNotEmpty) {
      bytes += g.text(_double);
      bytes += g.text("RINCIAN KAS KELUAR", styles: bold);
      bytes += g.text(_dash);
      for (var e in expenses) {
        bytes += g.text(_lr(
            "${e['description']}", formatNumber(e['amount'])));
      }
    }

    final String notes = settlement['notes']?.toString() ?? '';
    if (notes.isNotEmpty) {
      bytes += g.text(_double);
      bytes += g.text(_safe("Catatan: $notes"));
    }

    if (settlement['status'] == 'closed') {
      bytes += g.text(_double);
      bytes += g.feed(1);
      bytes += g.text(_lr("Kasir", "Penerima"));
      bytes += g.feed(3);
      bytes += g.text(_lr("(..........)", "(..........)"));
    }

    bytes += g.text("--- akhir rekap uang ---",
        styles: const PosStyles(align: PosAlign.center));
    return bytes;
  }

  List<int> _buildMenuReportBytes(Generator g, Map<String, dynamic> report) {
    List<int> bytes = _buildReportHeader(g, report, "2/2 - PENJUALAN MENU");
    const bold = PosStyles(bold: true);

    final s = report['summary'] ?? {};
    final categories = report['menus_by_category'] as List? ?? [];
    int totalQty = 0;
    int totalSales = 0;

    if (categories.isEmpty) {
      bytes += g.text("Belum ada menu terjual",
          styles: const PosStyles(align: PosAlign.center));
    }

    for (var category in categories) {
      bytes += g.text(_safe("[ ${category['category']} ]".toUpperCase()),
          styles: bold);

      for (var item in (category['items'] as List? ?? [])) {
        bytes += g.text(_safe("${item['name']}"));
        bytes += g.text(_lr(
            "  ${item['qty']} x ${formatNumber(item['price'])}",
            formatNumber(item['total'])));
      }

      bytes += g.text(_dash);
      bytes += g.text(
          _lr("Subtotal (${category['qty']} item)",
              formatNumber(category['total'])),
          styles: bold);
      bytes += g.feed(1);

      totalQty += toInt(category['qty']);
      totalSales += toInt(category['total']);
    }

    bytes += g.text(_double);
    bytes += g.text(_lr("TOTAL ITEM TERJUAL", "$totalQty"), styles: bold);
    bytes += g.text(_lr("TOTAL MENU (KOTOR)", formatNumber(totalSales)),
        styles: bold);
    bytes +=
        g.text(_lr("Diskon", "-${formatNumber(s['total_discount'])}"));
    bytes += g.text(_lr("Pajak (PB1)", formatNumber(s['total_tax'])));
    bytes += g.text(_dash);
    bytes += g.text(_lr("TOTAL PENJUALAN", formatNumber(s['net_sales'])),
        styles: bold);
    bytes += g.text(_double);
    bytes += g.text("--- akhir penjualan menu ---",
        styles: const PosStyles(align: PosAlign.center));
    return bytes;
  }

  // --- 5. TES CETAK ---
  Future<bool> printTest({PrinterRole role = PrinterRole.receipt}) async {
    try {
      final g = await _generator();
      List<int> bytes = [];
      bytes += g.text("TES PRINTER",
          styles: const PosStyles(
              align: PosAlign.center, bold: true, height: PosTextSize.size2));
      bytes += g.text(
          role == PrinterRole.kitchen ? "CEKER DAPUR" : "STRUK / BILL / SETTLEMENT",
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += g.text(_dash);
      bytes += g.text(_lr("Kiri", "Kanan"));
      bytes += g.text(_lr("Rupiah", rupiah(1500000)));
      bytes += g.text(_formatTime(null),
          styles: const PosStyles(align: PosAlign.center));
      bytes += g.text("Printer siap digunakan",
          styles: const PosStyles(align: PosAlign.center));
      bytes += g.feed(3);
      bytes += g.cut();
      return await _sendToPrinter(bytes, role: role);
    } catch (e) {
      debugPrint("Gagal tes cetak: $e");
      return false;
    }
  }

  // --- HELPERS UNTUK MERAPIKAN STRUK ---

  // Printer hanya mengenal karakter latin; emoji/aksara lain bikin cetak gagal
  String _safe(String text) => text.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

  /// Satu baris: teks kiri rata kiri, teks kanan rata kanan (total 32 karakter)
  String _lr(String left, String right) {
    left = _safe(left);
    right = _safe(right);
    final int maxLeft = _width - right.length - 1;
    if (maxLeft < 1) return right;
    if (left.length > maxLeft) left = left.substring(0, maxLeft);
    return left + (' ' * (_width - left.length - right.length)) + right;
  }

  String _formatTime(dynamic value) {
    DateTime time = DateTime.now();
    if (value != null) {
      time = DateTime.tryParse(value.toString())?.toLocal() ?? time;
    }
    return DateFormat('dd/MM/yy HH:mm').format(time);
  }

  String _orderTypeLabel(Map<String, dynamic> order) {
    final String type =
        (order['order_type'] ?? '').toString().replaceAll('_', ' ').toUpperCase();
    final String platform = (order['delivery_platform'] ?? '').toString();
    return platform.isEmpty ? type : "$type - ${platform.toUpperCase()}";
  }

  String _paymentLabel(Map<String, dynamic> order) {
    final String method = (order['payment_method'] ?? 'cash').toString();
    final String platform = (order['delivery_platform'] ?? '').toString();
    if (method == 'delivery' && platform.isNotEmpty) {
      return platformLabel(platform).toUpperCase();
    }
    return method.toUpperCase();
  }
}
