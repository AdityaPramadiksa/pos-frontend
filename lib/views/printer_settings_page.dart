import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../providers/theme_provider.dart';
import '../services/printer_service.dart';
import '../utils/responsive.dart';
import '../widgets/ui.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage>
    with WidgetsBindingObserver {
  static const MethodChannel _settingsChannel =
      MethodChannel('pos_babi_guling/settings');

  final PrinterService _printer = PrinterService();
  bool _isProcessing = false; // 🔥 Biar tombol gak macet

  String _receiptMac = PrinterService.defaultMacAddress;
  String? _receiptName;
  String? _kitchenMac;
  String? _kitchenName;
  List<BluetoothInfo> _pairedDevices = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPrinter();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Kembali dari halaman Bluetooth Android -> muat ulang daftar printer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPairedDevices();
  }

  Future<void> _initPrinter() async {
    if (!kIsWeb) {
      await [
        Permission.location,
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
    }
    await _loadSavedPrinters();
    await _loadPairedDevices();
  }

  Future<void> _loadSavedPrinters() async {
    final receiptMac = await _printer.getSavedMac();
    final receiptName = await _printer.getSavedName();
    final kitchenMac = await _printer.getKitchenMac();
    final kitchenName = await _printer.getSavedName(role: PrinterRole.kitchen);
    if (!mounted) return;
    setState(() {
      _receiptMac = receiptMac;
      _receiptName = receiptName;
      _kitchenMac = kitchenMac;
      _kitchenName = kitchenName;
    });
  }

  // Printer yang sudah di-pairing di pengaturan Bluetooth HP/tablet
  Future<void> _loadPairedDevices() async {
    if (kIsWeb) return;
    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (mounted) setState(() => _pairedDevices = devices);
    } catch (e) {
      debugPrint("Gagal ambil daftar bluetooth: $e");
    }
  }

  Future<void> _openBluetoothSettings() async {
    bool opened = false;
    try {
      opened = await _settingsChannel.invokeMethod<bool>(
              'openBluetoothSettings') ??
          false;
    } catch (e) {
      debugPrint("Gagal buka pengaturan Bluetooth: $e");
    }
    if (!opened) {
      _showSnack(
          "Buka Pengaturan > Bluetooth di HP secara manual.", Colors.orange);
    }
  }

  String _nameOf(String mac, String? savedName) {
    for (final d in _pairedDevices) {
      if (d.macAdress == mac) return d.name;
    }
    return (savedName == null || savedName.isEmpty) ? "Printer" : savedName;
  }

  Future<void> _assign(BluetoothInfo device, PrinterRole role) async {
    await _printer.saveMac(device.macAdress, role: role, name: device.name);
    await _loadSavedPrinters();
    _showSnack(
      role == PrinterRole.kitchen
          ? "${device.name} dipakai untuk CEKER DAPUR"
          : "${device.name} dipakai untuk STRUK / BILL / SETTLEMENT",
      Colors.green,
    );
  }

  Future<void> _clearKitchen() async {
    await _printer.clearKitchenPrinter();
    await _loadSavedPrinters();
    _showSnack("Ceker dapur kembali dicetak di printer struk", Colors.blueGrey);
  }

  Future<void> _connect(PrinterRole role) async {
    setState(() => _isProcessing = true);
    final bool ok = await _printer.ensureConnected(role: role);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    _showSnack(
      ok
          ? "Printer terhubung."
          : "Gagal terhubung. Pastikan printer menyala, Bluetooth aktif & dekat.",
      ok ? Colors.green : Colors.redAccent,
    );
  }

  Future<void> _testPrint(PrinterRole role) async {
    setState(() => _isProcessing = true);
    final bool printed = await _printer.printTest(role: role);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    _showSnack(
      printed
          ? "Tes cetak terkirim"
          : "Gagal cetak. Pastikan printer menyala & sudah di-pairing.",
      printed ? Colors.green : Colors.red,
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    final bool ok = color == Colors.green;
    final bool bad = color == Colors.red || color == Colors.redAccent || color == Colors.orange;
    showMessage(context, msg, success: ok, error: bad);
  }

  // Pilih printer ini dipakai untuk apa
  void _showAssignSheet(BluetoothInfo device, ThemeProvider theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
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
              child: Text(
                "Pakai ${device.name} untuk:",
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: Icon(Icons.receipt_long, color: theme.primaryColor),
              title: Text("Struk, Bill & Settlement",
                  style: TextStyle(color: theme.textColor)),
              subtitle: Text("Struk pelanggan, tagihan, rekap shift",
                  style: TextStyle(color: theme.secondaryTextColor)),
              onTap: () {
                Navigator.pop(sheetContext);
                _assign(device, PrinterRole.receipt);
              },
            ),
            ListTile(
              leading: Icon(Icons.soup_kitchen_outlined,
                  color: theme.primaryColor),
              title: Text("Ceker Dapur",
                  style: TextStyle(color: theme.textColor)),
              subtitle: Text("Pesanan untuk dapur",
                  style: TextStyle(color: theme.secondaryTextColor)),
              onTap: () {
                Navigator.pop(sheetContext);
                _assign(device, PrinterRole.kitchen);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final double pad = isMobile(context) ? 16 : 24;
    final bool hasKitchen = _kitchenMac != null && _kitchenMac!.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text("Printer",
            style: TextStyle(color: theme.textColor)),
        backgroundColor: theme.backgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: "Muat ulang daftar printer",
            onPressed: _loadPairedDevices,
            icon: Icon(Icons.refresh, color: theme.textColor),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(pad),
        children: [
          _printerCard(
            theme,
            role: PrinterRole.receipt,
            icon: Icons.receipt_long,
            title: "Printer Struk",
            purpose: "Struk pelanggan, bill & settlement",
            mac: _receiptMac,
            name: _nameOf(_receiptMac, _receiptName),
          ),
          const SizedBox(height: 12),
          _printerCard(
            theme,
            role: PrinterRole.kitchen,
            icon: Icons.soup_kitchen_outlined,
            title: "Printer Ceker Dapur",
            purpose: hasKitchen
                ? "Khusus ceker pesanan untuk dapur"
                : "Belum diatur. Ceker ikut dicetak di printer struk.",
            mac: _kitchenMac,
            name: hasKitchen ? _nameOf(_kitchenMac!, _kitchenName) : null,
          ),
          const SizedBox(height: 28),

          // --- Pairing printer baru langsung dari HP ---
          Text("Tambah printer baru",
              style: TextStyle(
                  color: theme.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            "1. Nyalakan printer.  2. Tekan tombol di bawah, pilih printer di "
            "daftar Bluetooth lalu pairing (PIN biasanya 0000 atau 1234).  "
            "3. Kembali ke aplikasi, printer muncul di daftar bawah.",
            style: TextStyle(color: theme.secondaryTextColor, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.primaryColor,
                side: BorderSide(color: theme.primaryColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _openBluetoothSettings,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text("Buka pengaturan Bluetooth",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 28),

          Text("Printer ter-pairing",
              style: TextStyle(
                  color: theme.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("Ketuk printer untuk memilih dipakai sebagai apa.",
              style: TextStyle(color: theme.secondaryTextColor, fontSize: 12)),
          const SizedBox(height: 12),
          if (_pairedDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                "Belum ada perangkat ter-pairing yang terbaca.\nPairing dulu lewat tombol di atas.",
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.secondaryTextColor),
              ),
            )
          else
            ..._pairedDevices.map((device) {
              final bool isReceipt = device.macAdress == _receiptMac;
              final bool isKitchen = device.macAdress == _kitchenMac;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  tileColor: theme.cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: isReceipt || isKitchen
                            ? theme.primaryColor
                            : theme.borderColor),
                  ),
                  leading: Icon(Icons.bluetooth,
                      color: isReceipt || isKitchen
                          ? theme.primaryColor
                          : theme.secondaryTextColor),
                  title: Text(device.name,
                      style: TextStyle(color: theme.textColor)),
                  subtitle: Text(device.macAdress,
                      style: TextStyle(color: theme.secondaryTextColor)),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (isReceipt) _badge("STRUK", theme),
                      if (isKitchen) _badge("DAPUR", theme),
                      if (!isReceipt && !isKitchen)
                        Text("Pilih",
                            style: TextStyle(color: theme.primaryColor)),
                    ],
                  ),
                  onTap: _isProcessing
                      ? null
                      : () => _showAssignSheet(device, theme),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _badge(String text, ThemeProvider theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _printerCard(
    ThemeProvider theme, {
    required PrinterRole role,
    required IconData icon,
    required String title,
    required String purpose,
    required String? mac,
    required String? name,
  }) {
    final bool configured = mac != null && mac.isNotEmpty;
    final bool active = configured && _printer.activeMac == mac;

    return Container(
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
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: theme.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    Text(purpose,
                        style: TextStyle(
                            color: theme.secondaryTextColor, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (configured) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(active ? Icons.check_circle : Icons.print_outlined,
                    size: 16,
                    color: active ? theme.successColor : theme.secondaryTextColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "${name ?? 'Printer'} • $mac",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.textColor, fontSize: 13),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                active
                    ? "Sedang tersambung"
                    : "Tersambung otomatis saat mencetak",
                style: TextStyle(
                    color: active ? theme.successColor : theme.secondaryTextColor,
                    fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (configured) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isProcessing ? null : () => _testPrint(role),
                  icon: const Icon(Icons.receipt, size: 18),
                  label: const Text("Tes cetak"),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.primaryColor,
                    side: BorderSide(color: theme.borderColor),
                  ),
                  onPressed: _isProcessing ? null : () => _connect(role),
                  icon: const Icon(Icons.bluetooth_connected, size: 18),
                  label: const Text("Hubungkan"),
                ),
              ],
              if (role == PrinterRole.kitchen && configured)
                TextButton(
                  onPressed: _isProcessing ? null : _clearKitchen,
                  child: Text("Pakai printer struk",
                      style: TextStyle(color: theme.dangerColor)),
                ),
              if (!configured)
                Text(
                  "Pilih printer dari daftar ter-pairing di bawah.",
                  style:
                      TextStyle(color: theme.secondaryTextColor, fontSize: 12),
                ),
            ],
          ),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}
