import 'package:flutter/material.dart';
import '../models/menu_model.dart';
import '../models/discount_model.dart';
import '../utils/formatters.dart';

// --- CART ITEM MODEL ---
class CartItem {
  final MenuModel menu;
  int quantity;
  String? note;

  CartItem({
    required this.menu,
    this.quantity = 1,
    this.note,
  });
}

// --- CART PROVIDER ---
class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];

  int? _currentOrderId;
  int? get currentOrderId => _currentOrderId;

  String _customerName = "Pelanggan Umum";
  String _tableNumber = "";
  String _orderType = 'dine_in';
  String _deliveryPlatform = "";
  String _paymentMethod = 'cash';
  double _taxPercent = 10;

  DiscountModel? _selectedDiscount;

  // Saat melunasi bill gantung, angka mengikuti yang sudah tersimpan di server
  // (pajak/diskon dihitung saat bill dibuat), bukan dihitung ulang di aplikasi.
  Map<String, int>? _billTotals;

  // Mode "tambah pesanan ke bill": keranjang hanya berisi item tambahan
  // untuk bill [appendOrderId] (mis. meja yang pesan lagi).
  int? _appendOrderId;
  String _appendLabel = "";
  int? get appendOrderId => _appendOrderId;
  String get appendLabel => _appendLabel;
  bool get isAppending => _appendOrderId != null;

  /// Mulai menambah pesanan ke bill yang belum dibayar
  void startAppend(Map<String, dynamic> bill) {
    clearCart();
    _appendOrderId = bill['id'];
    _orderType = (bill['order_type'] ?? 'dine_in').toString();
    _deliveryPlatform = bill['delivery_platform']?.toString() ?? "";
    _tableNumber = bill['table_number']?.toString() ?? "";
    _customerName = bill['customer_name']?.toString() ?? "Pelanggan Umum";
    final String table = _tableNumber.isEmpty || _tableNumber == '-'
        ? ''
        : 'Meja $_tableNumber';
    _appendLabel = [table, if (_customerName != 'Pelanggan Umum') _customerName]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    if (_appendLabel.isEmpty) _appendLabel = bill['receipt_number'] ?? 'bill';
    notifyListeners();
  }

  // --- GETTER ---
  List<CartItem> get items => _items;
  String get customerName => _customerName;
  String get tableNumber => _tableNumber;
  String get orderType => _orderType;
  String get deliveryPlatform => _deliveryPlatform;
  String get paymentMethod => _paymentMethod;
  DiscountModel? get selectedDiscount => _selectedDiscount;
  bool get isBill => _billTotals != null;

  /// "10" atau "7.5"
  String get taxPercentLabel => _taxPercent == _taxPercent.roundToDouble()
      ? _taxPercent.toInt().toString()
      : _taxPercent.toString();

  // --- LOGIKA KERANJANG ---
  int quantityOf(int menuId) {
    int index = _items.indexWhere((item) => item.menu.id == menuId);
    return index >= 0 ? _items[index].quantity : 0;
  }

  void addToCart(MenuModel menu) {
    int index = _items.indexWhere((item) => item.menu.id == menu.id);
    if (index >= 0) {
      _items[index].quantity += 1;
    } else {
      _items.add(CartItem(menu: menu));
    }
    notifyListeners();
  }

  void decreaseQuantity(int menuId) {
    int index = _items.indexWhere((item) => item.menu.id == menuId);
    if (index >= 0) {
      if (_items[index].quantity > 1) {
        _items[index].quantity -= 1;
      } else {
        _items.removeAt(index);
      }
      notifyListeners();
    }
  }

  void removeFromCart(int menuId) {
    _items.removeWhere((item) => item.menu.id == menuId);
    notifyListeners();
  }

  void setNote(int menuId, String note) {
    int index = _items.indexWhere((item) => item.menu.id == menuId);
    if (index >= 0) {
      _items[index].note = note.isEmpty ? null : note;
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    _selectedDiscount = null;
    _currentOrderId = null;
    _billTotals = null;
    _appendOrderId = null;
    _appendLabel = "";
    _customerName = "Pelanggan Umum";
    _tableNumber = "";
    _orderType = 'dine_in';
    _deliveryPlatform = "";
    _paymentMethod = 'cash';
    notifyListeners();
  }

  // --- SETTER ---
  void setCustomerInfo(String name, String table) {
    _customerName = name.isEmpty ? "Pelanggan Umum" : name;
    _tableNumber = table;
    notifyListeners();
  }

  void setOrderType(String type, {String platform = ""}) {
    _orderType = type.toLowerCase();
    _deliveryPlatform = platform.toLowerCase();
    if (_orderType != 'delivery') {
      _deliveryPlatform = "";
    }
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method.toLowerCase();
    notifyListeners();
  }

  void setDiscount(DiscountModel? discount) {
    _selectedDiscount = discount;
    notifyListeners();
  }

  /// Tarif pajak dari Settings di server, supaya total di aplikasi = total di server
  void setTaxPercent(num percent) {
    if (percent < 0 || percent == _taxPercent) return;
    _taxPercent = percent.toDouble();
    notifyListeners();
  }

  // --- LOGIKA HARGA DINAMIS ---
  int priceOf(MenuModel menu) {
    if (_orderType == 'delivery') {
      return (menu.priceOnline > 0) ? menu.priceOnline : menu.price;
    } else {
      return (menu.priceDineIn > 0) ? menu.priceDineIn : menu.price;
    }
  }

  int get _itemsSubtotal {
    return _items.fold(
        0, (sum, item) => sum + (priceOf(item.menu) * item.quantity));
  }

  int get subtotalPrice => _billTotals?['subtotal'] ?? _itemsSubtotal;

  // Pembulatan disamakan dengan server (round), bukan dipotong (toInt)
  int get taxAmount =>
      _billTotals?['tax'] ?? (_itemsSubtotal * (_taxPercent / 100)).round();

  int get discountAmount {
    if (_billTotals != null) return _billTotals!['discount']!;
    if (_selectedDiscount == null) return 0;
    final int subtotal = _itemsSubtotal;
    final int discount = _selectedDiscount!.type == 'percentage'
        ? (subtotal * (_selectedDiscount!.value / 100)).round()
        : _selectedDiscount!.value;
    return discount > subtotal ? subtotal : discount;
  }

  int get totalPrice {
    if (_billTotals != null) return _billTotals!['total']!;
    int total = (subtotalPrice + taxAmount) - discountAmount;
    return total < 0 ? 0 : total;
  }

  // --- FUNGSI SINKRONISASI DARI BILL ---
  void loadBill(Map<String, dynamic> bill) {
    clearCart();

    _customerName = bill['customer_name']?.toString() ?? "Pelanggan Umum";
    _tableNumber = bill['table_number']?.toString() ?? "";
    _orderType = (bill['order_type'] ?? 'dine_in').toString().toLowerCase();
    _deliveryPlatform = bill['delivery_platform']?.toString() ?? "";
    _paymentMethod = _orderType == 'delivery' ? 'delivery' : 'cash';
    _currentOrderId = bill['id'];
    _billTotals = {
      'subtotal': toInt(bill['subtotal']),
      'tax': toInt(bill['tax_amount']),
      'discount': toInt(bill['discount_amount']),
      'total': toInt(bill['total_price']),
    };

    for (var item in (bill['items'] as List? ?? [])) {
      addManualItem({
        'id': item['menu_id'],
        'name': item['menu']?['name'],
        'price': item['price'],
        'qty': item['qty'],
        'note': item['note'],
        'image_url': item['menu']?['image_url'],
      });
    }
  }

  void addManualItem(Map<String, dynamic> data) {
    int price = toInt(data['price']);

    final menu = MenuModel(
      id: data['id'] ?? 0,
      categoryId: data['category_id'] ?? 0,
      name: data['name'] ?? 'Item Tanpa Nama',
      price: price,
      priceDineIn: price,
      priceOnline: price,
      image: data['image'] ?? "",
      imageUrl: data['image_url'] ?? "",
      stock: data['stock'] ?? 999,
      isAvailable: true,
    );

    final String note = data['note']?.toString() ?? "";

    _items.add(CartItem(
      menu: menu,
      quantity: toInt(data['qty']) < 1 ? 1 : toInt(data['qty']),
      note: note.isEmpty ? null : note,
    ));
    notifyListeners();
  }

  void setCurrentOrderId(int? id) {
    _currentOrderId = id;
    notifyListeners();
  }
}
