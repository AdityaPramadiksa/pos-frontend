import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final ApiService _apiService = ApiService();
  List<dynamic> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final data = await _apiService.getOrderHistory();
      if (!mounted) return;

      setState(() {
        _orders = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Error Fetch History: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 24),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.primaryColor,
                      ),
                    )
                  : _orders.isEmpty
                      ? _buildEmptyState(theme)
                      : _buildOrderTable(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeProvider theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Order History",
              style: TextStyle(
                color: theme.textColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "Daftar transaksi hari ini (${DateFormat('dd MMM yyyy').format(DateTime.now())})",
              style: TextStyle(color: theme.secondaryTextColor),
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: _fetchHistory,
          icon: const Icon(Icons.refresh, size: 20),
          label: const Text("Refresh"),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.cardColor,
            foregroundColor: theme.primaryColor,
            side: BorderSide(color: theme.borderColor),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderTable(ThemeProvider theme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          child: DataTable(
            showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(
              theme.backgroundColor.withOpacity(0.5),
            ),
            columns: [
              _col("Invoice", theme),
              _col("Customer", theme),
              _col("Total", theme),
              _col("Type / Payment", theme), // FIX: Ubah judul header
              _col("Status", theme),
              _col("Action", theme),
            ],
            rows: _orders.map((order) {
              bool isVoid = order['status'].toString().toLowerCase() == 'void';
              String type = order['order_type']
                  .toString()
                  .replaceAll('_', ' ')
                  .toUpperCase();
              String payment =
                  order['payment_method']?.toString().toUpperCase() ??
                      "N/A"; // Data Payment
              String platform = order['delivery_platform']?.toString() ?? "";

              return DataRow(
                onSelectChanged: (_) => _showOrderDetails(order, theme),
                cells: [
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['receipt_number'],
                          style: _cellStyle(isVoid, Colors.white),
                        ),
                        Text(
                          DateFormat('HH:mm').format(
                            DateTime.parse(order['created_at']).toLocal(),
                          ),
                          style: TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      order['customer_name'] ?? "-",
                      style: _cellStyle(isVoid, theme.secondaryTextColor),
                    ),
                  ),
                  DataCell(
                    Text(
                      rupiah(order['total_price']),
                      style: _cellStyle(isVoid, theme.textColor, bold: true),
                    ),
                  ),
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Baris 1: Tipe Order (Dine In / To Go / Delivery + Platform)
                        Row(
                          children: [
                            Text(
                              type,
                              style: _cellStyle(
                                isVoid,
                                theme.secondaryTextColor,
                                size: 11,
                              ),
                            ),
                            if (platform.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _buildPlatformBadge(platform),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Baris 2: Metode Pembayaran
                        Row(
                          children: [
                            Icon(
                              Icons.payment,
                              size: 10,
                              color: isVoid ? Colors.grey : theme.primaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              payment,
                              style: _cellStyle(
                                isVoid,
                                theme.primaryColor,
                                size: 10,
                                bold: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  DataCell(_buildStatusBadge(order['status'])),
                  DataCell(
                    IconButton(
                      icon: Icon(
                        Icons.receipt_long,
                        color: isVoid ? Colors.grey : theme.primaryColor,
                      ),
                      onPressed: () => _showOrderDetails(order, theme),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformBadge(String platform) {
    Color color = Colors.green;
    if (platform == 'shopee') color = Colors.orange;
    if (platform == 'grab') color = Colors.greenAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        platform.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  TextStyle _cellStyle(
    bool isVoid,
    Color color, {
    bool bold = false,
    double size = 14,
  }) {
    return TextStyle(
      color: isVoid ? Colors.grey : color,
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      decoration: isVoid ? TextDecoration.lineThrough : null,
    );
  }

  DataColumn _col(String label, ThemeProvider theme) {
    return DataColumn(
      label: Text(
        label,
        style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    String s = status.toLowerCase();
    Color color = s == 'paid'
        ? Colors.greenAccent
        : (s == 'void' ? Colors.redAccent : Colors.orangeAccent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        s.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showOrderDetails(dynamic order, ThemeProvider theme) {
    List<dynamic> items = order['items'] ?? [];
    bool isVoid = order['status'].toString().toLowerCase() == 'void';
    String platform = order['delivery_platform']?.toString() ?? "";
    String payment = order['payment_method']?.toString().toUpperCase() ?? "N/A";

    // 🔥 AMBIL DATA UANG DIBAYAR & KEMBALIAN DARI JSON
    int amountPaid = int.tryParse(order['amount_paid']?.toString() ?? '0') ?? 0;
    int changeAmount =
        int.tryParse(order['change_amount']?.toString() ?? '0') ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Detail Pesanan",
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.grey),
            ),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _infoBlock(
                        "KASIR", order['user']?['name'] ?? "N/A", theme),
                    _infoBlock(
                      "PELANGGAN",
                      order['customer_name'] ?? "Umum",
                      theme,
                    ),
                    _infoBlock("PEMBAYARAN", payment, theme),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _infoBlock(
                      "TIPE",
                      order['order_type'].toString().toUpperCase(),
                      theme,
                    ),
                    if (platform.isNotEmpty)
                      _infoBlock("PLATFORM", platform.toUpperCase(), theme),
                    _infoBlock(
                        "MEJA", order['table_number']?.toString() ?? "-", theme),
                  ],
                ),
                const Divider(height: 32, color: Colors.white10),
                Text(
                  "ITEM MENU",
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${item['qty']}x ${item['menu']?['name'] ?? 'Menu'}",
                                style: TextStyle(
                                  color: theme.secondaryTextColor,
                                  fontSize: 13,
                                ),
                              ),
                              if (item['note'] != null &&
                                  item['note'].toString().trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4,
                                    left: 24,
                                  ),
                                  child: Text(
                                    "* ${item['note']}",
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          rupiah(item['subtotal']),
                          style: TextStyle(
                            color: theme.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 32, color: Colors.white10),
                _summaryRow("Subtotal", rupiah(order['subtotal']), theme),
                _summaryRow(
                  "Pajak (PB1)",
                  rupiah(order['tax_amount']),
                  theme,
                ),
                _summaryRow(
                  "Diskon",
                  "- ${rupiah(order['discount_amount'])}",
                  theme,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "TOTAL AKHIR",
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      rupiah(order['total_price']),
                      style: TextStyle(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                    height: 12), // Jarak sedikit sebelum nominal dibayar

                // 🔥 TAMPILAN BARU: DIBAYAR & KEMBALI
                // Muncul otomatis kalau tipe pembayaran CASH atau kalau uang dibayarnya lebih besar dari 0
                if (payment == 'CASH' || amountPaid > 0) ...[
                  _summaryRow("Dibayar", rupiah(amountPaid), theme),
                  _summaryRow("Kembali", rupiah(changeAmount), theme),
                ],

                if (isVoid) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "ALASAN VOID:",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          order['void_reason'] ?? "Tidak ada alasan",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (!isVoid)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showVoidDialog(order['id'], theme);
              },
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
              label: const Text(
                "VOID TRANSACTION",
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          if (order['status'].toString().toLowerCase() == 'paid')
            TextButton.icon(
              onPressed: () => _reprintReceipt(order),
              icon: Icon(Icons.print, color: theme.primaryColor),
              label: Text(
                "CETAK ULANG",
                style: TextStyle(color: theme.primaryColor),
              ),
            ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: const Text("CLOSE"),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reprintReceipt(dynamic order) async {
    final bool printed = await PrinterService()
        .printCustomerCopy(Map<String, dynamic>.from(order), isReprint: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(printed
            ? "Struk dicetak ulang"
            : "Printer tidak terhubung. Cek menu Printer."),
        backgroundColor: printed ? Colors.green : Colors.red,
      ),
    );
  }

  Widget _infoBlock(String label, String value, ThemeProvider theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _summaryRow(
    String label,
    String value,
    ThemeProvider theme, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: theme.secondaryTextColor, fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(color: color ?? theme.textColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showVoidDialog(int orderId, ThemeProvider theme) {
    final pinController = TextEditingController();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: const Text(
          "Admin Confirmation",
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Otoritas Admin diperlukan untuk membatalkan transaksi.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco("Admin PIN", Icons.lock_outline),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco("Void Reason (Min. 5 char)", Icons.notes),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              if (reasonController.text.length < 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Alasan terlalu pendek!")),
                );
                return;
              }
              final res = await _apiService.voidOrder(
                orderId,
                pinController.text,
                reasonController.text,
              );
              if (res['status'] == 'success') {
                if (!mounted) return;
                Navigator.pop(context);
                _fetchHistory();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("VOID Berhasil"),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? "Error"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("CONFIRM VOID"),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon) {
    return InputDecoration(
      labelText: hint,
      prefixIcon: Icon(icon, size: 20),
      labelStyle: const TextStyle(color: Colors.grey),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.white10),
      ),
    );
  }

  Widget _buildEmptyState(ThemeProvider theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: theme.secondaryTextColor.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          Text(
            "Belum ada transaksi hari ini",
            style: TextStyle(color: theme.secondaryTextColor),
          ),
        ],
      ),
    );
  }
}
