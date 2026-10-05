import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/ui.dart';

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

  List<dynamic> _historyExpenses = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    final res = await _apiService.getExpenses();
    if (!mounted) return;
    if (res['status'] == 'success') {
      setState(() => _historyExpenses = res['data'] ?? []);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile =
          await _picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile != null) setState(() => _imageFile = pickedFile);
    } catch (e) {
      if (mounted) showMessage(context, "Foto tidak bisa diambil: $e", error: true);
    }
  }

  Future<void> _submitExpense() async {
    final int amount = int.tryParse(_amountController.text) ?? 0;
    if (amount <= 0 || _descController.text.trim().isEmpty) {
      showMessage(context, "Isi jumlah dan keterangan dulu.", error: true);
      return;
    }

    setState(() => _isLoading = true);
    final res = await _apiService.addExpense(
      amount: amount,
      description: _descController.text.trim(),
      imageFile: _imageFile,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['status'] == 'success') {
      _amountController.clear();
      _descController.clear();
      setState(() => _imageFile = null);
      FocusScope.of(context).unfocus();
      showMessage(context, "Pengeluaran ${rupiah(amount)} dicatat.",
          success: true);
      _fetchHistory();
    } else {
      showMessage(context, res['message'] ?? "Pengeluaran gagal dicatat.",
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final bool mobile = isMobile(context);
    final int total =
        _historyExpenses.fold(0, (sum, e) => sum + toInt(e['amount']));

    final form = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Catat pengeluaran",
              style: TextStyle(
                  color: theme.textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text("Uang yang diambil dari laci, misalnya untuk beli es batu atau gas.",
              style: TextStyle(color: theme.secondaryTextColor, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
                color: theme.textColor,
                fontSize: 20,
                fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              labelText: "Jumlah",
              prefixText: "Rp ",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: "Keterangan",
              hintText: "Contoh: beli es batu 2 karung",
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text("Foto nota"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text("Dari galeri"),
                ),
              ),
            ],
          ),
          if (_imageFile != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: theme.successColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text("Foto nota terlampir: ${_imageFile!.name}",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.secondaryTextColor)),
                  ),
                  IconButton(
                    tooltip: "Hapus foto",
                    onPressed: () => setState(() => _imageFile = null),
                    icon: Icon(Icons.close, size: 18, color: theme.dangerColor),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitExpense,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text("Simpan pengeluaran"),
            ),
          ),
        ],
      ),
    );

    final history = Panel(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text("Pengeluaran shift ini",
                    style: TextStyle(
                        color: theme.textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              Text(rupiah(total),
                  style: TextStyle(
                      color: theme.textColor, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          if (_historyExpenses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text("Belum ada pengeluaran di shift ini.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.secondaryTextColor)),
            ),
          for (final item in _historyExpenses)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.subtleColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['description'] ?? "",
                            style: TextStyle(color: theme.textColor)),
                        Text(
                          [
                            () {
                              final t = DateTime.tryParse(
                                      item['created_at']?.toString() ?? '')
                                  ?.toLocal();
                              return t == null
                                  ? ''
                                  : DateFormat('HH:mm').format(t);
                            }(),
                            if (item['receipt_image'] != null) 'ada foto nota',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: TextStyle(
                              color: theme.secondaryTextColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text("− ${rupiah(item['amount'])}",
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ],
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: RefreshIndicator(
        onRefresh: _fetchHistory,
        color: theme.primaryColor,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              mobile ? 16 : 32, mobile ? 16 : 28, mobile ? 16 : 32, 24),
          children: [
            PageHeader(
              title: "Kas keluar",
              subtitle: "Dikurangkan dari uang tunai saat tutup shift",
              compact: mobile,
            ),
            SizedBox(height: mobile ? 16 : 24),
            if (mobile) ...[
              form,
              const SizedBox(height: 16),
              history,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: form),
                  const SizedBox(width: 24),
                  Expanded(child: history),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
