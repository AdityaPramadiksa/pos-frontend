import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../providers/cart_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/pos_service.dart';
import '../services/sync_service.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/ui.dart';
import 'login_page.dart';

class SalesRecapPage extends StatefulWidget {
  const SalesRecapPage({super.key});

  @override
  State<SalesRecapPage> createState() => _SalesRecapPageState();
}

class _SalesRecapPageState extends State<SalesRecapPage> {
  final ApiService _apiService = ApiService();
  final PrinterService _printer = PrinterService();
  Map<String, dynamic>? _recapData;
  bool _isLoading = true;
  bool _isPrinting = false;

  /// Rekap dari salinan terakhir di perangkat (server tidak terjangkau)
  DateTime? _cachedAt;
  int _syncedTick = 0;

  @override
  void initState() {
    super.initState();
    _syncedTick = SyncService().syncedTick;
    SyncService().addListener(_onSync);
    _fetchRecap();
  }

  @override
  void dispose() {
    SyncService().removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (mounted) setState(() {}); // jumlah transaksi belum terkirim berubah
    if (SyncService().syncedTick == _syncedTick) return;
    _syncedTick = SyncService().syncedTick;
    _fetchRecap();
  }

  Future<void> _fetchRecap() async {
    if (!mounted) return;
    setState(() => _isLoading = _recapData == null);
    final res = await _apiService.getSalesRecapitulation();
    if (!mounted) return;
    setState(() {
      if (res['status'] == 'success') {
        _recapData = res['data'];
        _cachedAt = res['cached'] == true
            ? DateTime.tryParse(res['saved_at']?.toString() ?? '')
            : null;
      }
      _isLoading = false;
    });
    if (res['status'] != 'success') {
      _showSnackBar(res['message'] ?? "Rekap gagal dimuat.", error: true);
    }
  }

  /// Keterangan bila rekap belum mencakup semua transaksi
  String? _staleNote() {
    final int unsent = SyncService().pendingCount;
    if (_cachedAt != null) {
      return "Offline: rekap terakhir pukul ${DateFormat('HH:mm').format(_cachedAt!.toLocal())}"
          "${unsent > 0 ? ', belum termasuk $unsent transaksi yang belum terkirim' : ''}.";
    }
    if (unsent > 0) {
      return "$unsent transaksi belum terkirim ke server dan belum masuk rekap.";
    }
    return null;
  }

  /// Tutup shift butuh semua transaksi sudah di server dan rekap terbaru
  Future<void> _startCloseShift(ThemeProvider theme) async {
    setState(() => _isLoading = true);
    await SyncService().syncNow();
    await _fetchRecap();
    if (!mounted) return;
    if (_cachedAt != null) {
      _showSnackBar(
          "Tutup shift butuh koneksi ke server. Sambungkan internet lalu coba lagi.",
          error: true);
      return;
    }
    if (SyncService().pendingCount > 0) {
      _showSnackBar(
          "Masih ada ${SyncService().pendingCount} transaksi yang belum terkirim. Tunggu sampai terkirim, lalu tutup shift.",
          error: true);
      return;
    }
    _showSettlementDialog(theme);
  }

  void _showSnackBar(String message, {bool error = false, bool success = false}) {
    if (!mounted) return;
    showMessage(context, message, error: error, success: success);
  }

  // Cetak 2 struk (rekap uang + penjualan menu) dari sebuah laporan shift
  Future<bool> _printReport(Map<String, dynamic> report) async {
    setState(() => _isPrinting = true);
    final bool printed = await _printer.printShiftReport(report);
    if (mounted) setState(() => _isPrinting = false);
    return printed;
  }

  // Rekap shift berjalan, tanpa menutup shift
  Future<void> _printCurrentRecap() async {
    await _fetchRecap();
    if (_recapData == null) return;
    final bool printed = await _printReport(_recapData!);
    _showSnackBar(
      printed
          ? "Rekap shift dicetak (2 struk)."
          : "Printer tidak terhubung. Periksa di menu Printer.",
      success: printed,
      error: !printed,
    );
  }

  Future<void> _reprintLastSettlement() async {
    final res = await _apiService.getLastSettlement();
    if (res['status'] != 'success') {
      _showSnackBar(res['message'] ?? "Belum ada shift yang ditutup.", error: true);
      return;
    }
    final bool printed = await _printReport(res['data']);
    _showSnackBar(
      printed
          ? "Settlement terakhir dicetak ulang (2 struk)."
          : "Printer tidak terhubung. Periksa di menu Printer.",
      success: printed,
      error: !printed,
    );
  }

  Future<void> _processCloseShift(String notes, int? actualCash) async {
    // Tanpa printer, struk settlement tidak keluar. Pastikan kasir tahu sebelum shift ditutup.
    if (!await _printer.ensureConnected()) {
      if (!mounted) return;
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Printer belum terhubung"),
          content: const Text(
            "Struk settlement tidak bisa dicetak sekarang. Shift tetap bisa ditutup, "
            "lalu struknya dicetak ulang dari menu Rekap setelah printer tersambung.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Tetap tutup shift"),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    final res = await PosService().closeShift(notes, actualCash: actualCash);

    if (res['status'] != 'success') {
      if (mounted) setState(() => _isLoading = false);
      _showSnackBar(res['message'] ?? "Shift gagal ditutup.", error: true);
      return;
    }

    // Cetak 2 struk: rekap uang + penjualan per menu. Shift tetap tertutup walau printer gagal.
    final bool printed = await _printer.printShiftReport(res['data']);

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');

    if (!mounted) return;
    Provider.of<CartProvider>(context, listen: false).clearCart();
    Provider.of<NavProvider>(context, listen: false).goTo(NavProvider.kasir);

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(printed
            ? "Shift ditutup dan 2 struk settlement dicetak."
            : "Shift ditutup, tapi struk tidak tercetak. Cetak ulang dari menu Rekap setelah masuk."),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  // ===================== DIALOG TUTUP SHIFT =====================

  void _showSettlementDialog(ThemeProvider theme) {
    final summary = _recapData?['summary'] ?? {};
    final payments = _recapData?['payments'] as List? ?? [];

    final int pendingCount = toInt(summary['pending_count']);
    final TextEditingController noteController = TextEditingController();
    final TextEditingController actualCashController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        insetPadding: isMobile(context)
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        title: const Text("Tutup shift?"),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AmountRow("Modal awal", rupiah(summary['starting_cash'])),
                AmountRow("Penjualan tunai",
                    "+ ${rupiah(summary['payments_in_cash'])}"),
                AmountRow("Kas keluar", "− ${rupiah(summary['total_expenses'])}"),
                Divider(height: 20, color: theme.borderColor),
                AmountRow("Uang tunai seharusnya",
                    rupiah(summary['expected_ending_cash']),
                    bold: true),
                const SizedBox(height: 16),
                Text("Non-tunai",
                    style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 4),
                ...payments
                    .where((p) =>
                        p['payment_method'] != 'cash' && toInt(p['total']) > 0)
                    .map((p) => AmountRow(
                        "${_paymentName(p)} · ${p['qty']}", rupiah(p['total']),
                        fontSize: 13)),
                AmountRow("Total non-tunai", rupiah(summary['non_cash_sales']),
                    fontSize: 13),
                if (pendingCount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.warningSoftColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "$pendingCount bill belum dibayar (${rupiah(summary['pending_total'])}). "
                      "Bill ini tidak masuk settlement dan akan terhitung di shift yang melunasinya.",
                      style: TextStyle(color: theme.warningInkColor, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                TextField(
                  controller: actualCashController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: "Uang tunai yang dihitung (opsional)",
                    helperText:
                        "Kosongkan bila sama dengan sistem. Selisihnya ikut tercetak di struk.",
                    helperMaxLines: 2,
                    prefixText: "Rp ",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: "Catatan (opsional)",
                  ),
                ),
                Text(
                  "Setelah ditutup tercetak 2 struk: rekap uang per cara bayar dan penjualan per menu.",
                  style: TextStyle(color: theme.secondaryTextColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.dangerColor),
            onPressed: () {
              Navigator.pop(context);
              _processCloseShift(
                noteController.text,
                int.tryParse(actualCashController.text),
              );
            },
            child: const Text("Tutup shift"),
          ),
        ],
      ),
    );
  }

  // ===================== BUILD =====================

  String _paymentName(dynamic p) {
    const names = {
      'cash': 'Tunai',
      'qris': 'QRIS',
      'debit': 'Debit',
      'credit': 'Kredit',
      'gojek': 'GoFood',
      'grab': 'GrabFood',
      'shopee': 'ShopeeFood',
      'delivery_other': 'Ojol lainnya',
    };
    return names[p['payment_method']] ?? p['label']?.toString() ?? '-';
  }

  String _subtitle() {
    final settlement = _recapData?['settlement'] ?? {};
    final summary = _recapData?['summary'] ?? {};
    final DateTime? openedAt =
        DateTime.tryParse(settlement['opened_at']?.toString() ?? '');
    if (openedAt == null) return "Shift yang sedang berjalan";
    final String base =
        "${settlement['cashier'] ?? ''} · buka ${DateFormat('d MMM, HH:mm', 'id').format(openedAt)} · ${summary['total_bills'] ?? 0} bill";
    final String? stale = _staleNote();
    return stale == null ? base : "$base\n$stale";
  }

  Widget _printMenu(ThemeProvider theme, {required bool compact}) {
    return PopupMenuButton<String>(
      tooltip: "Cetak",
      enabled: !_isPrinting,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'current') _printCurrentRecap();
        if (value == 'last') _reprintLastSettlement();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'current',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.print_outlined, color: theme.primaryColor),
            title: const Text("Cetak rekap shift ini"),
            subtitle: const Text("Tanpa menutup shift"),
          ),
        ),
        PopupMenuItem(
          value: 'last',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.history, color: theme.primaryColor),
            title: const Text("Cetak ulang settlement terakhir"),
            subtitle: const Text("Shift yang sudah ditutup"),
          ),
        ),
      ],
      child: Container(
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.fieldBorderColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _isPrinting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.receipt_long_outlined,
                    size: 20, color: theme.textColor),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text("Cetak",
                  style: TextStyle(
                      color: theme.textColor, fontWeight: FontWeight.w600)),
              Icon(Icons.arrow_drop_down, color: theme.textColor),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final bool mobile = isMobile(context);

    final header = PageHeader(
      title: "Rekap shift",
      subtitle: _subtitle(),
      compact: mobile,
      actions: [
        _printMenu(theme, compact: mobile),
        const SizedBox(width: 8),
        IconButton(
          tooltip: "Muat ulang",
          onPressed: _fetchRecap,
          icon: Icon(Icons.refresh, color: theme.textColor),
        ),
      ],
    );

    final closeBar = Container(
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 32, 12, mobile ? 16 : 32, 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.borderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (!mobile)
              Expanded(
                child: Text(
                  "Tutup shift di akhir jam kerja untuk mencetak settlement.",
                  style: TextStyle(color: theme.secondaryTextColor),
                ),
              ),
            SizedBox(
              width: mobile ? null : 260,
              height: 50,
              child: mobile
                  ? null
                  : _closeButton(theme),
            ),
            if (mobile) Expanded(child: SizedBox(height: 50, child: _closeButton(theme))),
          ],
        ),
      ),
    );

    if (_isLoading || _recapData == null) {
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        body: Padding(
          padding: EdgeInsets.all(mobile ? 16 : 32),
          child: Column(
            children: [
              header,
              Expanded(
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : Text("Rekap belum tersedia. Ketuk muat ulang.",
                          style: TextStyle(color: theme.secondaryTextColor)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final leftColumn = [
      _cashCard(theme),
      const SizedBox(height: 16),
      _paymentsCard(theme),
      const SizedBox(height: 16),
      _summaryCard(theme),
    ];

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      bottomNavigationBar: closeBar,
      body: RefreshIndicator(
        onRefresh: _fetchRecap,
        color: theme.primaryColor,
        child: mobile
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  header,
                  const SizedBox(height: 16),
                  ...leftColumn,
                  const SizedBox(height: 16),
                  _menuCard(theme),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                children: [
                  header,
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Column(children: leftColumn)),
                      const SizedBox(width: 24),
                      Expanded(child: _menuCard(theme)),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _closeButton(ThemeProvider theme) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(backgroundColor: theme.dangerColor),
      onPressed: _recapData == null || _isPrinting
          ? null
          : () => _startCloseShift(theme),
      icon: const Icon(Icons.lock_clock_outlined, size: 20),
      label: const Text("Tutup shift", style: TextStyle(fontSize: 15)),
    );
  }

  // Kartu gelap: uang tunai yang harus ada di laci
  Widget _cashCard(ThemeProvider theme) {
    final summary = _recapData?['summary'] ?? {};
    final Color muted = theme.onInkColor.withValues(alpha: 0.7);

    Widget part(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                    color: theme.onInkColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.inkColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Uang tunai", style: TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            rupiah(summary['expected_ending_cash']),
            style: TextStyle(
              color: theme.onInkColor,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              part("Modal", formatNumber(summary['starting_cash'])),
              part("Tunai masuk", "+${formatNumber(summary['payments_in_cash'])}"),
              part("Kas keluar", "−${formatNumber(summary['total_expenses'])}"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentsCard(ThemeProvider theme) {
    final summary = _recapData?['summary'] ?? {};
    final payments = _recapData?['payments'] as List? ?? [];
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          for (final p in payments)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.subtleColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: _paymentName(p),
                          style: TextStyle(color: theme.textColor)),
                      TextSpan(
                          text: "  · ${p['qty']}",
                          style: TextStyle(color: theme.faintTextColor)),
                    ])),
                  ),
                  Text(rupiah(p['total']),
                      style: TextStyle(
                        color: toInt(p['total']) > 0
                            ? theme.textColor
                            : theme.faintTextColor,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AmountRow("Total penjualan", rupiah(summary['net_sales']),
                bold: true),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(ThemeProvider theme) {
    final summary = _recapData?['summary'] ?? {};
    final int pendingCount = toInt(summary['pending_count']);
    final int voidCount = toInt(summary['void_count']);
    return Column(
      children: [
        Panel(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              AmountRow("Penjualan kotor", rupiah(summary['gross_sales']),
                  fontSize: 13.5),
              AmountRow("Diskon", "− ${rupiah(summary['total_discount'])}",
                  fontSize: 13.5),
              AmountRow("Pajak (PB1)", rupiah(summary['total_tax']),
                  fontSize: 13.5),
              AmountRow("Kas keluar", "− ${rupiah(summary['total_expenses'])}",
                  fontSize: 13.5),
              if (voidCount > 0)
                AmountRow("Dibatalkan · $voidCount", rupiah(summary['void_total']),
                    fontSize: 13.5, valueColor: theme.dangerColor),
            ],
          ),
        ),
        if (pendingCount > 0) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.warningSoftColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: theme.warningColor, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "$pendingCount bill belum dibayar (${rupiah(summary['pending_total'])}). "
                    "Bill ini masuk ke shift yang melunasinya.",
                    style: TextStyle(color: theme.warningInkColor, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Penjualan per menu: jumlah × harga = total, dikelompokkan per kategori
  Widget _menuCard(ThemeProvider theme) {
    final categories = _recapData?['menus_by_category'] as List? ?? [];
    final int totalQty = categories.fold(0, (sum, c) => sum + toInt(c['qty']));

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text("Penjualan per menu",
                    style: TextStyle(
                        color: theme.textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              Text("$totalQty porsi",
                  style: TextStyle(color: theme.secondaryTextColor)),
            ],
          ),
          const SizedBox(height: 8),
          if (categories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text("Belum ada menu terjual di shift ini.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.secondaryTextColor)),
            ),
          for (final category in categories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "${category['category']}".toUpperCase(),
                      style: TextStyle(
                        color: theme.secondaryTextColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Text(
                    "${category['qty']} porsi · ${rupiah(category['total'])}",
                    style: TextStyle(
                        color: theme.secondaryTextColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            for (final item in (category['items'] as List? ?? []))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: theme.subtleColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${item['name']}",
                              style: TextStyle(color: theme.textColor)),
                          Text("${item['qty']} × ${rupiah(item['price'])}",
                              style: TextStyle(
                                  color: theme.secondaryTextColor,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    Text(rupiah(item['total']),
                        style: TextStyle(
                          color: theme.textColor,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
