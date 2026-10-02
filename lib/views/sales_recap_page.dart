import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../providers/cart_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchRecap();
  }

  Future<void> _fetchRecap() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final res = await _apiService.getSalesRecapitulation();
    if (!mounted) return;
    setState(() {
      if (res['status'] == 'success') _recapData = res['data'];
      _isLoading = false;
    });
    if (res['status'] != 'success') {
      _showSnackBar(res['message'] ?? "Gagal memuat rekap", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
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
          ? "Rekap shift dicetak (2 struk)"
          : "Printer tidak terhubung. Cek menu Printer.",
      printed ? Colors.green : Colors.red,
    );
  }

  Future<void> _reprintLastSettlement() async {
    final res = await _apiService.getLastSettlement();
    if (res['status'] != 'success') {
      _showSnackBar(res['message'] ?? "Belum ada shift yang ditutup", Colors.red);
      return;
    }
    final bool printed = await _printReport(res['data']);
    _showSnackBar(
      printed
          ? "Settlement terakhir dicetak ulang (2 struk)"
          : "Printer tidak terhubung. Cek menu Printer.",
      printed ? Colors.green : Colors.red,
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
            "Struk settlement tidak bisa dicetak sekarang.\n\n"
            "Shift tetap bisa ditutup, lalu struk dicetak ulang nanti lewat tombol "
            "\"Cetak Ulang Settlement\" di halaman ini.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("BATAL"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("TETAP TUTUP SHIFT"),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    final res = await _apiService.closeSettlement(notes, actualCash: actualCash);

    if (res['status'] != 'success') {
      if (mounted) setState(() => _isLoading = false);
      _showSnackBar(res['message'] ?? "Gagal menutup shift", Colors.red);
      return;
    }

    // --- CETAK 2 STRUK: REKAP UANG + PENJUALAN PER MENU ---
    // Dicetak sebelum logout; shift tetap tertutup walau printer gagal.
    final bool printed = await _printer.printShiftReport(res['data']);

    // --- PROSES LOGOUT ---
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');

    if (!mounted) return;
    Provider.of<CartProvider>(context, listen: false).clearCart();

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(printed
            ? "Shift ditutup & 2 struk settlement dicetak. Sampai jumpa!"
            : "Shift ditutup, tapi struk GAGAL dicetak. Cetak ulang dari menu Rekap setelah login."),
        backgroundColor: printed ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _showSettlementDialog(ThemeProvider theme) {
    final summary = _recapData?['summary'] ?? {};
    final payments = _recapData?['payments'] as List? ?? [];

    final int totalExpenses = toInt(summary['total_expenses']);
    final int startingCash = toInt(summary['starting_cash']);
    final int cashSales = toInt(summary['payments_in_cash']);
    final int expectedCash = toInt(summary['expected_ending_cash']);
    final int pendingCount = toInt(summary['pending_count']);

    final TextEditingController noteController = TextEditingController();
    final TextEditingController actualCashController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          "Konfirmasi Tutup Shift",
          style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSettlementRow(
                    "Modal Awal (Cash)", rupiah(startingCash), theme),
                _buildSettlementRow(
                  "Total Penjualan Cash",
                  "+ ${rupiah(cashSales)}",
                  theme,
                  color: Colors.green,
                ),
                _buildSettlementRow(
                  "Total Kas Keluar (Petty Cash)",
                  "- ${rupiah(totalExpenses)}",
                  theme,
                  color: Colors.redAccent,
                ),
                Divider(height: 32, color: theme.borderColor),
                _buildSettlementRow(
                  "UANG FISIK DI LACI",
                  rupiah(expectedCash),
                  theme,
                  isBold: true,
                  color: theme.primaryColor,
                ),
                const SizedBox(height: 24),
                _sectionTitle("RINGKASAN NON-CASH", theme),
                ...payments
                    .where((p) =>
                        p['payment_method'] != 'cash' && toInt(p['total']) > 0)
                    .map(
                      (p) => _buildSettlementRow(
                        "${p['label']} (${p['qty']})",
                        rupiah(p['total']),
                        theme,
                      ),
                    ),
                _buildSettlementRow(
                  "Total Non-Cash",
                  rupiah(summary['non_cash_sales']),
                  theme,
                  isBold: true,
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withAlpha(120)),
                    ),
                    child: Text(
                      "Masih ada $pendingCount bill belum lunas (${rupiah(summary['pending_total'])}). "
                      "Bill ini tidak masuk settlement dan akan terhitung di shift yang melunasinya.",
                      style: const TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: actualCashController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(color: theme.textColor, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: "Uang fisik hasil hitung (opsional)",
                    helperText:
                        "Kosongkan jika sesuai sistem. Selisih ikut tercetak di struk.",
                    helperStyle: TextStyle(color: theme.secondaryTextColor),
                    prefixText: "Rp ",
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  maxLength: 255,
                  style: TextStyle(color: theme.textColor, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: "Catatan Akhir Shift",
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Setelah ditutup akan tercetak 2 struk: rekap uang per cara bayar dan penjualan per menu.",
                  style:
                      TextStyle(color: theme.secondaryTextColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("BATAL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              _processCloseShift(
                noteController.text,
                int.tryParse(actualCashController.text),
              );
            },
            child: const Text(
              "YA, TUTUP SHIFT",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, ThemeProvider theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(
          title,
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 32),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.primaryColor,
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: _buildFinancialSummary(theme),
                        ),
                        const SizedBox(width: 32),
                        Expanded(flex: 1, child: _buildMenuRecap(theme)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeProvider theme) {
    final settlement = _recapData?['settlement'] ?? {};
    final DateTime? openedAt =
        DateTime.tryParse(settlement['opened_at']?.toString() ?? '');

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Sales Recapitulation",
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                openedAt == null
                    ? "Rekap shift berjalan"
                    : "Shift ${settlement['cashier'] ?? ''} - buka ${DateFormat('dd MMM yyyy HH:mm').format(openedAt)} WITA",
                style: TextStyle(color: theme.secondaryTextColor),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _isPrinting ? null : _reprintLastSettlement,
          icon: const Icon(Icons.receipt_long),
          label: const Text("Cetak Ulang Settlement"),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.primaryColor,
            side: BorderSide(color: theme.borderColor),
            padding: const EdgeInsets.all(20),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _fetchRecap,
          icon: const Icon(Icons.refresh),
          label: const Text("Refresh Data"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueGrey,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(20),
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialSummary(ThemeProvider theme) {
    final summary = _recapData?['summary'] ?? {};
    final payments = _recapData?['payments'] as List? ?? [];
    final orderTypes = _recapData?['order_types'] as List? ?? [];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Financial Summary",
            style: TextStyle(
              color: theme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Divider(height: 32, color: theme.borderColor),

          // 🔥 BAGIAN INI DIBUAT BISA DI-SCROLL 🔥
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRow(
                      "Gross Sales", rupiah(summary['gross_sales']), theme),
                  _buildRow(
                    "Total Discount",
                    "- ${rupiah(summary['total_discount'])}",
                    theme,
                    color: Colors.redAccent,
                  ),
                  _buildRow("Tax (PB1)", rupiah(summary['total_tax']), theme),
                  const SizedBox(height: 8),
                  _buildRow(
                    "Petty Cash (Pengeluaran)",
                    "- ${rupiah(summary['total_expenses'])}",
                    theme,
                    color: Colors.orangeAccent,
                  ),
                  _buildRow(
                    "Uang Fisik di Laci",
                    rupiah(summary['expected_ending_cash']),
                    theme,
                    color: Colors.greenAccent,
                  ),
                  Divider(height: 32, color: theme.borderColor),
                  _sectionTitle("PAYMENT METHODS", theme),
                  ...payments.map(
                    (p) => _buildRow(
                      "${p['label']} (${p['qty']})",
                      rupiah(p['total']),
                      theme,
                      isSecondary: true,
                    ),
                  ),
                  Divider(height: 32, color: theme.borderColor),
                  _sectionTitle("TIPE ORDER", theme),
                  ...orderTypes.map(
                    (t) => _buildRow(
                      "${t['label']} (${t['qty']})",
                      rupiah(t['total']),
                      theme,
                      isSecondary: true,
                    ),
                  ),
                  if (toInt(summary['void_count']) > 0)
                    _buildRow(
                      "VOID (${summary['void_count']})",
                      rupiah(summary['void_total']),
                      theme,
                      isSecondary: true,
                      color: Colors.redAccent,
                    ),
                  if (toInt(summary['pending_count']) > 0)
                    _buildRow(
                      "BILL GANTUNG (${summary['pending_count']})",
                      rupiah(summary['pending_total']),
                      theme,
                      isSecondary: true,
                      color: Colors.orangeAccent,
                    ),
                ],
              ),
            ),
          ),

          // 🔥 BAGIAN TOTAL & TOMBOL TETAP DI BAWAH (TIDAK IKUT SCROLL) 🔥
          Divider(color: theme.borderColor, height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total Net Sales (${summary['total_bills'] ?? 0} bill)",
                style: TextStyle(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                rupiah(summary['net_sales']),
                style: TextStyle(
                  color: theme.primaryColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isPrinting ? null : _printCurrentRecap,
                  icon: _isPrinting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print),
                  label: const Text(
                    "CETAK REKAP",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.primaryColor,
                    side: BorderSide(color: theme.primaryColor),
                    padding: const EdgeInsets.all(20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _recapData == null || _isPrinting
                      ? null
                      : () => _showSettlementDialog(theme),
                  icon: const Icon(Icons.lock_clock),
                  label: const Text(
                    "END SHIFT / SETTLEMENT",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Penjualan per menu: qty x harga = total, dikelompokkan per kategori
  Widget _buildMenuRecap(ThemeProvider theme) {
    final categories = _recapData?['menus_by_category'] as List? ?? [];
    final int totalQty =
        categories.fold(0, (sum, c) => sum + toInt(c['qty']));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Penjualan per Menu",
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "$totalQty item terjual",
                style: TextStyle(color: theme.secondaryTextColor),
              ),
            ],
          ),
          Divider(height: 32, color: theme.borderColor),
          Expanded(
            child: categories.isEmpty
                ? Center(
                    child: Text(
                      "Belum ada data penjualan",
                      style: TextStyle(color: theme.secondaryTextColor),
                    ),
                  )
                : ListView(
                    children: [
                      for (var category in categories) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "${category['category']}".toUpperCase(),
                                style: TextStyle(
                                  color: theme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                "${category['qty']} item - ${rupiah(category['total'])}",
                                style: TextStyle(
                                  color: theme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (var item in (category['items'] as List? ?? []))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${item['name']}",
                                        style:
                                            TextStyle(color: theme.textColor),
                                      ),
                                      Text(
                                        "${item['qty']} x ${rupiah(item['price'])}",
                                        style: TextStyle(
                                          color: theme.secondaryTextColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  rupiah(item['total']),
                                  style: TextStyle(
                                    color: theme.textColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Divider(height: 24, color: theme.borderColor),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    String label,
    String value,
    ThemeProvider theme, {
    Color? color,
    bool isSecondary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSecondary ? theme.secondaryTextColor : theme.textColor,
              fontSize: isSecondary ? 13 : 15,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ??
                  (isSecondary ? theme.secondaryTextColor : theme.textColor),
              fontWeight: isSecondary ? FontWeight.normal : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementRow(
    String label,
    String value,
    ThemeProvider theme, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: theme.secondaryTextColor, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? theme.textColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 16 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
