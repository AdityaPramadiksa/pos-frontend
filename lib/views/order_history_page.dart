import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/pos_service.dart';
import '../services/sync_service.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/ui.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final ApiService _apiService = ApiService();
  final PosService _pos = PosService();
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  bool _fresh = true;
  int _syncedTick = 0;

  static const Map<String, String> _typeLabels = {
    'dine_in': 'Makan di sini',
    'to_go': 'Bungkus',
    'delivery': 'Ojol',
  };

  @override
  void initState() {
    super.initState();
    _syncedTick = SyncService().syncedTick;
    SyncService().addListener(_onSync);
    _fetchHistory();
  }

  @override
  void dispose() {
    SyncService().removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (SyncService().syncedTick == _syncedTick) return;
    _syncedTick = SyncService().syncedTick;
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;
    setState(() => _isLoading = _orders.isEmpty);
    final res = await _pos.history();
    if (!mounted) return;
    setState(() {
      _orders = res.items;
      _fresh = res.fresh;
      _isLoading = false;
    });
  }

  String _time(dynamic order) {
    final DateTime? t =
        DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal();
    return t == null ? '' : DateFormat('HH:mm').format(t);
  }

  String _typeLabel(dynamic order) {
    final String type = _typeLabels[order['order_type']] ?? '${order['order_type']}';
    final String platform = order['delivery_platform']?.toString() ?? '';
    return platform.isEmpty ? type : "$type · ${platformLabel(platform)}";
  }

  String _paymentLabel(dynamic order) {
    final String method = order['payment_method']?.toString() ?? '';
    if (method.isEmpty) return 'Belum dibayar';
    if (method == 'delivery') return 'Lewat aplikasi';
    if (method == 'cash') return 'Tunai';
    if (method == 'credit') return 'Kredit';
    return method.toUpperCase();
  }

  String _customer(dynamic order) {
    final String name = order['customer_name']?.toString() ?? '';
    return name.isEmpty || name == 'Pelanggan Umum' ? 'Pelanggan umum' : name;
  }

  Widget _statusChip(dynamic order) {
    if (order['_failed'] == true) {
      return const StatusChip("Gagal terkirim", tone: ChipTone.danger);
    }
    if (PosService.isUnsynced(order)) {
      return StatusChip(
          order['status'] == 'paid' ? "Lunas · offline" : "Bill · offline",
          tone: ChipTone.neutral);
    }
    switch (order['status'].toString().toLowerCase()) {
      case 'paid':
        return const StatusChip("Lunas", tone: ChipTone.success);
      case 'void':
        return const StatusChip("Dibatalkan", tone: ChipTone.danger);
      default:
        return const StatusChip("Belum dibayar", tone: ChipTone.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final bool mobile = isMobile(context);
    final int paidCount =
        _orders.where((o) => o['status'] == 'paid').length;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 32, mobile ? 16 : 28, mobile ? 16 : 32, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: "Riwayat pesanan",
              subtitle:
                  "Hari ini, ${DateFormat('d MMMM yyyy', 'id').format(DateTime.now())} · $paidCount lunas dari ${_orders.length} pesanan"
                  "${_fresh ? '' : ' · offline'}",
              compact: mobile,
              actions: [
                IconButton(
                  tooltip: "Muat ulang",
                  onPressed: _fetchHistory,
                  icon: Icon(Icons.refresh, color: theme.textColor),
                ),
              ],
            ),
            SizedBox(height: mobile ? 16 : 24),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _fetchHistory,
                      color: theme.primaryColor,
                      child: _orders.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 80),
                                Icon(Icons.history,
                                    size: 48, color: theme.placeholderIconColor),
                                const SizedBox(height: 12),
                                Text("Belum ada pesanan hari ini.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: theme.secondaryTextColor)),
                              ],
                            )
                          : (mobile
                              ? _buildOrderList(theme)
                              : _buildOrderTable(theme)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Tablet: tabel ---
  Widget _buildOrderTable(ThemeProvider theme) {
    TextStyle head = TextStyle(
        color: theme.secondaryTextColor,
        fontSize: 12,
        fontWeight: FontWeight.w500);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    SizedBox(width: 70, child: Text("Jam", style: head)),
                    Expanded(flex: 3, child: Text("No. struk", style: head)),
                    Expanded(flex: 3, child: Text("Pelanggan", style: head)),
                    Expanded(flex: 3, child: Text("Jenis", style: head)),
                    Expanded(flex: 2, child: Text("Cara bayar", style: head)),
                    Expanded(
                        flex: 2,
                        child: Text("Total",
                            style: head, textAlign: TextAlign.right)),
                    const SizedBox(width: 20),
                    SizedBox(width: 118, child: Text("Status", style: head)),
                  ],
                ),
              ),
              for (final order in _orders) _tableRow(order, theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableRow(dynamic order, ThemeProvider theme) {
    final bool isVoid = order['status'] == 'void';
    final TextStyle base = TextStyle(
      color: isVoid ? theme.faintTextColor : theme.textColor,
      fontSize: 14,
      decoration: isVoid ? TextDecoration.lineThrough : null,
    );
    return InkWell(
      onTap: () => _showOrderDetails(order, theme),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.subtleColor)),
        ),
        child: Row(
          children: [
            SizedBox(
                width: 70,
                child: Text(_time(order),
                    style: base.copyWith(color: theme.secondaryTextColor))),
            Expanded(
                flex: 3,
                child: Text(order['receipt_number'] ?? '-',
                    style: base.copyWith(fontWeight: FontWeight.w600))),
            Expanded(
                flex: 3,
                child: Text(_customer(order),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: base)),
            Expanded(
                flex: 3,
                child: Text(_typeLabel(order),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: base)),
            Expanded(flex: 2, child: Text(_paymentLabel(order), style: base)),
            Expanded(
              flex: 2,
              child: Text(rupiah(order['total_price']),
                  textAlign: TextAlign.right,
                  style: base.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
            const SizedBox(width: 20),
            SizedBox(
                width: 118,
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: _statusChip(order))),
          ],
        ),
      ),
    );
  }

  // --- HP: daftar kartu ---
  Widget _buildOrderList(ThemeProvider theme) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final order = _orders[index];
        final bool isVoid = order['status'] == 'void';
        return Material(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: theme.borderColor),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showOrderDetails(order, theme),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order['receipt_number'] ?? '-',
                          style: TextStyle(
                            color: isVoid ? theme.faintTextColor : theme.textColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            decoration:
                                isVoid ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      _statusChip(order),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text("${_time(order)} · ${_customer(order)}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.secondaryTextColor, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            "${_typeLabel(order)} · ${_paymentLabel(order)}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: theme.secondaryTextColor, fontSize: 12.5)),
                      ),
                      Text(
                        rupiah(order['total_price']),
                        style: TextStyle(
                          color: isVoid ? theme.faintTextColor : theme.textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          decoration:
                              isVoid ? TextDecoration.lineThrough : null,
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
      },
    );
  }

  // --- Detail pesanan ---
  void _showOrderDetails(dynamic order, ThemeProvider theme) {
    final List<dynamic> items = order['items'] ?? [];
    final String status = order['status'].toString().toLowerCase();
    final bool isVoid = status == 'void';
    final int amountPaid = toInt(order['amount_paid']);
    final int changeAmount = toInt(order['change_amount']);
    final bool mobile = isMobile(context);

    Widget info(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(color: theme.secondaryTextColor, fontSize: 12)),
            Text(value,
                style: TextStyle(
                    color: theme.textColor, fontWeight: FontWeight.w600)),
          ],
        );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: mobile
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        contentPadding: mobile
            ? const EdgeInsets.fromLTRB(16, 12, 16, 8)
            : const EdgeInsets.fromLTRB(24, 16, 24, 8),
        title: Row(
          children: [
            Expanded(child: Text(order['receipt_number'] ?? 'Detail pesanan')),
            IconButton(
              tooltip: "Tutup",
              onPressed: () => Navigator.pop(dialogContext),
              icon: Icon(Icons.close, color: theme.secondaryTextColor),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  children: [
                    info("Kasir", order['user']?['name'] ?? '-'),
                    info("Pelanggan", _customer(order)),
                    info("Jenis", _typeLabel(order)),
                    if ((order['table_number']?.toString() ?? '').isNotEmpty &&
                        order['table_number'].toString() != '-')
                      info("Meja", order['table_number'].toString()),
                    info("Cara bayar", _paymentLabel(order)),
                  ],
                ),
                Divider(height: 28, color: theme.borderColor),
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
                                        color: theme.warningColor,
                                        fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(rupiah(item['subtotal']),
                            style: TextStyle(
                                color: theme.textColor,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  );
                }),
                Divider(height: 28, color: theme.borderColor),
                AmountRow("Subtotal", rupiah(order['subtotal']), fontSize: 13),
                AmountRow("Pajak (PB1)", rupiah(order['tax_amount']),
                    fontSize: 13),
                if (toInt(order['discount_amount']) > 0)
                  AmountRow("Diskon", "− ${rupiah(order['discount_amount'])}",
                      fontSize: 13),
                AmountRow("Total", rupiah(order['total_price']), bold: true),
                if (order['payment_method'] == 'cash' && amountPaid > 0) ...[
                  AmountRow("Uang diterima", rupiah(amountPaid), fontSize: 13),
                  AmountRow("Kembalian", rupiah(changeAmount), fontSize: 13),
                ],
                if (isVoid) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.dangerSoftColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "Dibatalkan: ${order['void_reason'] ?? 'tanpa alasan'}",
                      style: TextStyle(color: theme.dangerColor, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          // Void dicek PIN admin di server, jadi hanya untuk pesanan yang sudah terkirim
          if (!isVoid && !PosService.isUnsynced(order) && order['id'] != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: theme.dangerColor),
              onPressed: () {
                Navigator.pop(dialogContext);
                _showVoidDialog(order, theme);
              },
              child: const Text("Batalkan transaksi"),
            ),
          if (status == 'paid')
            ElevatedButton.icon(
              onPressed: () => _reprintReceipt(order),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text("Cetak ulang struk"),
            ),
        ],
      ),
    );
  }

  Future<void> _reprintReceipt(dynamic order) async {
    final bool printed = await PrinterService()
        .printCustomerCopy(Map<String, dynamic>.from(order), isReprint: true);
    if (!mounted) return;
    showMessage(
      context,
      printed ? "Struk dicetak ulang." : "Printer tidak terhubung. Periksa di menu Printer.",
      success: printed,
      error: !printed,
    );
  }

  void _showVoidDialog(dynamic order, ThemeProvider theme) {
    final pinController = TextEditingController();
    final reasonController = TextEditingController();
    bool sending = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text("Batalkan ${order['receipt_number']}?"),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    "Butuh persetujuan admin. Stok menu dikembalikan dan total shift dihitung ulang."),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: "Alasan pembatalan",
                    hintText: "Contoh: salah input menu",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: "PIN admin",
                    counterText: "",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Kembali"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: theme.dangerColor),
              onPressed: sending
                  ? null
                  : () async {
                      if (reasonController.text.trim().length < 5) {
                        showMessage(dialogContext,
                            "Tulis alasan minimal 5 huruf.",
                            error: true);
                        return;
                      }
                      setDialog(() => sending = true);
                      final res = await _apiService.voidOrder(
                        order['id'],
                        pinController.text,
                        reasonController.text.trim(),
                      );
                      if (!dialogContext.mounted) return;
                      setDialog(() => sending = false);
                      if (res['status'] == 'success') {
                        Navigator.pop(dialogContext);
                        _fetchHistory();
                        if (mounted) {
                          showMessage(context, "Transaksi dibatalkan.",
                              success: true);
                        }
                      } else {
                        showMessage(dialogContext,
                            res['message'] ?? "Pembatalan gagal.",
                            error: true);
                      }
                    },
              child: const Text("Batalkan transaksi"),
            ),
          ],
        ),
      ),
    );
  }
}
