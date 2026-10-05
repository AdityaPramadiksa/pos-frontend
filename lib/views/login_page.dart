import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../utils/responsive.dart';
import '../widgets/ui.dart';
import 'main_layout.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String _pin = "";
  bool _isLoading = false;

  void _handlePinInput(String value) {
    if (_isLoading) return;
    if (_pin.length < 4) {
      setState(() => _pin += value);
      if (_pin.length == 4) _login();
    }
  }

  void _deleteDigit() {
    if (_isLoading || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _login() async {
    setState(() => _isLoading = true);
    final result = await ApiService().loginPin(_pin);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['status'] == 'success') {
      if (result['offline'] == true) {
        showMessage(context, result['message']);
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    } else {
      setState(() => _pin = "");
      showMessage(context, result['message'] ?? 'PIN salah. Coba lagi.',
          error: true);
    }
  }

  // Ganti alamat server tanpa build ulang: alamat hosting, atau IP laptop
  // di WiFi warung (berubah saat pindah WiFi)
  void _showServerDialog() {
    final controller = TextEditingController(text: ApiService.ipAddress);
    String? testResult;
    bool testing = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text("Alamat server"),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: "Alamat server",
                    hintText: "pos.namawarung.com atau 192.168.1.10",
                    helperText:
                        "Nama domain memakai https. IP memakai port 8000 bila tidak ditulis.",
                    helperMaxLines: 2,
                  ),
                ),
                if (testResult != null) ...[
                  const SizedBox(height: 12),
                  Text(testResult!,
                      style: TextStyle(
                          color: testResult!.startsWith('Tersambung')
                              ? Provider.of<ThemeProvider>(context,
                                      listen: false)
                                  .successColor
                              : Provider.of<ThemeProvider>(context,
                                      listen: false)
                                  .dangerColor)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: testing
                  ? null
                  : () async {
                      final String previous = ApiService.ipAddress;
                      setDialog(() => testing = true);
                      ApiService.ipAddress = controller.text.trim();
                      final bool ok = await ApiService().ping();
                      final String url = ApiService.serverRoot;
                      ApiService.ipAddress = previous;
                      if (!dialogContext.mounted) return;
                      setDialog(() {
                        testing = false;
                        testResult = ok
                            ? "Tersambung ke $url"
                            : "Tidak tersambung ke $url";
                      });
                    },
              child: Text(testing ? "Mengecek…" : "Tes koneksi"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              onPressed: () async {
                await ApiService.saveServerAddress(controller.text);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                setState(() {});
              },
              child: const Text("Simpan"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final bool mobile = isMobile(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(mobile ? 24 : 32),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.borderColor),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text("MG",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                        ),
                        const SizedBox(height: 14),
                        Text("Kasir Men Gede",
                            style: TextStyle(
                                color: theme.textColor,
                                fontSize: 20,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text("Masukkan PIN 4 angka",
                            style: TextStyle(color: theme.secondaryTextColor)),
                        const SizedBox(height: 24),

                        // Titik PIN
                        Semantics(
                          label: "${_pin.length} dari 4 angka PIN terisi",
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              4,
                              (index) => Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 9),
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _pin.length > index
                                      ? theme.inkColor
                                      : Colors.transparent,
                                  border: Border.all(
                                      color: _pin.length > index
                                          ? theme.inkColor
                                          : theme.fieldBorderColor,
                                      width: 1.6),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Papan angka
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisExtent: 60,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                          itemCount: 12,
                          itemBuilder: (context, index) {
                            if (index == 9) return const SizedBox();
                            if (index == 10) return _buildNumBtn("0", theme);
                            if (index == 11) {
                              return IconButton(
                                tooltip: "Hapus angka",
                                onPressed: _deleteDigit,
                                icon: Icon(Icons.backspace_outlined,
                                    color: theme.secondaryTextColor),
                              );
                            }
                            return _buildNumBtn("${index + 1}", theme);
                          },
                        ),
                        SizedBox(
                          height: 36,
                          child: _isLoading
                              ? const Padding(
                                  padding: EdgeInsets.only(top: 14),
                                  child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _showServerDialog,
                    icon: Icon(Icons.dns_outlined,
                        size: 16, color: theme.secondaryTextColor),
                    label: Text("Server ${ApiService.ipAddress} · Ubah",
                        style: TextStyle(
                            color: theme.secondaryTextColor,
                            fontWeight: FontWeight.w500,
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumBtn(String val, ThemeProvider theme) {
    return Material(
      color: theme.subtleColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _handlePinInput(val),
        child: Center(
          child: Text(
            val,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
