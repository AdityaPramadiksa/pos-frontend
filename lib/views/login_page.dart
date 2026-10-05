import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive.dart';
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

  void _login() async {
    setState(() => _isLoading = true);
    final result = await ApiService().loginPin(_pin);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['status'] == 'success') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    } else {
      setState(() => _pin = ""); // Reset
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'PIN Salah!'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // Ganti alamat server tanpa build ulang (IP laptop berubah saat pindah WiFi)
  void _showServerDialog() {
    final controller = TextEditingController(text: ApiService.ipAddress);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D303E),
        title: const Text(
          "Alamat Server",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "IP laptop server",
            hintText: "contoh: 192.168.1.10",
            helperText: "Tanpa port = 8000",
            labelStyle: TextStyle(color: Colors.grey),
            hintStyle: TextStyle(color: Colors.grey),
            helperStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("BATAL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA7C69),
            ),
            onPressed: () async {
              await ApiService.saveServerAddress(controller.text);
              if (!context.mounted) return;
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text("SIMPAN", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1D2B),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: const Color(0xFF2D303E),
        tooltip: "Alamat server: ${ApiService.ipAddress}",
        onPressed: _showServerDialog,
        child: const Icon(Icons.settings, color: Colors.grey),
      ),
      body: Center(
        // 🔥 TAMBAHKAN SINGLE CHILD SCROLL VIEW DI SINI 🔥
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            margin: const EdgeInsets.all(16),
            padding: EdgeInsets.all(isMobile(context) ? 24 : 40),
            decoration: BoxDecoration(
              color: const Color(0xFF2D303E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF393C49)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.restaurant_menu,
                  size: 60,
                  color: Color(0xFFEA7C69),
                ),
                const SizedBox(height: 16),
                const Text(
                  'POS BABI GULING',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),

                // PIN Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _pin.length > index
                            ? const Color(0xFFEA7C69)
                            : Colors.transparent,
                        border: Border.all(color: const Color(0xFFEA7C69)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // Numpad
                GridView.builder(
                  shrinkWrap: true,
                  physics:
                      const NeverScrollableScrollPhysics(), // 🔥 MATIKAN SCROLL DALAM GRID BIAR NGGAK BENTROK
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.5,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    if (index == 9) return const SizedBox();
                    if (index == 10) return _buildNumBtn("0");
                    if (index == 11) {
                      return IconButton(
                        onPressed: () => setState(
                          () => _pin = _pin.isNotEmpty
                              ? _pin.substring(0, _pin.length - 1)
                              : "",
                        ),
                        icon: const Icon(Icons.backspace, color: Colors.white),
                      );
                    }
                    return _buildNumBtn("${index + 1}");
                  },
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: CircularProgressIndicator(color: Color(0xFFEA7C69)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumBtn(String val) {
    return InkWell(
      onTap: () => _handlePinInput(val),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1F1D2B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          val,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
