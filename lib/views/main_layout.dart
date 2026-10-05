import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/cart_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../utils/responsive.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'order_history_page.dart';
import 'sales_recap_page.dart';
import 'bills_page.dart';
import 'petty_cash_page.dart';
import 'printer_settings_page.dart'; // 🔥 Import printer settings

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  String _cashierName = "";
  final ApiService _apiService = ApiService();

  // Daftar Halaman Utama
  final List<Widget> _pages = [
    const HomePage(), // Index 0: Halaman Transaksi/Kasir Utama
    const BillsPage(), // Index 1: Daftar Meja/Pesanan Gantung
    const OrderHistoryPage(), // Index 2: Riwayat Transaksi Lunas & Void
    const PettyCashPage(), // Index 3: Kas Keluar / Petty Cash
    const SalesRecapPage(), // Index 4: Rekap Penjualan & Tutup Shift
    const PrinterSettingsPage(), // 🔥 Index 5: SEKARANG MENGARAH KE PRINTER SETTINGS
  ];

  @override
  void initState() {
    super.initState();
    _initializeShift();
  }

  Future<void> _initializeShift() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _cashierName = prefs.getString('user_name') ?? "");
    }

    // Buka shift (otomatis di server) & ambil tarif pajak yang berlaku
    final response = await _apiService.checkSettlementStatus();
    if (response['status'] == 'success') {
      debugPrint("Shift Active: ${response['data']?['starting_cash']}");
    }

    final settings = await _apiService.getSettings();
    if (mounted && settings['status'] == 'success') {
      final taxRate = settings['data']?['tax_rate'];
      if (taxRate is num) {
        Provider.of<CartProvider>(context, listen: false)
            .setTaxPercent(taxRate);
      }
    }

    // Sambungkan printer tersimpan supaya struk pertama tidak gagal
    PrinterService().ensureConnected();
  }

  Future<void> _confirmLogout(ThemeProvider theme) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text("Keluar?", style: TextStyle(color: theme.textColor)),
        content: Text(
          "Shift TIDAK ditutup dan tetap berjalan saat Anda login lagi.\n"
          "Untuk tutup shift & cetak settlement, pakai menu Rekap.",
          style: TextStyle(color: theme.secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("BATAL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("KELUAR", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _apiService.logout();
    if (!mounted) return;
    Provider.of<CartProvider>(context, listen: false).clearCart();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  // --- NAVIGASI VERSI HP ---
  // Bar bawah: Kasir, Bills, Riwayat, Rekap, Lainnya (Kas Keluar, Printer, Keluar)
  static const List<int> _bottomNavPages = [0, 1, 2, 4];

  int get _bottomNavIndex {
    final int index = _bottomNavPages.indexOf(_selectedIndex);
    return index >= 0 ? index : _bottomNavPages.length;
  }

  void _showMoreMenu(ThemeProvider theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        Widget item(IconData icon, String label, VoidCallback onTap,
            {Color? color, bool active = false}) {
          return ListTile(
            leading: Icon(icon,
                color: color ??
                    (active ? theme.primaryColor : theme.secondaryTextColor)),
            title: Text(label,
                style: TextStyle(
                    color: color ?? theme.textColor,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal)),
            trailing: active
                ? Icon(Icons.check, color: theme.primaryColor, size: 18)
                : null,
            onTap: () {
              Navigator.pop(sheetContext);
              onTap();
            },
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: theme.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (_cashierName.isNotEmpty)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.primaryColor.withAlpha(40),
                    child: Icon(Icons.person, color: theme.primaryColor),
                  ),
                  title: Text(_cashierName,
                      style: TextStyle(
                          color: theme.textColor, fontWeight: FontWeight.bold)),
                  subtitle: Text("Kasir yang sedang bertugas",
                      style: TextStyle(color: theme.secondaryTextColor)),
                ),
              Divider(color: theme.borderColor),
              item(Icons.account_balance_wallet_outlined, "Kas Keluar",
                  () => setState(() => _selectedIndex = 3),
                  active: _selectedIndex == 3),
              item(Icons.print_outlined, "Printer",
                  () => setState(() => _selectedIndex = 5),
                  active: _selectedIndex == 5),
              item(Icons.logout, "Keluar", () => _confirmLogout(theme),
                  color: Colors.redAccent),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNav(ThemeProvider theme) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: theme.cardColor,
        indicatorColor: theme.primaryColor,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.bold
                : FontWeight.normal,
            color: states.contains(WidgetState.selected)
                ? theme.primaryColor
                : theme.secondaryTextColor,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : theme.secondaryTextColor,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: _bottomNavIndex,
        onDestinationSelected: (index) {
          if (index == _bottomNavPages.length) {
            _showMoreMenu(theme);
          } else {
            setState(() => _selectedIndex = _bottomNavPages[index]);
          }
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.grid_view_rounded), label: "Kasir"),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_rounded), label: "Bills"),
          NavigationDestination(
              icon: Icon(Icons.history_rounded), label: "Riwayat"),
          NavigationDestination(
              icon: Icon(Icons.analytics_outlined), label: "Rekap"),
          NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded), label: "Lainnya"),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (isMobile(context)) {
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        body: SafeArea(bottom: false, child: _pages[_selectedIndex]),
        bottomNavigationBar: _buildBottomNav(theme),
      );
    }

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: Row(
        children: [
          _buildJaegarSidebar(theme),
          // Area Konten Utama
          Expanded(
            child: Container(
              color: theme.backgroundColor,
              // Menggunakan navigasi index biasa sesuai kode awal kamu agar login lancar
              child: _pages[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJaegarSidebar(ThemeProvider theme) {
    return Container(
      width: 100,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(right: BorderSide(color: theme.borderColor, width: 1)),
      ),
      child: Column(
        children: [
          // 1. LOGO RESTO
          Container(
            margin: const EdgeInsets.only(top: 24, bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.primaryColor.withAlpha(25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.restaurant_menu,
              color: theme.primaryColor,
              size: 32,
            ),
          ),
          if (_cashierName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                _cashierName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.secondaryTextColor, fontSize: 11),
              ),
            ),
          const SizedBox(height: 8),

          // 2. NAVIGASI MENU
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _sidebarItem(Icons.grid_view_rounded, "Kasir", 0, theme),
                  _sidebarItem(Icons.receipt_long_rounded, "Bills", 1, theme),
                  _sidebarItem(Icons.history_rounded, "Riwayat", 2, theme),
                  _sidebarItem(Icons.account_balance_wallet_outlined,
                      "Kas Keluar", 3, theme),
                  _sidebarItem(Icons.analytics_outlined, "Rekap", 4, theme),
                  _sidebarItem(Icons.print_outlined, "Printer", 5, theme),
                ],
              ),
            ),
          ),

          // 3. LOGOUT (tanpa tutup shift)
          InkWell(
            onTap: () => _confirmLogout(theme),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Icon(Icons.logout, color: Colors.redAccent, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    "Keluar",
                    style:
                        TextStyle(color: theme.secondaryTextColor, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(
      IconData icon, String label, int index, ThemeProvider theme) {
    bool isActive = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
      },
      child: Container(
        width: 100,
        height: 85,
        color: Colors.transparent,
        child: Stack(
          children: [
            // Highlight indikator di sisi kanan
            if (isActive)
              Positioned(
                right: 0,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                ),
              ),

            // Icon Utama + label
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isActive ? theme.primaryColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: theme.primaryColor.withAlpha(76),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      icon,
                      color: isActive ? Colors.white : theme.secondaryTextColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: isActive
                          ? theme.primaryColor
                          : theme.secondaryTextColor,
                      fontSize: 11,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
