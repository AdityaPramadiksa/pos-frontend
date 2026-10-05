import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/sync_service.dart';
import 'ui.dart';

/// Status koneksi & antrean kirim. Tidak tampil bila online dan semua
/// transaksi sudah terkirim.
class SyncStatusBar extends StatelessWidget {
  /// true = versi kecil untuk rail tablet
  final bool compact;
  const SyncStatusBar({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    return ListenableBuilder(
      listenable: SyncService(),
      builder: (context, _) {
        final sync = SyncService();
        final int pending = sync.pendingCount;
        final int failed = sync.failedCount;
        if (sync.isOnline && pending == 0 && failed == 0) {
          return const SizedBox.shrink();
        }

        final Color color;
        final IconData icon;
        final String text;
        if (failed > 0) {
          color = theme.dangerColor;
          icon = Icons.error_outline;
          text = "$failed transaksi gagal terkirim";
        } else if (!sync.isOnline) {
          color = theme.warningInkColor;
          icon = Icons.cloud_off_outlined;
          text = pending > 0
              ? "Offline · $pending transaksi menunggu dikirim"
              : "Offline · transaksi tetap bisa dicatat";
        } else {
          color = theme.secondaryTextColor;
          icon = Icons.cloud_upload_outlined;
          text = "Mengirim $pending transaksi…";
        }

        if (compact) {
          return Tooltip(
            message: text,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showSyncSheet(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(height: 2),
                    Text(
                      failed > 0
                          ? "$failed gagal"
                          : (sync.isOnline ? "Kirim $pending" : "Offline"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                    if (!sync.isOnline && pending > 0)
                      Text("$pending antre",
                          style: TextStyle(
                              color: theme.secondaryTextColor, fontSize: 10.5)),
                  ],
                ),
              ),
            ),
          );
        }

        return Material(
          color: failed > 0
              ? theme.dangerSoftColor
              : (!sync.isOnline ? theme.warningSoftColor : theme.subtleColor),
          child: InkWell(
            onTap: () => showSyncSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text("Detail",
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          decoration: TextDecoration.underline)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Daftar transaksi yang belum/gagal terkirim
void showSyncSheet(BuildContext context) {
  final theme = Provider.of<ThemeProvider>(context, listen: false);
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => ListenableBuilder(
      listenable: SyncService(),
      builder: (sheetContext, _) {
        final sync = SyncService();
        final ops = sync.ops;
        final DateFormat time = DateFormat('HH:mm');

        return ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("Pengiriman ke server",
                    style: TextStyle(
                        color: theme.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  sync.isOnline
                      ? "Tersambung ke server."
                      : "Tidak tersambung. Transaksi tetap tersimpan di perangkat dan dikirim otomatis saat sinyal kembali. Jangan hapus aplikasi atau datanya.",
                  style: TextStyle(color: theme.secondaryTextColor),
                ),
                if (sync.lastSyncAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                        "Terakhir terkirim pukul ${time.format(sync.lastSyncAt!)}",
                        style: TextStyle(
                            color: theme.faintTextColor, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                if (ops.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text("Semua transaksi sudah terkirim.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.secondaryTextColor)),
                  ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: ops.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: theme.borderColor),
                    itemBuilder: (_, i) {
                      final op = ops[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(op.label,
                                      style: TextStyle(
                                          color: theme.textColor,
                                          fontWeight: FontWeight.w600)),
                                ),
                                StatusChip(
                                  op.isFailed ? "Gagal" : "Menunggu",
                                  tone: op.isFailed
                                      ? ChipTone.danger
                                      : ChipTone.neutral,
                                ),
                              ],
                            ),
                            Text("${time.format(op.createdAt)} · ${op.userName}",
                                style: TextStyle(
                                    color: theme.secondaryTextColor,
                                    fontSize: 12)),
                            if (op.isFailed) ...[
                              const SizedBox(height: 4),
                              Text(op.error ?? '',
                                  style: TextStyle(
                                      color: theme.dangerColor, fontSize: 13)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: () => sync.retry(op.id),
                                    child: const Text("Coba lagi"),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                        foregroundColor: theme.dangerColor),
                                    onPressed: () =>
                                        _confirmDiscard(sheetContext, op),
                                    child: const Text("Hapus"),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: sync.isSyncing || sync.pendingCount == 0
                        ? null
                        : () => sync.syncNow(),
                    icon: sync.isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync, size: 18),
                    label: Text(sync.isSyncing ? "Mengirim…" : "Kirim sekarang"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _confirmDiscard(BuildContext context, SyncOp op) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Hapus dari antrean?"),
      content: Text(
        "\"${op.label}\" tidak akan dikirim ke server. Hapus hanya bila admin sudah mencatatnya secara manual.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text("Batal"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text("Hapus"),
        ),
      ],
    ),
  );
  if (ok == true) await SyncService().discard(op.id);
}
