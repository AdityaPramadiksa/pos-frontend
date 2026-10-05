import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/cart_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/printer_service.dart';
import '../services/sync_service.dart';
import '../utils/responsive.dart';
import '../widgets/sync_status.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'order_history_page.dart';
import 'sales_recap_page.dart';
import 'bills_page.dart';
import 'petty_cash_page.dart';
import 'printer_settings_page.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _NavItem {
  final int index;
  final IconData icon;
  final String label;
  const _NavItem(this.index, this.icon, this.label);
}

class _MainLayoutState extends State<MainLayout> {
  String _cashierName = "";
  final ApiService _apiService = ApiService();

  static const List<_NavItem> _items = [
    _NavItem(NavProvider.kasir, Icons.grid_view_rounded, "Kasir"),
    _NavItem(NavProvider.bills, Icons.receipt_long_outlined, "Bill"),
    _NavItem(NavProvider.riwayat, Icons.history_rounded, "Riwayat"),
    _NavItem(NavProvider.rekap, Icons.bar_chart_rounded, "Rekap"),
    _NavItem(NavProvider.kasKeluar, Icons.account_balance_wallet_outlined, "Kas keluar"),
    _NavItem(NavProvider.printer, Icons.print_outlined, "Printer"),
  ];

  Widget _page(int index) {
    switch (index) {
      case NavProvider.bills:
        return const BillsPage();
      case NavProvider.riwayat:
        return const OrderHistoryPage();
      case NavProvider.kasKeluar:
        return const PettyCashPage();
      case NavProvider.rekap:
        return const SalesRecapPage();
      case NavProvider.printer:
        return const PrinterSettingsPage();
      default:
        return const HomePage();
    }
  }

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

    // Antrean transaksi offline: muat & kirim berkala selama aplikasi dibuka
    await SyncService().load();
    SyncService().start();

    // Buka shift (otomatis di server), lalu ambil pengaturan toko terbaru.
    // Saat offline keduanya gagal tanpa masalah: shift dibuka server ketika
    // transaksi pertama terkirim, pengaturan memakai salinan terakhir.
    await _apiService.checkSettlementStatus();
    await AppSettings().refresh();
    if (mounted) {
      Provider.of<CartProvider>(context, listen: false)
          .setTaxPercent(AppSettings().taxPercent);
    }

    // Sambungkan printer tersimpan supaya struk pertama tidak gagal
    PrinterService().ensureConnected();
  }

  Future<void> _confirmLogout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Keluar dari aplikasi?"),
        content: Text(
          "Shift Anda tetap berjalan dan bisa dilanjutkan saat masuk lagi. "
          "Untuk menutup shift dan mencetak settlement, buka menu Rekap."
          "${SyncService().pendingCount > 0 ? '\n\nTransaksi yang belum terkirim tetap dikirim otomatis selama aplikasi terbuka.' : ''}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Keluar"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _apiService.logout();
    if (!mounted) return;
    Provider.of<CartProvider>(context, listen: false).clearCart();
    Provider.of<NavProvider>(context, listen: false).goTo(NavProvider.kasir);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  // --- HP: bar bawah Kasir, Bill, Riwayat, Rekap, Lainnya ---
  static const List<int> _bottomNavPages = [
    NavProvider.kasir,
    NavProvider.bills,
    NavProvider.riwayat,
    NavProvider.rekap,
  ];

  void _showMoreMenu(ThemeProvider theme, NavProvider nav) {
    showModalBottomSheet(
      context: context,
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
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
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
                    backgroundColor: theme.primarySoftColor,
                    child: Text(
                      _cashierName.characters.take(2).toString().toUpperCase(),
                      style: TextStyle(
                          color: theme.primaryDarkColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
                  title: Text(_cashierName,
                      style: TextStyle(
                          color: theme.textColor, fontWeight: FontWeight.w600)),
                  subtitle: Text("Shift sedang berjalan",
                      style: TextStyle(color: theme.successColor)),
                ),
              Divider(color: theme.borderColor),
              item(Icons.account_balance_wallet_outlined, "Kas keluar",
                  () => nav.goTo(NavProvider.kasKeluar),
                  active: nav.index == NavProvider.kasKeluar),
              item(Icons.print_outlined, "Printer",
                  () => nav.goTo(NavProvider.printer),
                  active: nav.index == NavProvider.printer),
              item(Icons.logout, "Keluar", _confirmLogout,
                  color: theme.dangerColor),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNav(ThemeProvider theme, NavProvider nav) {
    final int selected = _bottomNavPages.indexOf(nav.index);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.borderColor)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: theme.cardColor,
          surfaceTintColor: Colors.transparent,
          indicatorColor: theme.primarySoftColor,
          height: 66,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontFamily: 'PlusJakartaSans',
              fontSize: 11.5,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: states.contains(WidgetState.selected)
                  ? theme.primaryDarkColor
                  : theme.secondaryTextColor,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? theme.primaryDarkColor
                  : theme.secondaryTextColor,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selected >= 0 ? selected : _bottomNavPages.length,
          onDestinationSelected: (index) {
            if (index == _bottomNavPages.length) {
              _showMoreMenu(theme, nav);
            } else {
              nav.goTo(_bottomNavPages[index]);
            }
          },
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.grid_view_rounded), label: "Kasir"),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined), label: "Bill"),
            NavigationDestination(
                icon: Icon(Icons.history_rounded), label: "Riwayat"),
            NavigationDestination(
                icon: Icon(Icons.bar_chart_rounded), label: "Rekap"),
            NavigationDestination(
                icon: Icon(Icons.more_horiz_rounded), label: "Lainnya"),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final nav = Provider.of<NavProvider>(context);

    if (isMobile(context)) {
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const SyncStatusBar(),
              Expanded(child: _page(nav.index)),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(theme, nav),
      );
    }

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            _buildRail(theme, nav),
            Expanded(child: _page(nav.index)),
          ],
        ),
      ),
    );
  }

  // --- Tablet: rail navigasi di kiri ---
  Widget _buildRail(ThemeProvider theme, NavProvider nav) {
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(right: BorderSide(color: theme.borderColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/app_icon.png', width: 40, height: 40),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final item in _items) _railItem(item, theme, nav),
                ],
              ),
            ),
          ),
          const SyncStatusBar(compact: true),
          if (_cashierName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  Text(_cashierName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: theme.textColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                  Text("Shift buka",
                      style:
                          TextStyle(color: theme.successColor, fontSize: 11)),
                ],
              ),
            ),
          Tooltip(
            message: "Keluar",
            child: InkWell(
              onTap: _confirmLogout,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Icon(Icons.logout, color: theme.dangerColor, size: 22),
                    const SizedBox(height: 3),
                    Text("Keluar",
                        style: TextStyle(
                            color: theme.secondaryTextColor, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _railItem(_NavItem item, ThemeProvider theme, NavProvider nav) {
    final bool active = nav.index == item.index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? theme.primarySoftColor : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => nav.goTo(item.index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(item.icon,
                    size: 23,
                    color: active
                        ? theme.primaryDarkColor
                        : theme.secondaryTextColor),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: active
                        ? theme.primaryDarkColor
                        : theme.secondaryTextColor,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
