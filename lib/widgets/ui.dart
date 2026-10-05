import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/menu_model.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';

/// Foto menu. Bila admin belum mengunggah foto, tampil ikon sendok-garpu
/// abu-abu di kotak abu muda.
class MenuPhoto extends StatelessWidget {
  final MenuModel menu;
  final double radius;
  final double iconSize;

  const MenuPhoto({
    super.key,
    required this.menu,
    this.radius = 10,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final Widget placeholder = Container(
      color: theme.placeholderColor,
      alignment: Alignment.center,
      child: Icon(Icons.restaurant_menu,
          size: iconSize, color: theme.placeholderIconColor),
    );

    // Lewat jalur /api/menu-image supaya juga jalan di versi web (CORS)
    final String filename = menu.image.split('/').last;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.expand(
        child: filename.isEmpty
            ? placeholder
            : Image.network(
                "${ApiService.baseUrl}/menu-image/$filename",
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}

enum ChipTone { neutral, success, warning, danger, brand }

/// Label status kecil berwarna (Lunas, Habis, Belum dibayar, dst.)
class StatusChip extends StatelessWidget {
  final String label;
  final ChipTone tone;

  const StatusChip(this.label, {super.key, this.tone = ChipTone.neutral});

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<ThemeProvider>(context);
    final (Color bg, Color fg) = switch (tone) {
      ChipTone.success => (t.successSoftColor, t.successColor),
      ChipTone.warning => (t.warningSoftColor, t.warningInkColor),
      ChipTone.danger => (t.dangerSoftColor, t.dangerColor),
      ChipTone.brand => (t.primarySoftColor, t.primaryDarkColor),
      ChipTone.neutral => (t.subtleColor, t.secondaryTextColor),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Kotak putih bergaris tipis, wadah utama konten
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<ThemeProvider>(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.borderColor),
      ),
      child: child,
    );
  }
}

/// Judul halaman + subjudul, dipakai di semua tab
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool compact;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<ThemeProvider>(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textColor,
                  fontSize: compact ? 21 : 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                        color: t.secondaryTextColor,
                        fontSize: compact ? 12.5 : 13.5),
                  ),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

/// Baris label kiri, nilai kanan (ringkasan uang)
class AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;
  final double fontSize;

  const AmountRow(
    this.label,
    this.value, {
    super.key,
    this.bold = false,
    this.valueColor,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<ThemeProvider>(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? t.textColor : t.secondaryTextColor,
                fontSize: fontSize,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? t.textColor,
              fontSize: bold ? fontSize + 2 : fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tampilkan pesan singkat di bawah layar
void showMessage(BuildContext context, String message,
    {bool error = false, bool success = false}) {
  final t = Provider.of<ThemeProvider>(context, listen: false);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? t.dangerColor
            : success
                ? t.successColor
                : null,
        duration: Duration(seconds: error ? 4 : 2),
      ),
    );
}
