import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/cart_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/ui.dart';
import 'payment_page.dart';

class BillsPage extends StatefulWidget {
  const BillsPage({super.key});

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  final ApiService _apiService = ApiService();
  List<dynamic> _pendingBills = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBills();
  }

  Future<void> _fetchBills() async {
    if (!mounted) return;
    setState(() => _isLoading = _pendingBills.isEmpty);
    final bills = await _apiService.getPendingBills();
    if (!mounted) return;
    setState(() {
      _pendingBills = bills;
      _isLoading = false;
    });
  }

  String _billTitle(dynamic bill) {
    final String table = bill['table_number']?.toString() ?? '';
    return table.isEmpty || table == '-' ? "Tanpa meja" : "Meja $table";
  }

  String _billTime(dynamic bill) {
    final DateTime? time =
        DateTime.tryParse(bill['created_at']?.toString() ?? '')?.toLocal();
    return time == null ? '' : DateFormat('HH:mm').format(time);
  }

  String _customer(dynamic bill) {
    final String name = bill['customer_name']?.toString() ?? '';
    return name.isEmpty || name == 'Pelanggan Umum' ? "Pelanggan umum" : name;
  }

  void _navigateToPayment(dynamic bill) {
    final cart = Provider.of<CartProvider>(context, listen: false);
    // Total, pajak & diskon mengikuti bill yang tersimpan di server
    cart.loadBill(Map<String, dynamic>.from(bill));

    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => const PaymentPage(isFromBill: true)),
    ).then((_) {
      // Batal bayar: buang isi bill dari keranjang supaya tidak terbawa ke kasir
      if (cart.isBill) cart.clearCart();
      _fetchBills();
    });
  }

  /// Pindah ke halaman Kasir untuk menambah pesanan ke bill ini
  void _addToBill(dynamic bill) {
    Provider.of<CartProvider>(context, listen: false)
        .startAppend(Map<String, dynamic>.from(bill));
    Provider.of<NavProvider>(context, listen: false).goTo(NavProvider.kasir);
  }

  Future<void> _printBill(dynamic bill) async {
    final bool printed = await PrinterService()
        .printCustomerCopy(Map<String, dynamic>.from(bill), isBill: true);
    if (!mounted) return;
    showMessage(
      context,
      printed ? "Tagihan dicetak." : "Printer tidak terhubung. Periksa di menu Printer.",
      success: printed,
      error: !printed,
    );
  }

  void _showBillDialog(dynamic bill, ThemeProvider theme) {
    final List<dynamic> items = bill['items'] ?? [];
    final bool mobile = isMobile(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: mobile
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        title: Row(
          children: [
            Expanded(child: Text("Bill ${_billTitle(bill)}")),
            IconButton(
              tooltip: "Tutup",
              onPressed: () => Navigator.pop(dialogContext),
              icon: Icon(Icons.close, color: theme.secondaryTextColor),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("${_customer(bill)} · dibuat ${_billTime(bill)}",
                  style: TextStyle(color: theme.secondaryTextColor)),
              Divider(height: 24, color: theme.borderColor),
              // Column biasa (bukan ListView): dialog ini sudah bisa di-scroll,
              // dan ListView di dalam dialog membuat layout crash di layar HP.
              ...items.map((item) {
                final String note = item['note']?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                "${item['qty']}× ${item['menu']?['name'] ?? 'Menu'}",
                                style: TextStyle(color: theme.textColor)),
                            if (note.isNotEmpty)
                              Text(note,
                                  style: TextStyle(
                                      color: theme.warningColor, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(rupiah(item['subtotal']),
                          style: TextStyle(color: theme.textColor)),
                    ],
                  ),
                );
              }),
              Divider(height: 24, color: theme.borderColor),
              AmountRow("Subtotal", rupiah(bill['subtotal']), fontSize: 13),
              AmountRow("Pajak (PB1)", rupiah(bill['tax_amount']), fontSize: 13),
              if (toInt(bill['discount_amount']) > 0)
                AmountRow("Diskon", "− ${rupiah(bill['discount_amount'])}",
                    fontSize: 13),
              AmountRow("Total tagihan", rupiah(bill['total_price']), bold: true),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _navigateToPayment(bill);
                  },
                  child: const Text("Bayar bill"),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _addToBill(bill);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Tambah pesanan"),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () => _printBill(bill),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text("Cetak tagihan"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final bool mobile = isMobile(context);
    final int total =
        _pendingBills.fold(0, (sum, b) => sum + toInt(b['total_price']));

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 32, mobile ? 16 : 28, mobile ? 16 : 32, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: "Bill belum dibayar",
              subtitle: _pendingBills.isEmpty
                  ? "Semua bill sudah lunas"
                  : "${_pendingBills.length} bill · total ${rupiah(total)}",
              compact: mobile,
              actions: [
                IconButton(
                  tooltip: "Muat ulang",
                  onPressed: _fetchBills,
                  icon: Icon(Icons.refresh, color: theme.textColor),
                ),
              ],
            ),
            SizedBox(height: mobile ? 16 : 24),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _fetchBills,
                      color: theme.primaryColor,
                      child: _pendingBills.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [_buildEmptyState(theme)],
                            )
                          : GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 24),
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: mobile ? 600 : 300,
                                mainAxisExtent: 132,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _pendingBills.length,
                              itemBuilder: (context, index) => _buildBillCard(
                                  _pendingBills[index], theme),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillCard(dynamic bill, ThemeProvider theme) {
    final int itemCount = (bill['items'] as List? ?? [])
        .fold(0, (sum, item) => sum + toInt(item['qty']));

    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showBillDialog(bill, theme),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusChip(_billTitle(bill), tone: ChipTone.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text("sejak ${_billTime(bill)}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: theme.secondaryTextColor, fontSize: 12)),
                  ),
                ],
              ),
              const Spacer(),
              Text(_customer(bill),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: theme.textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text("$itemCount porsi",
                      style: TextStyle(
                          color: theme.secondaryTextColor, fontSize: 13)),
                  const Spacer(),
                  Text(
                    rupiah(bill['total_price']),
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: theme.placeholderIconColor),
          const SizedBox(height: 12),
          Text("Tidak ada bill yang belum dibayar.",
              style: TextStyle(color: theme.secondaryTextColor, fontSize: 15)),
          const SizedBox(height: 4),
          Text("Bill muncul di sini saat kasir menekan \"Simpan bill\".",
              style: TextStyle(color: theme.faintTextColor, fontSize: 13)),
        ],
      ),
    );
  }
}
