import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';
import 'local_store.dart';

/// Satu perintah ke server yang menunggu dikirim (pesanan, pelunasan bill,
/// tambah pesanan, kas keluar, ubah stok).
class SyncOp {
  final String id;
  final String type; // order | pay | add_items | expense | stock
  final String path;
  final Map<String, dynamic> body;
  final String label;
  final DateTime createdAt;
  final int? userId;
  final String userName;
  String token;

  /// Bentuk data seperti jawaban server, untuk ditampilkan selama belum terkirim
  final Map<String, dynamic>? snapshot;

  /// Kunci bill yang disentuh perintah ini (client_uuid atau id server)
  final String? billKey;
  final String? filePath;

  String status; // pending | failed
  String? error;
  int attempts;

  SyncOp({
    required this.id,
    required this.type,
    required this.path,
    required this.body,
    required this.label,
    required this.createdAt,
    required this.token,
    this.userId,
    this.userName = 'Kasir',
    this.snapshot,
    this.billKey,
    this.filePath,
    this.status = 'pending',
    this.error,
    this.attempts = 0,
  });

  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'path': path,
        'body': body,
        'label': label,
        'created_at': createdAt.toIso8601String(),
        'token': token,
        'user_id': userId,
        'user_name': userName,
        'snapshot': snapshot,
        'bill_key': billKey,
        'file_path': filePath,
        'status': status,
        'error': error,
        'attempts': attempts,
      };

  factory SyncOp.fromJson(Map<String, dynamic> j) => SyncOp(
        id: j['id'],
        type: j['type'],
        path: j['path'],
        body: Map<String, dynamic>.from(j['body'] ?? {}),
        label: j['label'] ?? '',
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
        token: j['token'] ?? '',
        userId: j['user_id'],
        userName: j['user_name'] ?? 'Kasir',
        snapshot: j['snapshot'] == null
            ? null
            : Map<String, dynamic>.from(j['snapshot']),
        billKey: j['bill_key'],
        filePath: j['file_path'],
        status: j['status'] ?? 'pending',
        error: j['error'],
        attempts: j['attempts'] ?? 0,
      );
}

/// Antrean kirim ke server. Semua transaksi masuk antrean dulu (tersimpan di
/// perangkat), lalu langsung dicoba dikirim. Kalau server tidak terjangkau,
/// transaksi tetap sah di aplikasi dan dikirim otomatis saat sinyal kembali,
/// berurutan sesuai waktu kejadian.
class SyncService extends ChangeNotifier {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const String _queueKey = 'sync_queue';
  static const int _maxServerErrors = 5;

  final List<SyncOp> _ops = [];
  bool _loaded = false;
  bool _online = true;
  bool _syncing = false;
  DateTime? _lastSyncAt;
  Timer? _timer;
  Future<void>? _lock;

  /// Perintah yang sedang ditunggu kasir di layar: kalau ditolak server,
  /// pesan errornya ditampilkan langsung dan perintahnya dibuang.
  final Set<String> _interactive = {};
  final Map<String, Map<String, dynamic>> _results = {};

  /// Bertambah setiap ada perintah yang berhasil terkirim, supaya halaman
  /// bisa memuat ulang data dari server.
  int syncedTick = 0;

  bool get isOnline => _online;
  bool get isSyncing => _syncing;
  DateTime? get lastSyncAt => _lastSyncAt;
  List<SyncOp> get ops => List.unmodifiable(_ops);
  List<SyncOp> get pendingOps => _ops.where((o) => o.isPending).toList();
  List<SyncOp> get failedOps => _ops.where((o) => o.isFailed).toList();
  int get pendingCount => _ops.where((o) => o.isPending).length;
  int get failedCount => _ops.where((o) => o.isFailed).length;

  bool hasUnsentFor(int? userId) =>
      _ops.any((o) => o.isPending && (userId == null || o.userId == userId));

  /// Kunci bill yang masih punya perubahan di perangkat (belum/gagal terkirim)
  Set<String> get touchedBillKeys =>
      _ops.where((o) => o.billKey != null).map((o) => o.billKey!).toSet();

  @visibleForTesting
  void debugReset() {
    _ops.clear();
    _interactive.clear();
    _results.clear();
    _loaded = false;
    _online = true;
    _syncing = false;
    _timer?.cancel();
    _timer = null;
    _lock = null;
    syncedTick = 0;
  }

  Future<void> load() async {
    if (_loaded) return;
    final saved = await LocalStore.readJson(_queueKey);
    _ops.clear();
    if (saved is List) {
      for (final j in saved) {
        try {
          _ops.add(SyncOp.fromJson(Map<String, dynamic>.from(j)));
        } catch (e) {
          debugPrint('Antrean rusak dilewati: $e');
        }
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() =>
      LocalStore.writeJson(_queueKey, _ops.map((o) => o.toJson()).toList());

  /// Matikan timer berkala (test widget tidak boleh menyisakan timer)
  @visibleForTesting
  static bool periodic = true;

  /// Mulai pengiriman berkala (dipanggil setelah kasir masuk)
  void start() {
    if (periodic) {
      _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    }
    unawaited(syncNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (pendingCount > 0) {
      await syncNow();
    } else if (!_online) {
      await ApiService().ping();
    }
  }

  /// Dipanggil ApiService setiap kali request berhasil/gagal menjangkau server
  void markReachable(bool reachable) {
    if (_online == reachable) return;
    _online = reachable;
    notifyListeners();
    // Sinyal kembali: kirim antrean tanpa menunggu timer
    if (reachable && pendingCount > 0 && !_syncing) unawaited(syncNow());
  }

  /// Simpan perintah lalu coba kirim. Hasil:
  /// - jawaban server (status success/error) bila server terjangkau
  /// - {'status': 'success', 'queued': true, 'data': snapshot} bila offline
  Future<Map<String, dynamic>> submit(SyncOp op) async {
    await load();
    _ops.add(op);
    _interactive.add(op.id);
    await _save();
    notifyListeners();

    // Sudah diketahui offline: jangan buat kasir menunggu timeout
    if (_online) {
      await syncNow();
    } else {
      unawaited(syncNow());
    }

    _interactive.remove(op.id);
    final result = _results.remove(op.id);
    if (result != null) return result;

    // Masih di antrean: tandai sebagai transaksi offline supaya server
    // menerimanya apa adanya (harga & total sesuai struk yang tercetak)
    op.body['offline'] = true;
    await _save();
    notifyListeners();
    return {
      'status': 'success',
      'queued': true,
      'data': op.snapshot,
      'message': 'Tersimpan di perangkat, dikirim otomatis saat online.',
    };
  }

  /// Kirim semua antrean berurutan (satu proses pada satu waktu)
  Future<void> syncNow() {
    final Future<void>? previous = _lock;
    final Future<void> next =
        (previous == null ? _drain() : previous.then((_) => _drain()))
            .catchError((e) {
      debugPrint('Sinkronisasi gagal: $e');
    });
    _lock = next;
    return next;
  }

  Future<void> _drain() async {
    await load();
    if (_ops.every((o) => !o.isPending)) return;
    _syncing = true;
    notifyListeners();
    int sent = 0;

    try {
      for (final op in List<SyncOp>.from(_ops)) {
        if (!op.isPending || !_ops.contains(op)) continue;

        final res = await _send(op);
        final int code = res['_http'] is int ? res['_http'] : 0;
        final bool interactive = _interactive.contains(op.id);

        if (code == 0) {
          // Server tidak terjangkau: berhenti, coba lagi nanti dari awal
          break;
        }

        if (code >= 200 && code < 300) {
          _ops.remove(op);
          sent++;
          if (interactive) _results[op.id] = res;
        } else if (interactive) {
          // Ditolak/error saat kasir menunggu: tampilkan alasannya langsung
          // (seperti sebelum ada mode offline), jangan diantrekan
          _ops.remove(op);
          _results[op.id] = res;
        } else if (code >= 500 || code == 429 || code == 408) {
          // Gangguan sementara di server: pertahankan urutan, coba lagi nanti
          op.attempts++;
          if (op.attempts >= _maxServerErrors) {
            _fail(op, res['message']?.toString() ?? 'Server error ($code)');
          }
          break;
        } else if (code == 401) {
          _fail(op,
              'Sesi ${op.userName} sudah tidak berlaku (PIN diganti?). Minta ${op.userName} masuk lagi saat online, lalu tekan Coba lagi.');
        } else {
          _fail(op, res['message']?.toString() ?? 'Ditolak server ($code)');
        }
        await _save();
        notifyListeners();
      }
    } finally {
      _syncing = false;
      if (sent > 0) {
        _lastSyncAt = DateTime.now();
        syncedTick++;
      }
      await _save();
      notifyListeners();
    }
  }

  void _fail(SyncOp op, String message) {
    op.status = 'failed';
    op.error = message;
  }

  Future<Map<String, dynamic>> _send(SyncOp op) async {
    if (op.type == 'expense') {
      List<int>? bytes;
      if (op.filePath != null && op.filePath!.isNotEmpty) {
        try {
          bytes = await XFile(op.filePath!).readAsBytes();
        } catch (_) {
          bytes = null; // foto nota sudah terhapus dari perangkat
        }
      }
      return ApiService().send(op.path, op.body,
          token: op.token,
          multipart: true,
          fileBytes: bytes,
          fileName: op.filePath?.split(RegExp(r'[\\/]')).last);
    }
    // Kasir sedang menunggu di layar: jangan lama-lama saat sinyal buruk.
    // Aman bila server ternyata sudah menerima: kiriman ulang tidak dobel.
    return ApiService().send(op.path, op.body,
        token: op.token,
        timeout: _interactive.contains(op.id)
            ? const Duration(seconds: 8)
            : const Duration(seconds: 20));
  }

  /// Kasir masuk lagi secara online: perintah miliknya yang gagal karena
  /// sesi lama dipakai ulang dengan token baru.
  Future<void> reauthorize(dynamic userId, String token) async {
    await load();
    final int? id = int.tryParse(userId?.toString() ?? '');
    bool changed = false;
    for (final op in _ops) {
      if (id != null && op.userId == id) {
        op.token = token;
        if (op.isFailed && (op.error ?? '').startsWith('Sesi ')) {
          op.status = 'pending';
          op.error = null;
        }
        changed = true;
      }
    }
    if (changed) {
      await _save();
      notifyListeners();
    }
  }

  /// Coba kirim ulang perintah yang gagal
  Future<void> retry(String id) async {
    for (final op in _ops) {
      if (op.id == id) {
        op.status = 'pending';
        op.error = null;
        op.attempts = 0;
      }
    }
    await _save();
    notifyListeners();
    await syncNow();
  }

  /// Buang perintah gagal (sudah dicatat manual oleh admin)
  Future<void> discard(String id) async {
    _ops.removeWhere((o) => o.id == id && o.isFailed);
    await _save();
    notifyListeners();
  }
}
