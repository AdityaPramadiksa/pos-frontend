import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/cart_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/theme_provider.dart';
import '../models/menu_model.dart';
import '../models/category_model.dart';
import '../models/discount_model.dart';
import '../services/pos_service.dart';
import '../services/sync_service.dart';
import '../services/app_settings.dart';
import '../services/printer_service.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/ui.dart';
import 'payment_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PosService _pos = PosService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _tableController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  // Konteks lembar pesanan versi HP selagi terbuka (untuk snackbar & menutupnya)
  BuildContext? _sheetContext;

  List<CategoryModel> _categories = [];
  List<MenuModel> _allMenus = [];
  int _selectedCategoryId = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _syncedTick = SyncService().syncedTick;
    SyncService().addListener(_onSync);
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cart = Provider.of<CartProvider>(context, listen: false);
      // Sisa bill yang batal dilunasi tidak boleh ikut jadi pesanan baru
      if (cart.isBill) cart.clearCart();
      _syncInputsFromCart();
    });
  }

  @override
  void dispose() {
    SyncService().removeListener(_onSync);
    _nameController.dispose();
    _tableController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Setelah transaksi offline terkirim, stok di server sudah terbaru
  int _syncedTick = 0;
  void _onSync() {
    if (SyncService().syncedTick == _syncedTick) return;
    _syncedTick = SyncService().syncedTick;
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    final cats = await _pos.categories();
    final items = await _pos.menus();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _allMenus = items;
      _isLoading = false;
    });
  }

  // Samakan kolom nama & meja dengan isi keranjang (mis. setelah dikosongkan)
  void _syncInputsFromCart() {
    final cart = Provider.of<CartProvider>(context, listen: false);
    _nameController.text =
        cart.customerName == 'Pelanggan Umum' ? '' : cart.customerName;
    _tableController.text = cart.tableNumber == '-' ? '' : cart.tableNumber;
  }

  void _applyInputs(CartProvider cart) {
    cart.setCustomerInfo(
        _nameController.text.trim(), _tableController.text.trim());
  }

  void _showSnack(String message, {bool error = true, bool success = false}) {
    if (!mounted) return;
    final BuildContext target =
        (_sheetContext != null && _sheetContext!.mounted)
            ? _sheetContext!
            : context;
    showMessage(target, message, error: error && !success, success: success);
  }

  List<MenuModel> get _filteredMenus {
    Iterable<MenuModel> filtered = _allMenus;
    if (_selectedCategoryId != 0) {
      filtered = filtered.where((m) => m.categoryId == _selectedCategoryId);
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((m) => m.name.toLowerCase().contains(q));
    }
    return filtered.toList();
  }

  // Tambah ke keranjang dengan batas stok
  void _addMenu(CartProvider cart, MenuModel menu) {
    if (cart.quantityOf(menu.id) >= menu.stock) {
      _showSnack(menu.stock <= 0
          ? "${menu.name} habis. Ketuk label stok untuk mengisi ulang."
          : "Stok ${menu.name} tinggal ${menu.stock} porsi.");
      return;
    }
    cart.addToCart(menu);
  }

  // ===================== UBAH STOK DARI KASIR =====================

  void _showStockSheet(MenuModel menu) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    final controller = TextEditingController(
        text: menu.stock > 0 ? menu.stock.toString() : '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          Future<void> save(int stock) async {
            setSheet(() => saving = true);
            final res = await _pos.updateStock(menu, stock);
            if (!sheetContext.mounted) return;
            setSheet(() => saving = false);
            if (res['status'] == 'success') {
              Navigator.pop(sheetContext);
              await _loadData();
              _showSnack(res['message'] ?? "Stok diperbarui", success: true);
            } else {
              showMessage(sheetContext, res['message'] ?? "Stok gagal disimpan",
                  error: true);
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20,
                20 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Stok ${menu.name}",
                    style: TextStyle(
                        color: theme.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  menu.stock > 0
                      ? "Sisa sekarang ${menu.stock} porsi. Isi jumlah porsi yang masih tersedia."
                      : "Menu ini sedang habis. Isi jumlah porsi bila sudah tersedia lagi.",
                  style: TextStyle(color: theme.secondaryTextColor),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: "Sisa porsi",
                    suffixText: "porsi",
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.dangerColor,
                        ),
                        onPressed: saving || menu.stock <= 0
                            ? null
                            : () => save(0),
                        child: const Text("Tandai habis"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () {
                                final int? stock =
                                    int.tryParse(controller.text);
                                if (stock == null) {
                                  showMessage(sheetContext,
                                      "Isi jumlah porsi dulu.",
                                      error: true);
                                  return;
                                }
                                save(stock);
                              },
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text("Simpan stok"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ===================== PEMILIH =====================

  void _showDiscountPicker(CartProvider cart) async {
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    final List<DiscountModel> discounts = await _pos.discounts();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text("Pilih diskon",
                  style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 17)),
            ),
            if (discounts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text("Belum ada diskon aktif. Diskon dibuat di panel admin.",
                    style: TextStyle(color: theme.secondaryTextColor)),
              ),
            ...discounts.map(
              (d) => ListTile(
                leading: Icon(Icons.local_offer_outlined,
                    color: theme.primaryColor),
                title: Text(d.name, style: TextStyle(color: theme.textColor)),
                subtitle: Text(
                  d.type == 'percentage'
                      ? "Potongan ${d.value}%"
                      : "Potongan ${rupiah(d.value)}",
                  style: TextStyle(color: theme.secondaryTextColor),
                ),
                trailing: cart.selectedDiscount?.id == d.id
                    ? Icon(Icons.check, color: theme.primaryColor)
                    : null,
                onTap: () {
                  cart.setDiscount(d);
                  Navigator.pop(sheetContext);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeliveryPicker(CartProvider cart) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        Widget tile(String label, String value) => ListTile(
              leading: Icon(Icons.delivery_dining_outlined,
                  color: theme.primaryColor),
              title: Text(label, style: TextStyle(color: theme.textColor)),
              trailing: cart.deliveryPlatform == value
                  ? Icon(Icons.check, color: theme.primaryColor)
                  : null,
              onTap: () {
                _tableController.clear();
                cart.setOrderType("delivery", platform: value);
                Navigator.pop(sheetContext);
              },
            );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text("Pesanan dari aplikasi apa?",
                    style: TextStyle(
                        color: theme.textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ),
              tile("GoFood", "gojek"),
              tile("GrabFood", "grab"),
              tile("ShopeeFood", "shopee"),
            ],
          ),
        );
      },
    );
  }

  void _showNoteDialog(CartItem item, CartProvider cart) {
    final controller = TextEditingController(text: item.note ?? "");
    const List<String> quick = [
      "Pedas",
      "Tidak pedas",
      "Kulit dipisah",
      "Tanpa lawar",
      "Nasi sedikit",
    ];

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Catatan ${item.menu.name}"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration:
                    const InputDecoration(hintText: "Contoh: pedas, kulit dipisah"),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: quick
                    .map((q) => ActionChip(
                          label: Text(q),
                          onPressed: () {
                            final current = controller.text.trim();
                            controller.text =
                                current.isEmpty ? q : "$current, $q";
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () {
              cart.setNote(item.menu.id, controller.text.trim());
              Navigator.pop(dialogContext);
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  // ===================== AKSI PESANAN =====================

  Future<void> _goToPayment(CartProvider cart) async {
    if (cart.orderType == 'dine_in' && _tableController.text.trim().isEmpty) {
      _showSnack("Isi nomor meja dulu.");
      return;
    }
    if (cart.orderType == 'delivery' && cart.deliveryPlatform.isEmpty) {
      _showDeliveryPicker(cart);
      return;
    }

    _applyInputs(cart);
    // Ceker dapur dicetak di halaman pembayaran setelah pembayaran berhasil,
    // supaya tidak dobel kalau kasir bolak-balik.
    _closeMobileCart();
    await Navigator.push(
        context, MaterialPageRoute(builder: (context) => const PaymentPage()));

    if (!mounted) return;
    _syncInputsFromCart();
    _loadData();
  }

  Future<void> _handleSaveAsBill(CartProvider cart) async {
    if (_isSubmitting) return; // cegah bill dobel karena tombol ditekan 2x
    if (_tableController.text.trim().isEmpty) {
      _showSnack("Isi nomor meja dulu.");
      return;
    }
    _applyInputs(cart);
    setState(() => _isSubmitting = true);

    final res = await _pos.createOrder(cart, pending: true);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['status'] != 'success') {
      _showSnack(res['message'] ?? "Bill gagal disimpan.");
      return;
    }

    // Pesanan yang disimpan sebagai bill langsung dikirim ke dapur
    bool printed = false;
    if (res['data'] is Map<String, dynamic>) {
      printed = await PrinterService().printKitchenOrder(res['data']);
    }

    final String table = cart.tableNumber;
    final String offline =
        res['queued'] == true ? " (offline, dikirim saat online)" : "";
    cart.clearCart();
    if (!mounted) return;
    _closeMobileCart();
    _syncInputsFromCart();
    _loadData();
    _showSnack(
      printed
          ? "Bill meja $table disimpan$offline, ceker dapur dicetak."
          : "Bill meja $table disimpan$offline, tapi ceker dapur tidak tercetak. Periksa printer.",
      success: printed,
      error: !printed,
    );
  }

  /// Tambah item di keranjang ke bill yang belum dibayar
  Future<void> _handleAppendToBill(CartProvider cart) async {
    if (_isSubmitting || cart.appendBill == null) return;
    setState(() => _isSubmitting = true);

    final res = await _pos.addItemsToBill(cart.appendBill!, cart);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['status'] != 'success') {
      _showSnack(res['message'] ?? "Pesanan gagal ditambahkan.");
      return;
    }

    // Ceker dapur hanya untuk item tambahan
    bool printed = false;
    final data = res['data'];
    if (data is Map<String, dynamic>) {
      printed = await PrinterService().printKitchenOrder({
        ...data,
        'items': data['new_items'] ?? const [],
        'kitchen_title': 'TAMBAHAN',
      });
    }

    final String label = cart.appendLabel;
    cart.clearCart();
    if (!mounted) return;
    _closeMobileCart();
    _syncInputsFromCart();
    _loadData();
    _showSnack(
      printed
          ? "Pesanan ditambahkan ke $label. Total bill sekarang ${rupiah(data['total_price'])}."
          : "Pesanan ditambahkan ke $label, tapi ceker dapur tidak tercetak.",
      success: printed,
      error: !printed,
    );
    Provider.of<NavProvider>(context, listen: false).goTo(NavProvider.bills);
  }

  // ===================== BUILD =====================

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final theme = Provider.of<ThemeProvider>(context);

    if (isMobile(context)) return _buildMobile(cart, theme);

    final double panelWidth =
        (MediaQuery.sizeOf(context).width * 0.3).clamp(340.0, 420.0);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 16),
                  _buildCategoryChips(theme),
                  const SizedBox(height: 16),
                  Expanded(child: _menuArea(cart, theme)),
                ],
              ),
            ),
          ),
          SizedBox(width: panelWidth, child: _buildOrderPanel(cart, theme)),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeProvider theme) {
    return Row(
      children: [
        Expanded(
          child: PageHeader(
            title: "Pesanan baru",
            subtitle:
                "${DateFormat('EEEE, d MMM · HH:mm', 'id').format(DateTime.now())}  ·  Ketuk label stok untuk mengubah stok",
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(width: 300, child: _searchField(theme)),
      ],
    );
  }

  Widget _searchField(ThemeProvider theme) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _searchQuery = v),
      textInputAction: TextInputAction.search,
      style: TextStyle(color: theme.textColor),
      decoration: InputDecoration(
        hintText: "Cari menu",
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: "Hapus pencarian",
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = "");
                },
              ),
      ),
    );
  }

  Widget _buildCategoryChips(ThemeProvider theme) {
    Widget chip(int id, String label) {
      final bool selected = _selectedCategoryId == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? theme.inkColor : theme.cardColor,
          shape: StadiumBorder(
            side: BorderSide(
                color: selected ? theme.inkColor : theme.fieldBorderColor),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _selectedCategoryId = id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? theme.onInkColor : theme.textColor,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(0, "Semua"),
          for (final cat in _categories) chip(cat.id, cat.name),
        ],
      ),
    );
  }

  Widget _menuArea(CartProvider cart, ThemeProvider theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      color: theme.primaryColor,
      child: _buildMenuGrid(cart, theme),
    );
  }

  Widget _buildMenuGrid(CartProvider cart, ThemeProvider theme) {
    final bool mobile = isMobile(context);
    final menus = _filteredMenus;
    if (menus.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.restaurant_menu,
              size: 40, color: theme.placeholderIconColor),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isEmpty
                ? "Belum ada menu. Tambahkan menu di panel admin."
                : "Tidak ada menu bernama \"$_searchQuery\".",
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.secondaryTextColor),
          ),
        ],
      );
    }

    final int threshold = AppSettings().lowStockThreshold;

    // Jumlah kolom menyesuaikan lebar layar: 2 di HP, 3-5 di tablet
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 20),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:
              (constraints.maxWidth / (mobile ? 170 : 200)).floor().clamp(2, 6),
          mainAxisExtent: mobile ? 214 : 232,
          crossAxisSpacing: mobile ? 10 : 12,
          mainAxisSpacing: mobile ? 10 : 12,
        ),
        itemCount: menus.length,
        itemBuilder: (context, index) =>
            _menuCard(menus[index], cart, theme, threshold),
      ),
    );
  }

  Widget _menuCard(
      MenuModel menu, CartProvider cart, ThemeProvider theme, int threshold) {
    final bool soldOut = menu.stock <= 0;
    final bool low = !soldOut && menu.stock <= threshold;
    final int inCart = cart.quantityOf(menu.id);

    final String stockLabel =
        soldOut ? "Habis" : (low ? "Sisa ${menu.stock}" : "${menu.stock} porsi");
    final Color stockColor = soldOut
        ? theme.dangerColor
        : (low ? theme.warningColor : theme.secondaryTextColor);

    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: inCart > 0 ? theme.primaryColor : theme.borderColor,
          width: inCart > 0 ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _addMenu(cart, menu),
        onLongPress: () => _showStockSheet(menu),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: soldOut ? 0.45 : 1,
                      child: MenuPhoto(menu: menu, radius: 8),
                    ),
                    if (inCart > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text("$inCart",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                menu.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: soldOut ? theme.secondaryTextColor : theme.textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rupiah(cart.priceOf(menu)),
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  // Label stok bisa diketuk untuk mengubah stok / tandai habis
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _showStockSheet(menu),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text(
                        stockLabel,
                        style: TextStyle(
                          color: stockColor,
                          fontSize: 12,
                          fontWeight: soldOut || low
                              ? FontWeight.w600
                              : FontWeight.w400,
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dotted,
                          decorationColor: stockColor,
                        ),
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

  // ===================== PANEL PESANAN =====================

  Widget _buildOrderPanel(CartProvider cart, ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(left: BorderSide(color: theme.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _orderHeader(cart, theme),
            ),
          ),
          Expanded(
            child: cart.items.isEmpty
                ? _emptyCart(cart, theme)
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      for (final item in cart.items)
                        _buildCartItem(item, cart, theme),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _orderFooter(cart, theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCart(CartProvider cart, ThemeProvider theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          cart.isAppending
              ? "Pilih menu tambahan untuk ${cart.appendLabel}."
              : "Belum ada pesanan.\nKetuk menu untuk menambahkan.",
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.secondaryTextColor),
        ),
      ),
    );
  }

  /// Jenis pesanan, meja, dan nama pelanggan (atau info bill saat menambah)
  List<Widget> _orderHeader(CartProvider cart, ThemeProvider theme,
      {Widget? trailing}) {
    if (cart.isAppending) {
      return [
        Row(
          children: [
            Expanded(
              child: Text("Tambah pesanan",
                  style: TextStyle(
                      color: theme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            color: theme.warningSoftColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 18, color: theme.warningInkColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text("Ke bill ${cart.appendLabel}",
                    style: TextStyle(
                        color: theme.warningInkColor,
                        fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () {
                  cart.clearCart();
                  _syncInputsFromCart();
                },
                child: Text("Batal",
                    style: TextStyle(color: theme.warningInkColor)),
              ),
            ],
          ),
        ),
      ];
    }

    Widget segment(String label, String value) {
      final bool selected = cart.orderType == value;
      return Expanded(
        child: Material(
          color: selected ? theme.cardColor : Colors.transparent,
          elevation: selected ? 1 : 0,
          shadowColor: theme.textColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (value == 'delivery') {
                _showDeliveryPicker(cart);
                return;
              }
              if (value != 'dine_in') _tableController.clear();
              cart.setOrderType(value);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Text(
                value == 'delivery' && selected && cart.deliveryPlatform.isNotEmpty
                    ? platformLabel(cart.deliveryPlatform)
                    : label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? theme.textColor : theme.secondaryTextColor,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return [
      if (trailing != null)
        Row(
          children: [
            Expanded(
              child: Text("Pesanan",
                  style: TextStyle(
                      color: theme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ),
            trailing,
          ],
        ),
      if (trailing != null) const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: theme.subtleColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            segment("Makan di sini", "dine_in"),
            segment("Bungkus", "to_go"),
            segment("Ojol", "delivery"),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          if (cart.orderType == 'dine_in') ...[
            SizedBox(
              width: 92,
              child: TextField(
                controller: _tableController,
                keyboardType: TextInputType.text,
                onChanged: (_) => _applyInputs(cart),
                decoration: const InputDecoration(
                  labelText: "Meja",
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  hintText: "Meja",
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => _applyInputs(cart),
              decoration: const InputDecoration(
                hintText: "Nama pelanggan (opsional)",
              ),
            ),
          ),
        ],
      ),
    ];
  }

  /// Ringkasan harga & tombol aksi
  List<Widget> _orderFooter(CartProvider cart, ThemeProvider theme) {
    final bool hasItems = cart.items.isNotEmpty;
    return [
      AmountRow("Subtotal", rupiah(cart.subtotalPrice), fontSize: 13),
      AmountRow("Pajak PB1 ${cart.taxPercentLabel}%", rupiah(cart.taxAmount),
          fontSize: 13),
      if (!cart.isAppending)
        Row(
          children: [
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _showDiscountPicker(cart),
              child: Text(cart.selectedDiscount == null
                  ? "+ Pakai diskon"
                  : "Diskon: ${cart.selectedDiscount!.name}"),
            ),
            const Spacer(),
            if (cart.selectedDiscount != null) ...[
              Text("− ${rupiah(cart.discountAmount)}",
                  style: TextStyle(color: theme.dangerColor, fontSize: 13)),
              IconButton(
                tooltip: "Hapus diskon",
                visualDensity: VisualDensity.compact,
                onPressed: () => cart.setDiscount(null),
                icon: Icon(Icons.close, size: 16, color: theme.dangerColor),
              ),
            ],
          ],
        ),
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(cart.isAppending ? "Tambahan" : "Total",
              style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const Spacer(),
          Text(
            rupiah(cart.totalPrice),
            style: TextStyle(
              color: theme.textColor,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (cart.isAppending)
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: !hasItems || _isSubmitting
                ? null
                : () => _handleAppendToBill(cart),
            child: Text(_isSubmitting ? "Menyimpan…" : "Tambahkan ke bill"),
          ),
        )
      else
        Row(
          children: [
            if (cart.orderType == 'dine_in') ...[
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: !hasItems || _isSubmitting
                        ? null
                        : () => _handleSaveAsBill(cart),
                    child: const Text("Simpan bill"),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: !hasItems ? null : () => _goToPayment(cart),
                  child: const Text("Bayar"),
                ),
              ),
            ),
          ],
        ),
    ];
  }

  Widget _qtyButton(IconData icon, String tooltip, ThemeProvider theme,
      VoidCallback onTap) {
    return SizedBox(
      width: 34,
      height: 34,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(34, 34),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Icon(icon, size: 16, color: theme.textColor, semanticLabel: tooltip),
      ),
    );
  }

  Widget _buildCartItem(CartItem item, CartProvider cart, ThemeProvider theme) {
    final String note = item.note ?? "";
    final int price = cart.priceOf(item.menu);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.subtleColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(item.menu.name,
                    style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
              const SizedBox(width: 12),
              Text(
                rupiah(price * item.quantity),
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(note,
                  style: TextStyle(color: theme.warningColor, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _qtyButton(Icons.remove, "Kurangi", theme,
                  () => cart.decreaseQuantity(item.menu.id)),
              SizedBox(
                width: 34,
                child: Text("${item.quantity}",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
              _qtyButton(
                  Icons.add, "Tambah", theme, () => _addMenu(cart, item.menu)),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 40),
                ),
                onPressed: () => _showNoteDialog(item, cart),
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text("Catatan", style: TextStyle(fontSize: 13)),
              ),
              IconButton(
                tooltip: "Hapus dari pesanan",
                onPressed: () => cart.removeFromCart(item.menu.id),
                icon: Icon(Icons.delete_outline,
                    size: 20, color: theme.dangerColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===================== VERSI HP =====================

  Widget _buildMobile(CartProvider cart, ThemeProvider theme) {
    final int itemCount =
        cart.items.fold(0, (sum, item) => sum + item.quantity);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: cart.isAppending ? "Tambah pesanan" : "Pesanan baru",
                  subtitle: cart.isAppending
                      ? "Ke bill ${cart.appendLabel}"
                      : "Ketuk label stok untuk mengubah stok",
                  compact: true,
                ),
                const SizedBox(height: 12),
                _searchField(theme),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildCategoryChips(theme),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _menuArea(cart, theme),
            ),
          ),
        ],
      ),
      bottomNavigationBar: cart.items.isEmpty && !cart.isAppending
          ? null
          : _buildMobileCartBar(cart, theme, itemCount),
    );
  }

  Widget _buildMobileCartBar(
      CartProvider cart, ThemeProvider theme, int itemCount) {
    final String where = cart.isAppending
        ? cart.appendLabel
        : (cart.tableNumber.isNotEmpty
            ? "Meja ${cart.tableNumber}"
            : (cart.orderType == 'delivery'
                ? platformLabel(cart.deliveryPlatform)
                : (cart.orderType == 'to_go' ? "Bungkus" : "Pesanan")));

    return Container(
      color: theme.backgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Material(
            color: theme.inkColor,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _openMobileCart,
              child: SizedBox(
                height: 58,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text("$itemCount",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(where,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: theme.onInkColor
                                        .withValues(alpha: 0.75),
                                    fontSize: 12)),
                            Text(
                              rupiah(cart.totalPrice),
                              style: TextStyle(
                                color: theme.onInkColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text("Lihat pesanan",
                          style: TextStyle(
                              color: theme.onInkColor,
                              fontWeight: FontWeight.w600)),
                      Icon(Icons.chevron_right, color: theme.onInkColor),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Lembar pesanan (HP). Punya ScaffoldMessenger sendiri supaya pesan
  // seperti "Isi nomor meja" tampil di atas lembar, bukan tertutup.
  void _openMobileCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: ScaffoldMessenger(
              child: Consumer2<CartProvider, ThemeProvider>(
                builder: (_, cart, theme, __) => Scaffold(
                  backgroundColor: theme.cardColor,
                  body: Builder(builder: (ctx) {
                    _sheetContext = ctx;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: theme.borderColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        ..._orderHeader(
                          cart,
                          theme,
                          trailing: IconButton(
                            tooltip: "Tutup",
                            onPressed: _closeMobileCart,
                            icon: Icon(Icons.close,
                                color: theme.secondaryTextColor),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (cart.items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: _emptyCart(cart, theme),
                          )
                        else
                          ...cart.items
                              .map((item) => _buildCartItem(item, cart, theme)),
                      ],
                    );
                  }),
                  bottomNavigationBar: SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        border:
                            Border(top: BorderSide(color: theme.borderColor)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _orderFooter(cart, theme),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() => _sheetContext = null);
  }

  void _closeMobileCart() {
    final ctx = _sheetContext;
    _sheetContext = null;
    if (ctx != null && ctx.mounted) Navigator.pop(ctx);
  }
}
