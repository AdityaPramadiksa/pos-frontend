import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../providers/theme_provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';
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
    setState(() => _isLoading = true);
    try {
      final bills = await _apiService.getPendingBills();
      if (!mounted) return;
      setState(() {
        _pendingBills = bills;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar("Gagal mengambil data bill: $e", Colors.red);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: color,
          duration: const Duration(seconds: 2)),
    );
  }

  void _showPayDialog(dynamic bill, ThemeProvider theme) {
    List<dynamic> items = bill['items'] ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.payments_outlined, color: theme.primaryColor),
            const SizedBox(width: 10),
            Text(
              "Bill Meja ${bill['table_number'] ?? '-'}",
              style: TextStyle(
                  color: theme.textColor, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Pelanggan: ${bill['customer_name'] ?? 'Guest'}",
                  style: TextStyle(color: theme.secondaryTextColor)),
              const Divider(height: 32),
              Text("Rincian Pesanan:",
                  style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: Text(
                                  "${item['qty']}x ${item['menu']?['name'] ?? 'Menu'}",
                                  style: TextStyle(
                                      color: theme.secondaryTextColor,
                                      fontSize: 13))),
                          Text(rupiah(item['subtotal']),
                              style: TextStyle(
                                  color: theme.textColor, fontSize: 13)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 32),
              _totalRow("Subtotal", rupiah(bill['subtotal']), theme),
              _totalRow("Pajak (PB1)", rupiah(bill['tax_amount']), theme),
              if (toInt(bill['discount_amount']) > 0)
                _totalRow(
                    "Diskon", "- ${rupiah(bill['discount_amount'])}", theme),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Total Tagihan",
                      style: TextStyle(
                          color: theme.textColor, fontWeight: FontWeight.bold)),
                  Text(rupiah(bill['total_price']),
                      style: TextStyle(
                          color: theme.primaryColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.primaryColor,
                          side: BorderSide(color: theme.primaryColor),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _printBill(bill),
                        icon: const Icon(Icons.print, size: 18),
                        label: const Text("CETAK BILL",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _navigateToPayment(bill);
                        },
                        child: const Text("PROSES PEMBAYARAN",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
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

  Future<void> _printBill(dynamic bill) async {
    final bool printed = await PrinterService()
        .printCustomerCopy(Map<String, dynamic>.from(bill), isBill: true);
    if (!mounted) return;
    _showSnackBar(
      printed ? "Tagihan dicetak" : "Printer tidak terhubung. Cek menu Printer.",
      printed ? Colors.green : Colors.red,
    );
  }

  String _billTime(dynamic bill) {
    final DateTime? time =
        DateTime.tryParse(bill['created_at']?.toString() ?? '')?.toLocal();
    return time == null ? '' : DateFormat('dd/MM HH:mm').format(time);
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Active Bills",
                        style: TextStyle(
                            color: theme.textColor,
                            fontSize: 28,
                            fontWeight: FontWeight.bold)),
                    Text("Kelola pesanan gantung yang belum lunas",
                        style: TextStyle(color: theme.secondaryTextColor)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _fetchBills,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text("Refresh Data"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.cardColor,
                    foregroundColor: theme.primaryColor,
                    side: BorderSide(color: theme.borderColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Expanded(
              child: _isLoading
                  ? Center(
                      child:
                          CircularProgressIndicator(color: theme.primaryColor))
                  : _pendingBills.isEmpty
                      ? _buildEmptyState(theme)
                      : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            childAspectRatio:
                                1.3, // 🔥 Disesuaikan agar card lebih lebar (Fix Overflow)
                          ),
                          itemCount: _pendingBills.length,
                          itemBuilder: (context, index) =>
                              _buildBillCard(_pendingBills[index], theme),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: theme.secondaryTextColor, fontSize: 13)),
          Text(value, style: TextStyle(color: theme.textColor, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildBillCard(dynamic bill, ThemeProvider theme) {
    return InkWell(
      onTap: () => _showPayDialog(bill, theme),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                      "Meja ${bill['table_number'] ?? '-'}", // 🔥 Fix Meja Null
                      style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
                Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 14, color: theme.secondaryTextColor),
                    const SizedBox(width: 4),
                    Text(_billTime(bill),
                        style: TextStyle(
                            color: theme.secondaryTextColor, fontSize: 11)),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Text(bill['customer_name'] ?? "Pelanggan Umum",
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            // 🔥 Fix Overflow: Menggunakan Wrap atau Row dengan Expanded
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Tagihan:",
                    style: TextStyle(
                        color: theme.secondaryTextColor, fontSize: 12)),
                Flexible(
                  child: Text(rupiah(bill['total_price']),
                      style: TextStyle(
                          color: theme.primaryColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeProvider theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 80, color: theme.borderColor.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text("Semua meja sudah lunas!",
              style: TextStyle(color: theme.secondaryTextColor, fontSize: 16)),
        ],
      ),
    );
  }
}
