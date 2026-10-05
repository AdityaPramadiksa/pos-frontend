import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/ui.dart';

class PaymentPage extends StatefulWidget {
  final bool isFromBill; // Tambahkan baris ini

  // Update constructor agar bisa menerima parameter
  const PaymentPage({super.key, this.isFromBill = false});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final ApiService _apiService = ApiService();
  int _amountReceived = 0;
  bool _isProcessing = false;

  final List<int> _denominations = [
    1000,
    2000,
    5000,
    10000,
    20000,
    50000,
    100000,
  ];

  @override
  void initState() {
    super.initState();
    // Order delivery defaultnya dibayar platform (Gojek/Grab/ShopeeFood);
    // order lain tidak boleh memakai metode "delivery".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cart = Provider.of<CartProvider>(context, listen: false);
      final bool isDelivery = cart.orderType == 'delivery';
      if (isDelivery && !widget.isFromBill) {
        cart.setPaymentMethod('delivery');
      } else if (!isDelivery && cart.paymentMethod == 'delivery') {
        cart.setPaymentMethod('cash');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final theme = Provider.of<ThemeProvider>(context);
    final bool mobile = isMobile(context);

    final appBar = AppBar(
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new,
          color: theme.textColor,
          size: 20,
        ),
        onPressed: _isProcessing ? null : () => Navigator.pop(context),
      ),
      title: Text(
        widget.isFromBill
            ? "Pelunasan bill"
            : "Pembayaran",
        style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold),
      ),
      backgroundColor: theme.backgroundColor,
      elevation: 0,
    );

    // --- VERSI HP: satu kolom, tombol konfirmasi menempel di bawah ---
    if (mobile) {
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: appBar,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle("Ringkasan pesanan", theme, size: 17),
                  const SizedBox(height: 12),
                  ...cart.items
                      .map((item) => _buildSummaryItem(item, cart, theme)),
                  Divider(color: theme.borderColor, height: 24),
                  ..._totalRows(cart, theme, compact: true),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ..._paymentSection(cart, theme),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(top: BorderSide(color: theme.borderColor)),
            ),
            child: _confirmBtn(cart, theme),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: appBar,
      body: Row(
        children: [
          // SISI KIRI: RINGKASAN PESANAN
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: theme.borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle("Ringkasan pesanan", theme, size: 20),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.builder(
                      itemCount: cart.items.length,
                      itemBuilder: (context, index) =>
                          _buildSummaryItem(cart.items[index], cart, theme),
                    ),
                  ),
                  Divider(color: theme.borderColor, height: 32),
                  ..._totalRows(cart, theme),
                ],
              ),
            ),
          ),
// SISI KANAN: INFO PELANGGAN & PEMBAYARAN
          Expanded(
            flex: 4,
            child: Container(
              color: theme.cardColor,
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🔥 BUNGKUS DENGAN EXPANDED & SCROLL BIAR TIDAK OVERFLOW 🔥
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _paymentSection(cart, theme),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  // 🔥 TOMBOL KONFIRMASI TETAP DI BAWAH 🔥
                  _confirmBtn(cart, theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, ThemeProvider theme, {double size = 20}) {
    return Text(
      text,
      style: TextStyle(
        color: theme.textColor,
        fontSize: size,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  List<Widget> _totalRows(CartProvider cart, ThemeProvider theme,
      {bool compact = false}) {
    return [
      _priceRow("Subtotal", rupiah(cart.subtotalPrice), theme,
          compact: compact),
      _priceRow(
        cart.isBill ? "Pajak PB1" : "Pajak PB1 ${cart.taxPercentLabel}%",
        rupiah(cart.taxAmount),
        theme,
        compact: compact,
      ),
      if (cart.discountAmount > 0)
        _priceRow(
          cart.selectedDiscount != null
              ? "Diskon (${cart.selectedDiscount!.name})"
              : "Diskon",
          "- ${rupiah(cart.discountAmount)}",
          theme,
          color: theme.dangerColor,
          compact: compact,
        ),
      _priceRow(
        "Total",
        rupiah(cart.totalPrice),
        theme,
        isBold: true,
        color: theme.primaryColor,
        compact: compact,
      ),
    ];
  }

  // Info pelanggan, pilihan metode bayar, dan input uang tunai
  List<Widget> _paymentSection(CartProvider cart, ThemeProvider theme) {
    final int total = cart.totalPrice;
    final int change = _amountReceived > total ? _amountReceived - total : 0;
    final bool isDelivery = cart.orderType == 'delivery';
    final bool mobile = isMobile(context);

    return [
      _sectionTitle("Pelanggan", theme, size: mobile ? 18 : 20),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: mobile ? theme.cardColor : theme.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.borderColor),
        ),
        child: Wrap(
          spacing: 32,
          runSpacing: 12,
          children: [
            _infoTile("Nama", cart.customerName, theme),
            _infoTile(
              "Meja",
              cart.tableNumber.isEmpty ? "-" : cart.tableNumber,
              theme,
            ),
            _infoTile(
              "Jenis",
              const {'dine_in': 'Makan di sini', 'to_go': 'Bungkus', 'delivery': 'Ojol'}[cart.orderType] ?? cart.orderType,
              theme,
            ),
            if (isDelivery)
              _infoTile(
                "Aplikasi",
                platformLabel(cart.deliveryPlatform),
                theme,
              ),
          ],
        ),
      ),
      SizedBox(height: mobile ? 24 : 32),
      _sectionTitle("Cara bayar", theme, size: mobile ? 18 : 20),
      const SizedBox(height: 12),
      Wrap(
        spacing: mobile ? 8 : 12,
        runSpacing: mobile ? 8 : 12,
        children: [
          // Dibayar oleh platform ojol (masuk rekap Gojek/Grab/ShopeeFood)
          if (isDelivery)
            _paymentOption(
              cart,
              "delivery",
              Icons.motorcycle,
              theme,
              label: cart.deliveryPlatform.isEmpty
                  ? "Platform"
                  : platformLabel(cart.deliveryPlatform),
            ),
          _paymentOption(cart, "cash", Icons.payments_outlined, theme, label: "Tunai"),
          _paymentOption(cart, "qris", Icons.qr_code_2, theme, label: "QRIS"),
          _paymentOption(cart, "debit", Icons.credit_card, theme, label: "Debit"),
          _paymentOption(cart, "credit", Icons.credit_score, theme, label: "Kredit"),
        ],
      ),
      SizedBox(height: mobile ? 24 : 32),

      // TAMPILAN KHUSUS CASH
      if (cart.paymentMethod.toLowerCase() == "cash") ...[
        Text(
          "Uang diterima",
          style: TextStyle(
            color: theme.secondaryTextColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          rupiah(_amountReceived),
          style: TextStyle(
            color: theme.primaryColor,
            fontSize: mobile ? 28 : 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _exactBtn(total, theme),
            ..._denominations.map((val) => _denominationBtn(val, theme)),
            _clearBtn(theme),
          ],
        ),
        const SizedBox(height: 20),
        _priceRow(
          "Kembalian",
          rupiah(change),
          theme,
          isBold: true,
          color: theme.successColor,
          compact: mobile,
        ),
      ],
    ];
  }

  Widget _buildSummaryItem(
    CartItem item,
    CartProvider cart,
    ThemeProvider theme,
  ) {
    final int currentPrice = cart.priceOf(item.menu);
    final String note = item.note ?? "";

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.menu.name,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "x${item.quantity} (@ ${rupiah(currentPrice)})",
                  style: TextStyle(
                    color: theme.secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
                if (note.isNotEmpty)
                  Text(
                    note,
                    style: TextStyle(
                      color: theme.warningColor,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            rupiah(currentPrice * item.quantity),
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPERS ---
  Widget _infoTile(String label, String value, ThemeProvider theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: theme.secondaryTextColor, fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _paymentOption(
    CartProvider cart,
    String method,
    IconData icon,
    ThemeProvider theme, {
    String? label,
  }) {
    bool isSelected = cart.paymentMethod.toLowerCase() == method.toLowerCase();
    return GestureDetector(
      onTap: _isProcessing
          ? null
          : () {
              cart.setPaymentMethod(method);
              if (method.toLowerCase() != "cash") {
                setState(() => _amountReceived = 0);
              }
            },
      child: Container(
        // HP: 4 metode muat dalam satu baris
        width: isMobile(context) ? 74 : 100,
        height: isMobile(context) ? 72 : 80,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primarySoftColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.primaryColor : theme.borderColor,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? theme.primaryColor : theme.secondaryTextColor,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label ?? method,
              style: TextStyle(
                color: isSelected ? theme.textColor : theme.secondaryTextColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _denominationBtn(int val, ThemeProvider theme) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.cardColor,
        foregroundColor: theme.textColor,
        side: BorderSide(color: theme.borderColor),
      ),
      onPressed: () => setState(() => _amountReceived += val),
      child: Text("+${val ~/ 1000}k"),
    );
  }

  Widget _exactBtn(int total, ThemeProvider theme) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.primarySoftColor,
        foregroundColor: theme.primaryColor,
      ),
      onPressed: () => setState(() => _amountReceived = total),
      child: const Text("Uang pas"),
    );
  }

  Widget _clearBtn(ThemeProvider theme) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.dangerSoftColor,
        foregroundColor: theme.dangerColor,
      ),
      onPressed: () => setState(() => _amountReceived = 0),
      child: const Text("Hapus"),
    );
  }

  Widget _confirmBtn(CartProvider cart, ThemeProvider theme) {
    bool isCash = cart.paymentMethod.toLowerCase() == "cash";
    bool isShort = isCash && _amountReceived < cart.totalPrice;
    bool isDisabled = _isProcessing || isShort || cart.items.isEmpty;
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: isDisabled ? null : () => _handleConfirmPayment(cart),
        child: _isProcessing
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                isShort ? "Uang diterima kurang" : "Konfirmasi pembayaran",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Future<void> _handleConfirmPayment(CartProvider cart) async {
    setState(() => _isProcessing = true);
    final bool isCash = cart.paymentMethod.toLowerCase() == 'cash';

    try {
      Map<String, dynamic> response;

      if (widget.isFromBill && cart.currentOrderId != null) {
        response = await _apiService.payPendingBill(
          cart.currentOrderId!,
          cart.paymentMethod,
          isCash ? _amountReceived : null,
        );
      } else {
        response = await _apiService.saveTransaction(
          items: cart.items,
          paymentMethod: cart.paymentMethod,
          orderType: cart.orderType,
          deliveryPlatform: cart.deliveryPlatform,
          customerName: cart.customerName,
          tableNumber: cart.tableNumber,
          discountId: cart.selectedDiscount?.id,
          amountPaid: isCash ? _amountReceived : null,
        );
      }

      if (response['status'] != 'success') {
        throw Exception(response['message'] ?? "Pembayaran gagal diproses");
      }

      // Pembayaran sudah tercatat di server. Mulai dari sini kegagalan cetak
      // tidak boleh membuat transaksi terlihat gagal (bisa dobel input).
      bool printed = true;
      int changeAmount = 0;
      final order = response['data'];

      if (order is Map<String, dynamic>) {
        changeAmount = toInt(order['change_amount']);
        final printer = PrinterService();

        // Ceker dapur hanya untuk order baru; bill gantung sudah dicetak saat disimpan
        if (!widget.isFromBill) {
          printed = await printer.printKitchenOrder(order);
          await Future.delayed(const Duration(milliseconds: 1500));
        }
        printed = await printer.printCustomerCopy(order) && printed;
      }

      cart.clearCart();
      if (!mounted) return;
      _showSuccessDialog(
        Provider.of<ThemeProvider>(context, listen: false),
        isCash ? changeAmount : null,
        printed,
      );
    } catch (e) {
      if (!mounted) return;
      showMessage(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _priceRow(
    String label,
    String value,
    ThemeProvider theme, {
    bool isBold = false,
    Color? color,
    bool compact = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  color: theme.secondaryTextColor, fontSize: compact ? 14 : 16),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? theme.textColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? (compact ? 20 : 22) : (compact ? 15 : 18),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(ThemeProvider theme, int? change, bool printed) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Icon(
          Icons.check_circle,
          color: theme.successColor,
          size: 80,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Pembayaran berhasil",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (change != null) ...[
              const SizedBox(height: 12),
              Text(
                "Kembalian ${rupiah(change)}",
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (!printed) ...[
              const SizedBox(height: 12),
              Text(
                "Struk tidak tercetak karena printer belum terhubung. Cetak ulang dari menu Riwayat.",
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.warningColor, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: Text(
                widget.isFromBill ? "Kembali ke daftar bill" : "Kembali ke kasir",
                style: TextStyle(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
