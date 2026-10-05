import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';

class PettyCashPage extends StatefulWidget {
  const PettyCashPage({super.key});

  @override
  State<PettyCashPage> createState() => _PettyCashPageState();
}

class _PettyCashPageState extends State<PettyCashPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  XFile? _imageFile;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  // List untuk menampung history pengeluaran
  List<dynamic> _historyExpenses = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory(); // Ambil data saat halaman dibuka
  }

  // Fungsi ambil history dari API
  Future<void> _fetchHistory() async {
    try {
      final res = await _apiService.getExpenses();
      if (!mounted) return;
      if (res['status'] == 'success') {
        setState(() {
          _historyExpenses = res['data'] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Gagal ambil history: $e");
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
      );
      if (pickedFile != null) {
        setState(() {
          _imageFile = pickedFile;
        });
      }
    } catch (e) {
      debugPrint("Gagal ambil foto: $e");
    }
  }

  // --- POPUP SUKSES ---
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final theme = Provider.of<ThemeProvider>(context);
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: theme.cardColor,
          child: Padding(
            padding: EdgeInsets.all(isMobile(context) ? 16 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 80),
                const SizedBox(height: 20),
                Text(
                  "Berhasil Dicatat!",
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Data pengeluaran sudah masuk ke laporan.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.secondaryTextColor),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context); // Tutup dialog
                      _fetchHistory(); // Refresh list bawah
                    },
                    child: const Text(
                      "OK",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitExpense() async {
    if (_amountController.text.isEmpty || _descController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Nominal dan Keterangan wajib diisi!"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    int amount = int.tryParse(
          _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Nominal harus lebih dari 0!"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final res = await _apiService.addExpense(
      amount: amount,
      description: _descController.text,
      imageFile: _imageFile,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['status'] == 'success') {
      // Bersihkan form
      _amountController.clear();
      _descController.clear();
      setState(() => _imageFile = null);

      // Tampilkan Popup Sukses
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? "Gagal menyimpan"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        elevation: 0,
        // Halaman ini adalah tab di sidebar, bukan halaman yang di-push,
        // jadi tidak ada tombol kembali (pop akan menutup seluruh layout).
        automaticallyImplyLeading: false,
        title: Text(
          "Petty Cash / Kas Keluar",
          style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile(context) ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- FORM INPUT ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.borderColor),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: "Nominal (Rp)",
                      prefixIcon: Icon(Icons.money, color: theme.primaryColor),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _descController,
                    style: TextStyle(color: theme.textColor),
                    decoration: InputDecoration(
                      labelText: "Keterangan",
                      prefixIcon: Icon(Icons.notes, color: theme.primaryColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- TOMBOL KAMERA & GALERI ---
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Kamera"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text("Galeri"),
                  ),
                ),
              ],
            ),

            if (_imageFile != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Foto nota terlampir: ${_imageFile!.name}",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.secondaryTextColor),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _imageFile = null),
                      icon: const Icon(Icons.close,
                          color: Colors.redAccent, size: 18),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitExpense,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "SIMPAN",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 40),

            // --- HISTORY SECTION ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Pengeluaran Shift Ini",
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Total: - ${rupiah(_historyExpenses.fold<int>(0, (sum, e) => sum + toInt(e['amount'])))}",
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _historyExpenses.isEmpty
                ? Center(
                    child: Text(
                      "Belum ada pengeluaran di shift ini",
                      style: TextStyle(color: theme.secondaryTextColor),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _historyExpenses.length,
                    itemBuilder: (context, index) {
                      final item = _historyExpenses[index];
                      return Card(
                        color: theme.cardColor,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.withOpacity(0.1),
                            child: const Icon(
                              Icons.arrow_downward,
                              color: Colors.red,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            item['description'] ?? "",
                            style: TextStyle(
                              color: theme.textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            item['created_at']?.split('T')[0] ?? "",
                            style: TextStyle(
                              color: theme.secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            "- ${rupiah(item['amount'])}",
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
