import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../providers/theme_provider.dart';
import '../services/printer_service.dart';
import '../utils/responsive.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  final PrinterService _printer = PrinterService();
  bool _connected = false;
  bool _isProcessing = false; // 🔥 Biar tombol gak macet

  String _printerMacAddress = PrinterService.defaultMacAddress;
  List<BluetoothInfo> _pairedDevices = [];

  @override
  void initState() {
    super.initState();
    _initPrinter();
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
    final String mac = await _printer.getSavedMac();
    if (mounted) setState(() => _printerMacAddress = mac);
    await _loadPairedDevices();
    _checkConnectionStatus();
  }

  // Printer yang sudah di-pairing di pengaturan Bluetooth tablet
  Future<void> _loadPairedDevices() async {
    if (kIsWeb) return;
    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (mounted) setState(() => _pairedDevices = devices);
    } catch (e) {
      debugPrint("Gagal ambil daftar bluetooth: $e");
    }
  }

  Future<void> _checkConnectionStatus() async {
    if (kIsWeb) return;
    try {
      final bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (mounted) setState(() => _connected = isConnected);
    } catch (e) {
      debugPrint("Gagal cek status: $e");
    }
  }

  Future<void> _connectTo(String mac) async {
    if (_isProcessing) return; // Cegah double click

    setState(() => _isProcessing = true);

    try {
      // 1. Pastikan Bluetooth Aktif
      final bool isBluetoothOn = await PrintBluetoothThermal.bluetoothEnabled;
      if (!isBluetoothOn) {
        _showSnack("Nyalakan Bluetooth Tablet dulu!", Colors.orange);
        return;
      }

      // 2. 🔥 RITUAL PEMBERSIHAN (Sangat Penting)
      // Putuskan koneksi lama yang mungkin "nyangkut" di memori
      await PrintBluetoothThermal.disconnect;
      await Future.delayed(const Duration(milliseconds: 500));

      // 3. Hubungkan
      final bool result =
          await PrintBluetoothThermal.connect(macPrinterAddress: mac);

      if (result) {
        // Diingat supaya aplikasi bisa menyambung ulang sendiri saat mencetak
        await _printer.saveMac(mac);
      }

      if (mounted) {
        setState(() {
          _connected = result;
          if (result) _printerMacAddress = mac;
        });
      }

      if (result) {
        _showSnack("PRINTER TERHUBUNG!", Colors.green);
      } else {
        _showSnack(
            "Gagal terhubung. Pastikan printer menyala & dekat dengan tablet.",
            Colors.redAccent);
      }
    } catch (e) {
      debugPrint("Error koneksi: $e");
      _showSnack("Error: $e", Colors.red);
    } finally {
      // 🔥 Tombol bisa diklik lagi setelah selesai proses
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _disconnect() async {
    setState(() => _isProcessing = true);
    try {
      await PrintBluetoothThermal.disconnect;
      if (mounted) setState(() => _connected = false);
      _showSnack("Koneksi diputuskan", Colors.blueGrey);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _testPrint() async {
    setState(() => _isProcessing = true);
    final bool printed = await _printer.printTest();
    if (!mounted) return;
    setState(() => _isProcessing = false);
    _checkConnectionStatus();
    _showSnack(
      printed ? "Tes cetak terkirim" : "Gagal cetak. Hubungkan printer dulu.",
      printed ? Colors.green : Colors.red,
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: color,
          duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text("Printer Settings",
            style: TextStyle(color: theme.textColor)),
        backgroundColor: theme.backgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: "Muat ulang daftar printer",
            onPressed: () async {
              await _loadPairedDevices();
              _checkConnectionStatus();
            },
            icon: Icon(Icons.refresh, color: theme.textColor),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(isMobile(context) ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              tileColor: theme.cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading: Icon(_connected ? Icons.print : Icons.print_disabled,
                  color: _connected ? Colors.green : Colors.grey),
              title: Text(_connected ? "SIAP MENCETAK" : "PRINTER OFFLINE",
                  style: TextStyle(
                      color: theme.textColor, fontWeight: FontWeight.bold)),
              subtitle: Text("Printer aktif: $_printerMacAddress",
                  style: TextStyle(color: theme.secondaryTextColor)),
              trailing: Icon(_connected ? Icons.check_circle : Icons.cancel,
                  color: _connected ? Colors.green : Colors.red),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _connected ? Colors.redAccent : theme.primaryColor,
                        disabledBackgroundColor: Colors.grey, // 🔥 Saat proses
                      ),
                      onPressed: _isProcessing
                          ? null
                          : (_connected
                              ? _disconnect
                              : () => _connectTo(_printerMacAddress)),
                      child: _isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              isMobile(context)
                                  ? (_connected ? "PUTUSKAN" : "HUBUNGKAN")
                                  : (_connected
                                      ? "PUTUSKAN KONEKSI"
                                      : "HUBUNGKAN PRINTER"),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 55,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.primaryColor,
                        side: BorderSide(color: theme.primaryColor),
                      ),
                      onPressed: _isProcessing ? null : _testPrint,
                      icon: const Icon(Icons.receipt),
                      label: const Text("TES CETAK",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text("Printer Bluetooth ter-pairing",
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            Text(
                "Ganti printer? Pairing dulu di pengaturan Bluetooth tablet, lalu pilih di sini.",
                style:
                    TextStyle(color: theme.secondaryTextColor, fontSize: 12)),
            const SizedBox(height: 12),
            Expanded(
              child: _pairedDevices.isEmpty
                  ? Center(
                      child: Text(
                        "Belum ada perangkat ter-pairing yang terbaca.\nPrinter aktif di atas tetap bisa dihubungkan.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.secondaryTextColor),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _pairedDevices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final device = _pairedDevices[index];
                        final bool isActive =
                            device.macAdress == _printerMacAddress;
                        return ListTile(
                          tileColor: theme.cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: isActive
                                    ? theme.primaryColor
                                    : theme.borderColor),
                          ),
                          leading: Icon(Icons.bluetooth,
                              color: isActive
                                  ? theme.primaryColor
                                  : theme.secondaryTextColor),
                          title: Text(device.name,
                              style: TextStyle(color: theme.textColor)),
                          subtitle: Text(device.macAdress,
                              style:
                                  TextStyle(color: theme.secondaryTextColor)),
                          trailing: isActive && _connected
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green)
                              : Text("Hubungkan",
                                  style: TextStyle(color: theme.primaryColor)),
                          onTap: _isProcessing
                              ? null
                              : () => _connectTo(device.macAdress),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
