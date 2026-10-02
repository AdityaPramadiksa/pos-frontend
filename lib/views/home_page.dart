import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/cart_provider.dart';
import '../providers/theme_provider.dart';
import '../models/menu_model.dart';
import '../models/category_model.dart';
import '../models/discount_model.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';
import 'payment_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _nameController = TextEditingController(
    text: "Pelanggan Umum",
  );
  final TextEditingController _tableController = TextEditingController();

  List<CategoryModel> _categories = [];
  List<MenuModel> _allMenus = [];
  int _selectedCategoryId = 0;
  bool _isLoading = true;
  bool _isSavingBill = false;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cart = Provider.of<CartProvider>(context, listen: false);
      // Sisa bill yang batal dilunasi tidak boleh ikut jadi order baru
      if (cart.isBill) cart.clearCart();
      _syncInputsFromCart();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tableController.dispose();
    super.dispose();
  }

  // Samakan kolom nama & meja dengan isi keranjang (mis. setelah keranjang dikosongkan)
  void _syncInputsFromCart() {
    final cart = Provider.of<CartProvider>(context, listen: false);
    _nameController.text = cart.customerName;
    _tableController.text = cart.tableNumber;
  }

  void _showSnack(String message, {Color color = Colors.redAccent}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Tambah ke keranjang dengan batas stok
  void _addMenu(CartProvider cart, MenuModel menu) {
    if (cart.quantityOf(menu.id) >= menu.stock) {
      _showSnack(menu.stock <= 0
          ? "Stok ${menu.name} habis"
          : "Stok ${menu.name} tersisa ${menu.stock}");
      return;
    }
    cart.addToCart(menu);
  }

  Future<void> _loadData() async {
    try {
      final cats = await _apiService.getCategories();
      final items = await _apiService.getMenus();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _allMenus = items;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<MenuModel> get _filteredMenus {
    List<MenuModel> filtered = _allMenus;
    if (_selectedCategoryId != 0) {
      filtered =
          filtered.where((m) => m.categoryId == _selectedCategoryId).toList();
    }
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (m) => m.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }
    return filtered;
  }

  void _showDiscountPicker(CartProvider cart, ThemeProvider theme) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: theme.primaryColor)),
    );
    final List<DiscountModel> discounts = await _apiService.getDiscounts();

    if (!mounted) return;
    Navigator.pop(context); // Tutup loading

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Available Discounts",
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            if (discounts.isEmpty)
              Text(
                "No active discounts",
                style: TextStyle(color: theme.secondaryTextColor),
              ),
            ...discounts.map(
              (d) => ListTile(
                leading: Icon(Icons.local_offer, color: theme.primaryColor),
                title: Text(
                  d.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  d.type == 'percentage'
                      ? "${d.value}% Off"
                      : "Rp ${d.value} Off",
                  style: TextStyle(color: theme.secondaryTextColor),
                ),
                onTap: () {
                  cart.setDiscount(d);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeliveryPicker(CartProvider cart, ThemeProvider theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Select Delivery Platform",
              style: TextStyle(
                color: theme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _platformTile(
              "Gojek / GoFood",
              "gojek",
              Icons.motorcycle,
              Colors.green,
              cart,
            ),
            _platformTile(
              "Grab / GrabFood",
              "grab",
              Icons.directions_car,
              Colors.greenAccent,
              cart,
            ),
            _platformTile(
              "ShopeeFood",
              "shopee",
              Icons.fastfood,
              Colors.orange,
              cart,
            ),
          ],
        ),
      ),
    );
  }

  Widget _platformTile(
    String label,
    String value,
    IconData icon,
    Color color,
    CartProvider cart,
  ) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        _tableController.clear(); // Bersihkan meja jika delivery
        cart.setOrderType("delivery", platform: value);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: Row(
        children: [
          // SISI KIRI (MENU) - Turunkan flex dikit biar kanan lega
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 25),
                  _buildCategoryTabs(theme),
                  const SizedBox(height: 25),
                  Text(
                    "Choose Dishes",
                    style: TextStyle(
                        color: theme.textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _isLoading
                        ? Center(
                            child: CircularProgressIndicator(
                                color: theme.primaryColor))
                        : _buildMenuGrid(cart, theme),
                  ),
                ],
              ),
            ),
          ),

          // SISI KANAN (SIDEBAR ORDER) - Naikkan flex ke 2 (atau 3 jika masih kurang lebar)
          Expanded(
            flex: 2,
            child: _buildOrderSidebar(cart, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSidebar(CartProvider cart, ThemeProvider theme) {
    return Container(
      // Kita hapus width: 400 agar dia mengikuti jatah flex dari Expanded di atas
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(left: BorderSide(color: theme.borderColor)),
      ),
      padding: const EdgeInsets.all(20), // Kurangi padding dikit biar lega
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Current Order",
            style: TextStyle(
                color: theme.textColor,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // 1. INPUT NAMA & MEJA
          Row(
            children: [
              Expanded(
                child: _sidebarInput(_nameController, "Customer",
                    Icons.person_outline, theme, cart),
              ),
              if (cart.orderType == 'dine_in') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _sidebarInput(_tableController, "Table",
                      Icons.table_restaurant_outlined, theme, cart),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // 2. TOMBOL TIPE ORDER (Bungkus Expanded biar GAK OVERFLOW)
          Row(
            children: [
              Expanded(child: _typeBtn(cart, "Dine In", "dine_in", theme)),
              const SizedBox(width: 4),
              Expanded(child: _typeBtn(cart, "To Go", "to_go", theme)),
              const SizedBox(width: 4),
              Expanded(child: _deliveryBtn(cart, theme)),
            ],
          ),

          if (cart.orderType == 'delivery')
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                "Platform: ${cart.deliveryPlatform.toUpperCase()}",
                style: TextStyle(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11),
              ),
            ),

          const Divider(color: Color(0xFF393C49), height: 30),

          // --- 🔥 3. AREA DAFTAR ITEM (LIST KERANJANG) 🔥 ---
          Expanded(
            child: cart.items.isEmpty
                ? const Center(
                    child: Text("Cart is empty",
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) =>
                        _buildCartItem(cart.items[index], cart, theme),
                  ),
          ),

          const Divider(color: Color(0xFF393C49), height: 30),

          // 4. RINGKASAN HARGA
          _priceRow("Subtotal", rupiah(cart.subtotalPrice), theme),
          _priceRow(
              "Tax (${cart.taxPercentLabel}%)", rupiah(cart.taxAmount), theme),

          GestureDetector(
            onTap: () => _showDiscountPicker(cart, theme),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(cart.selectedDiscount?.name ?? "Add Discount",
                    style: TextStyle(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                if (cart.selectedDiscount == null)
                  Icon(Icons.arrow_forward_ios,
                      color: theme.primaryColor, size: 12)
                else
                  Row(
                    children: [
                      Text("- ${rupiah(cart.discountAmount)}",
                          style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(width: 8),
                      // Hapus diskon yang sudah dipilih
                      GestureDetector(
                        onTap: () => cart.setDiscount(null),
                        child: const Icon(Icons.close,
                            color: Colors.redAccent, size: 16),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          _priceRow("Total", rupiah(cart.totalPrice), theme,
              isBold: true, color: theme.primaryColor),
          const SizedBox(height: 15),

          // 5. TOMBOL ACTIONS
          if (cart.items.isNotEmpty) ...[
            if (cart.orderType == 'dine_in') ...[
              SizedBox(
                width: double.infinity,
                height: 45,
                child: OutlinedButton(
                  onPressed: _isSavingBill
                      ? null
                      : () => _handleSaveAsBill(cart),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.primaryColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text("Save as Bill",
                      style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  if (cart.orderType == 'dine_in' &&
                      _tableController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Isi nomor meja!")));
                    return;
                  }

                  if (cart.orderType == 'delivery' &&
                      cart.deliveryPlatform.isEmpty) {
                    _showDeliveryPicker(cart, theme);
                    return;
                  }

                  // A. Set info customer ke provider
                  cart.setCustomerInfo(
                      _nameController.text, _tableController.text);

                  // B. Pindah ke halaman pembayaran. Ceker dapur dicetak di sana
                  //    setelah pembayaran berhasil, supaya tidak tercetak dobel
                  //    kalau kasir bolak-balik ke halaman ini.
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PaymentPage()));

                  // C. Sinkronkan input & stok setelah kembali dari pembayaran
                  if (!mounted) return;
                  _syncInputsFromCart();
                  _loadData();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Confirm Payment",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deliveryBtn(CartProvider cart, ThemeProvider theme) {
    bool isSelected = cart.orderType == 'delivery';
    return GestureDetector(
      onTap: () => _showDeliveryPicker(cart, theme),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.transparent : theme.borderColor,
          ),
        ),
        child: Text(
          "Delivery",
          style: TextStyle(
            color: isSelected ? Colors.white : theme.primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _sidebarInput(
    TextEditingController controller,
    String hint,
    IconData icon,
    ThemeProvider theme,
    CartProvider cart,
  ) {
    return TextField(
      controller: controller,
      onChanged: (v) =>
          cart.setCustomerInfo(_nameController.text, _tableController.text),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: theme.secondaryTextColor),
        hintStyle: TextStyle(color: theme.secondaryTextColor),
        filled: true,
        fillColor: theme.backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, ThemeProvider theme, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.borderColor),
        ),
        child: Icon(icon, size: 14, color: theme.primaryColor),
      ),
    );
  }

  Widget _buildCartItem(CartItem item, CartProvider cart, ThemeProvider theme) {
    int currentPrice = cart.priceOf(item.menu);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              // 1. Nama Item & Note (Flex 4 agar teks punya ruang)
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.menu.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (item.note != null && item.note!.isNotEmpty)
                      Text(
                        "* ${item.note}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),

              // 2. Jumlah Qty dengan tombol kurang / tambah
              _qtyBtn(Icons.remove, theme,
                  () => cart.decreaseQuantity(item.menu.id)),
              SizedBox(
                width: 28,
                child: Text(
                  "${item.quantity}",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
              _qtyBtn(Icons.add, theme, () => _addMenu(cart, item.menu)),

              // 3. Harga Total (Flex 3 agar muat angka jutaan)
              Expanded(
                flex: 3,
                child: Text(
                  rupiah(currentPrice * item.quantity),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 4. TOMBOL AKSI (Sejajar dalam satu baris)
              // Tombol Note
              IconButton(
                onPressed: () => _showNoteDialog(item, cart, theme),
                icon:
                    Icon(Icons.edit_note, color: theme.primaryColor, size: 20),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              // Tombol Hapus (seluruh item)
              IconButton(
                onPressed: () => cart.removeFromCart(item.menu.id),
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 18),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: theme.borderColor.withOpacity(0.3), height: 1),
        ],
      ),
    );
  }

  // 🔥 FUNGSI BARU UNTUK NAMPILIN POP-UP CATATAN
  void _showNoteDialog(CartItem item, CartProvider cart, ThemeProvider theme) {
    // Isi controller dengan note yang sudah ada (jika mau diedit)
    TextEditingController noteController = TextEditingController(
      text: item.note ?? "",
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            "Add Note - ${item.menu.name}",
            style: TextStyle(color: theme.textColor, fontSize: 18),
          ),
          content: TextField(
            controller: noteController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "e.g., Pedas, pisah kuah...",
              hintStyle: TextStyle(color: theme.secondaryTextColor),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.borderColor),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.primaryColor),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "Cancel",
                style: TextStyle(color: theme.secondaryTextColor),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
              ),
              onPressed: () {
                // Simpan note ke CartProvider
                cart.setNote(item.menu.id, noteController.text);
                Navigator.pop(context);
              },
              child: const Text(
                "Save",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(ThemeProvider theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 1. Bungkus Judul dengan Expanded agar teks tidak mendorong Search Bar keluar layar
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Babi Guling POS",
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
                style: TextStyle(color: theme.secondaryTextColor, fontSize: 16),
              ),
            ],
          ),
        ),

        const SizedBox(width: 16), // Jarak antara judul dan search bar

        // 2. Ganti Container statis (300) menjadi Expanded agar fleksibel
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.borderColor),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(color: theme.textColor),
              decoration: InputDecoration(
                icon: Icon(Icons.search, color: theme.secondaryTextColor),
                hintText: "Search dishes...",
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryTabs(ThemeProvider theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _categoryTab(0, "All Dishes", theme),
          ..._categories
              .map((cat) => _categoryTab(cat.id, cat.name, theme))
              .toList(),
        ],
      ),
    );
  }

  Widget _categoryTab(int id, String label, ThemeProvider theme) {
    bool isSelected = _selectedCategoryId == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategoryId = id),
      child: Container(
        margin: const EdgeInsets.only(right: 30),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected ? theme.primaryColor : theme.secondaryTextColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(top: 8),
                height: 3,
                width: 30,
                color: theme.primaryColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuGrid(CartProvider cart, ThemeProvider theme) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.75,
        crossAxisSpacing: 25,
        mainAxisSpacing: 25,
      ),
      itemCount: _filteredMenus.length,
      itemBuilder: (context, index) {
        final menu = _filteredMenus[index];
        // Harga menyesuaikan orderType dinamis dari CartProvider
        int displayPrice = cart.priceOf(menu);
        final bool isSoldOut = menu.stock <= 0;
        final int inCart = cart.quantityOf(menu.id);

        return GestureDetector(
          onTap: () => _addMenu(cart, menu),
          child: Opacity(
            opacity: isSoldOut ? 0.45 : 1,
            child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.borderColor),
            ),
            child: Column(
              children: [
                // ... di dalam Column
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Builder(
                      builder: (context) {
                        // 1. Ambil nama file-nya saja secara otomatis (misal "menus/jus.jpg" jadi "jus.jpg")
                        String filename = menu.imageUrl.split('/').last;

                        // 2. Gabungkan dengan baseUrl dari ApiService + jalur VIP
                        // Hasilnya: "http://192.168.18.8:8000/api/menu-image/jus.jpg"
                        String finalUrl =
                            "${ApiService.baseUrl}/menu-image/$filename";

                        return Image.network(
                          finalUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[900],
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.white24,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  menu.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  rupiah(displayPrice),
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isSoldOut
                      ? "HABIS"
                      : "Stok ${menu.stock}${inCart > 0 ? '  |  di keranjang $inCart' : ''}",
                  style: TextStyle(
                    color: isSoldOut
                        ? Colors.redAccent
                        : theme.secondaryTextColor,
                    fontSize: 11,
                    fontWeight:
                        isSoldOut ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  Widget _typeBtn(
    CartProvider cart,
    String label,
    String value,
    ThemeProvider theme,
  ) {
    bool isSelected = cart.orderType == value;
    return GestureDetector(
      onTap: () {
        if (value != 'dine_in') {
          _tableController.clear(); // Hapus no meja jika pilih To Go
        }
        cart.setOrderType(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.transparent : theme.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : theme.primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _priceRow(
    String label,
    String value,
    ThemeProvider theme, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.secondaryTextColor)),
          Text(
            value,
            style: TextStyle(
              color: color ?? theme.textColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 18 : 16,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSaveAsBill(CartProvider cart) async {
    if (_tableController.text.trim().isEmpty) {
      _showSnack("Isi nomor meja!");
      return;
    }
    cart.setCustomerInfo(_nameController.text, _tableController.text.trim());

    setState(() => _isSavingBill = true);

    final res = await _apiService.saveTransaction(
      items: cart.items,
      orderType: cart.orderType,
      customerName: cart.customerName,
      tableNumber: cart.tableNumber,
      discountId: cart.selectedDiscount?.id,
      isPending: true,
    );

    if (!mounted) return;
    setState(() => _isSavingBill = false);

    if (res['status'] != 'success') {
      _showSnack(res['message'] ?? "Gagal menyimpan bill");
      return;
    }

    // Pesanan gantung langsung dikirim ke dapur
    bool printed = false;
    if (res['data'] is Map<String, dynamic>) {
      printed = await PrinterService().printKitchenOrder(res['data']);
    }

    cart.clearCart();
    if (!mounted) return;
    _syncInputsFromCart();
    _loadData();
    _showSnack(
      printed
          ? "Pesanan berhasil digantung & ceker dapur dicetak"
          : "Pesanan digantung, tapi ceker dapur TIDAK tercetak (cek printer)",
      color: printed ? Colors.green : Colors.orange,
    );
  }
}
