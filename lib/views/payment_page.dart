import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';

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
    final int total = cart.totalPrice;
    final int change = _amountReceived > total ? _amountReceived - total : 0;
    final bool isDelivery = cart.orderType == 'delivery';

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: theme.textColor,
            size: 20,
          ),
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
        ),
        title: Text(
          widget.isFromBill ? "Pelunasan Bill" : "Confirmation & Payment",
          style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        elevation: 0,
      ),
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
                  Text(
                    "Order Summary",
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.builder(
                      itemCount: cart.items.length,
                      itemBuilder: (context, index) =>
                          _buildSummaryItem(cart.items[index], cart, theme),
                    ),
                  ),
                  Divider(color: theme.borderColor, height: 32),
                  _priceRow("Subtotal", rupiah(cart.subtotalPrice), theme),
                  _priceRow(
                    cart.isBill ? "Tax" : "Tax (${cart.taxPercentLabel}%)",
                    rupiah(cart.taxAmount),
                    theme,
                  ),
                  if (cart.discountAmount > 0)
                    _priceRow(
                      cart.selectedDiscount != null
                          ? "Discount (${cart.selectedDiscount!.name})"
                          : "Discount",
                      "- ${rupiah(cart.discountAmount)}",
                      theme,
                      color: Colors.redAccent,
                    ),
                  _priceRow(
                    "Total",
                    rupiah(total),
                    theme,
                    isBold: true,
                    color: theme.primaryColor,
                  ),
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
                        children: [
                          Text(
                            "Customer Info",
                            style: TextStyle(
                              color: theme.textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.borderColor),
                            ),
                            child: Wrap(
                              spacing: 32,
                              runSpacing: 12,
                              children: [
                                _infoTile("Customer", cart.customerName, theme),
                                _infoTile(
                                  "Table",
                                  cart.tableNumber.isEmpty
                                      ? "-"
                                      : cart.tableNumber,
                                  theme,
                                ),
                                _infoTile(
                                  "Type",
                                  cart.orderType
                                      .replaceAll('_', ' ')
                                      .toUpperCase(),
                                  theme,
                                ),
                                if (isDelivery)
                                  _infoTile(
                                    "Platform",
                                    platformLabel(cart.deliveryPlatform),
                                    theme,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            "Payment Method",
                            style: TextStyle(
                              color: theme.textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
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
                                      : cart.deliveryPlatform.toUpperCase(),
                                ),
                              _paymentOption(
                                  cart, "Cash", Icons.payments_outlined, theme),
                              _paymentOption(
                                  cart, "QRIS", Icons.qr_code_scanner, theme),
                              _paymentOption(
                                  cart, "Debit", Icons.credit_card, theme),
                              _paymentOption(
                                  cart, "Credit", Icons.credit_score, theme),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // TAMPILAN KHUSUS CASH
                          if (cart.paymentMethod.toLowerCase() == "cash") ...[
                            Text(
                              "Amount Received",
                              style: TextStyle(
                                color: theme.secondaryTextColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              rupiah(_amountReceived),
                              style: TextStyle(
                                color: theme.primaryColor,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _exactBtn(total, theme),
                                ..._denominations
                                    .map((val) => _denominationBtn(val, theme)),
                                _clearBtn(theme),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _priceRow(
                              "Change",
                              rupiah(change),
                              theme,
                              isBold: true,
                              color: Colors.greenAccent,
                            ),
                          ],
                        ],
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
                    "* $note",
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
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
        width: 100,
        height: 80,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryColor.withAlpha(40)
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
        backgroundColor: theme.primaryColor.withAlpha(40),
        foregroundColor: theme.primaryColor,
      ),
      onPressed: () => setState(() => _amountReceived = total),
      child: const Text("Uang Pas"),
    );
  }

  Widget _clearBtn(ThemeProvider theme) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.withAlpha(40),
        foregroundColor: Colors.redAccent,
      ),
      onPressed: () => setState(() => _amountReceived = 0),
      child: const Text("Clear"),
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
                isShort ? "Uang Kurang" : "Confirm Payment",
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
        throw Exception(response['message'] ?? "Gagal memproses pembayaran");
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: theme.secondaryTextColor, fontSize: 16),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? theme.textColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 22 : 18,
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
        title: const Icon(
          Icons.check_circle,
          color: Colors.greenAccent,
          size: 80,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Payment Successful!",
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
                "Kembalian: ${rupiah(change)}",
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (!printed) ...[
              const SizedBox(height: 12),
              const Text(
                "Struk tidak tercetak (printer belum terhubung).\nCetak ulang dari menu Riwayat.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
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
                "Back to Home",
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
