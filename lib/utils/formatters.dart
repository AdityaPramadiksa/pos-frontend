import 'package:intl/intl.dart';

final NumberFormat _thousands = NumberFormat('#,##0', 'en_US');

int toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.round();
  return num.tryParse(value.toString())?.round() ?? 0;
}

/// 1500000 -> "1.500.000"
String formatNumber(dynamic value) =>
    _thousands.format(toInt(value)).replaceAll(',', '.');

/// 1500000 -> "Rp 1.500.000"
String rupiah(dynamic value) => 'Rp ${formatNumber(value)}';

const Map<String, String> platformLabels = {
  'gojek': 'Gojek / GoFood',
  'grab': 'Grab / GrabFood',
  'shopee': 'ShopeeFood',
};

String platformLabel(String? key) =>
    platformLabels[key?.toLowerCase()] ?? (key ?? '').toUpperCase();
