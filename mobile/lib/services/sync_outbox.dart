import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// How full the offline outbox is, driving the banner / alerts / lock.
enum OutboxLevel {
  /// Nothing waiting (or it's syncing normally).
  clear,

  /// Changes waiting, plenty of room.
  pending,

  /// ≥ [SyncOutbox.warnAt] of the limit — amber banner.
  warn,

  /// ≥ [SyncOutbox.criticalAt] of the limit — red banner + alert dialog.
  critical,

  /// At / over the limit — the app locks until it can sync.
  full,
}

/// Durable, size-bounded local outbox for every Firestore write the app makes.
///
/// Each write is (1) recorded here in SQLite, (2) handed to Firestore — whose
/// local cache makes it show up in the UI instantly — and (3) removed from
/// here the moment the server acknowledges it. So while the phone is offline
/// the rows accumulate; when the link returns they drain and the space is
/// freed (the DB is VACUUMed once empty).
///
/// Why not rely on Firestore's own offline queue alone? It's opaque: we can't
/// see how much is waiting, bound it, or warn the user. This ledger gives us
/// that, and doubles as a safety net — on every cold start any rows still
/// here are re-sent (writes are idempotent full-doc sets / deletes).
///
/// Writes return as soon as they're queued locally — callers never hang
/// waiting for a server ack that can't arrive offline.
class SyncOutbox extends ChangeNotifier {
  SyncOutbox._();
  static final SyncOutbox instance = SyncOutbox._();

  /// Hard cap on unsynced data kept on the phone. Roughly 5,000 typical
  /// transaction edits, or a few dozen receipt photos.
  static const int limitBytes = 5 * 1024 * 1024;
  static const double warnAt = 0.5;
  static const double criticalAt = 0.8;

  /// String sentinel for `FieldValue.serverTimestamp()` inside JSON-safe maps.
  static const String serverTimestamp = '__aeris_fv_serverTimestamp__';

  static const _table = 'outbox';

  Database? _db;
  Future<Database?>? _opening;
  String? _uid;
  final Set<String> _replayed = {};
  final Set<String> _ackedEarly = {};
  Timer? _probeTimer;
  int _failStreak = 0;
  int _peakBytes = 0;

  int _count = 0;
  int _bytes = 0;
  bool _online = true;
  bool _syncing = false;
  DateTime? _lastSynced;

  int get count => _count;
  int get bytes => _bytes;
  bool get online => _online;
  bool get syncing => _syncing;
  DateTime? get lastSynced => _lastSynced;
  double get fill => (_bytes / limitBytes).clamp(0.0, 1.5);

  OutboxLevel get level {
    if (_count == 0) return OutboxLevel.clear;
    final f = _bytes / limitBytes;
    if (f >= 1) return OutboxLevel.full;
    if (f >= criticalAt) return OutboxLevel.critical;
    if (f >= warnAt) return OutboxLevel.warn;
    return OutboxLevel.pending;
  }

  // ── Storage ────────────────────────────────────────────────

  Future<Database?> _database() {
    if (_db != null) return Future.value(_db);
    return _opening ??= () async {
      try {
        final dir = await getDatabasesPath();
        _db = await openDatabase(
          p.join(dir, 'aeris_outbox.db'),
          version: 1,
          onCreate: (db, _) => db.execute('''
            CREATE TABLE $_table (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              token TEXT NOT NULL,
              uid TEXT NOT NULL,
              path TEXT NOT NULL,
              op TEXT NOT NULL,
              data TEXT,
              merge INTEGER NOT NULL DEFAULT 0,
              bytes INTEGER NOT NULL,
              created INTEGER NOT NULL
            )'''),
        );
        return _db;
      } catch (e) {
        // e.g. a background isolate without the sqflite plugin — writes then
        // go straight to Firestore (its own offline queue still applies).
        debugPrint('[outbox] unavailable: $e');
        _opening = null;
        return null;
      }
    }();
  }

  // ── Writes ─────────────────────────────────────────────────

  /// Full-doc set (or merge) of [json] — a JSON-safe map that may contain
  /// [Timestamp]s and the [serverTimestamp] sentinel.
  Future<void> set(DocumentReference<Map<String, dynamic>> ref,
          Map<String, dynamic> json,
          {bool merge = false}) =>
      _write(ref, 'set', json, merge);

  Future<void> delete(DocumentReference<Map<String, dynamic>> ref) =>
      _write(ref, 'delete', null, false);

  Future<void> _write(DocumentReference<Map<String, dynamic>> ref, String op,
      Map<String, dynamic>? json, bool merge) async {
    final token = const Uuid().v4();
    String? encoded;
    var recordable = true;
    try {
      encoded = json == null ? null : jsonEncode(_toJson(json));
    } catch (e) {
      // Not JSON-representable (e.g. a FieldValue we don't map) — still write
      // it, Firestore's own queue will carry it; it just isn't tracked here.
      debugPrint('[outbox] untracked write ${ref.path}: $e');
      recordable = false;
    }
    // Issue the Firestore write synchronously so local write order is exactly
    // call order; the ledger row follows right after.
    _send(ref, op, json, merge).then(
      (_) => _ack(token),
      onError: (Object e) {
        // A server rejection (rules, bad data) will never succeed on retry —
        // drop it rather than let it block the queue forever.
        debugPrint('[outbox] write rejected ${ref.path}: $e');
        _ack(token);
      },
    );
    if (!recordable) return;
    final db = await _database();
    if (db == null) return;
    final uid = _uidOf(ref.path);
    final size = ref.path.length + (encoded?.length ?? 0);
    try {
      await db.transaction((tx) async {
        // A full overwrite or delete supersedes earlier pending writes to the
        // same doc — keep only the latest so storage isn't wasted.
        if (!merge) {
          await tx.delete(_table,
              where: 'uid = ? AND path = ?', whereArgs: [uid, ref.path]);
        }
        await tx.insert(_table, {
          'token': token,
          'uid': uid,
          'path': ref.path,
          'op': op,
          'data': encoded,
          'merge': merge ? 1 : 0,
          'bytes': size,
          'created': DateTime.now().millisecondsSinceEpoch,
        });
      });
      if (_ackedEarly.remove(token)) {
        await db.delete(_table, where: 'token = ?', whereArgs: [token]);
      }
    } catch (e) {
      debugPrint('[outbox] record failed: $e');
    }
    await _recount();
  }

  Future<void> _send(DocumentReference<Map<String, dynamic>> ref, String op,
      Map<String, dynamic>? json, bool merge) {
    if (op == 'delete') return ref.delete();
    return ref.set(_toFirestore(json!), merge ? SetOptions(merge: true) : null);
  }

  Future<void> _ack(String token) async {
    final db = _db;
    if (db == null) {
      _ackedEarly.add(token);
      return;
    }
    final n = await db.delete(_table, where: 'token = ?', whereArgs: [token]);
    if (n == 0) _ackedEarly.add(token); // row not inserted yet
    if (n > 0) {
      _online = true;
      _lastSynced = DateTime.now();
      await _recount();
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────

  /// Call once a user is signed in. Re-sends anything left over from a
  /// previous run, then keeps probing connectivity while work is pending.
  Future<void> startFor(String uid) async {
    _uid = uid;
    final db = await _database();
    if (db != null && _replayed.add(uid)) {
      final rows = await db.query(_table,
          where: 'uid = ?', whereArgs: [uid], orderBy: 'id ASC');
      for (final r in rows) {
        final ref = FirebaseFirestore.instance.doc(r['path'] as String);
        final data = r['data'] as String?;
        final token = r['token'] as String;
        _send(
          ref,
          r['op'] as String,
          data == null
              ? null
              : (jsonDecode(data) as Map).cast<String, dynamic>(),
          (r['merge'] as int) == 1,
        ).then((_) => _ack(token), onError: (Object e) => _ack(token));
      }
    }
    await _recount();
    if (_count > 0) unawaited(syncNow());
  }

  /// Re-reads the ledger (it may have been written by the background SMS
  /// isolate) and refreshes the published stats.
  Future<void> refresh() => _recount();

  /// Checks connectivity and, if online, waits for Firestore to flush. Returns
  /// true when everything pending has reached the server.
  Future<bool> syncNow() async {
    if (_syncing) return _count == 0;
    _syncing = true;
    notifyListeners();
    try {
      await _recount();
      if (_count == 0) return true;
      _online = await _probe();
      if (!_online) return false;
      final db = await _database();
      final uid = _uid;
      final maxRow = (db == null || uid == null)
          ? null
          : Sqflite.firstIntValue(await db
              .rawQuery('SELECT MAX(id) FROM $_table WHERE uid = ?', [uid]));
      try {
        await FirebaseFirestore.instance.enableNetwork();
        await FirebaseFirestore.instance
            .waitForPendingWrites()
            .timeout(const Duration(seconds: 25));
        // Every write queued before we started is now on the server (our own
        // rows were replayed into Firestore's queue in [startFor]).
        if (db != null && maxRow != null && _replayed.contains(uid)) {
          await db.delete(_table,
              where: 'uid = ? AND id <= ?', whereArgs: [uid, maxRow]);
        }
        _lastSynced = DateTime.now();
      } on TimeoutException {
        // Link is up but slow; per-write acks will keep draining the queue.
      }
      await _recount();
      return _count == 0;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<bool> _probe() async {
    try {
      final r = await InternetAddress.lookup('firestore.googleapis.com')
          .timeout(const Duration(seconds: 5));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recount() async {
    final db = await _database();
    final uid = _uid;
    var count = 0, bytes = 0;
    if (db != null && uid != null) {
      final r = await db.rawQuery(
          'SELECT COUNT(*) AS c, COALESCE(SUM(bytes), 0) AS b '
          'FROM $_table WHERE uid = ?',
          [uid]);
      count = (r.first['c'] as int?) ?? 0;
      bytes = (r.first['b'] as int?) ?? 0;
    }
    if (bytes > _peakBytes) _peakBytes = bytes;
    final drained = _count > 0 && count == 0;
    final changed = count != _count || bytes != _bytes;
    _count = count;
    _bytes = bytes;
    if (drained) {
      _online = true;
      _lastSynced = DateTime.now();
      // Give the freed pages back to the OS — only after a real offline
      // backlog. VACUUM rewrites the file, so doing it after every normal
      // online write was pure I/O churn.
      final big = _peakBytes > 256 * 1024;
      _peakBytes = 0;
      if (big) {
        try {
          final total = Sqflite.firstIntValue(
              await db!.rawQuery('SELECT COUNT(*) FROM $_table'));
          if (total == 0) await db.execute('VACUUM');
        } catch (_) {}
      }
    }
    _scheduleProbe();
    if (changed || drained) notifyListeners();
  }

  /// While anything is pending, re-check the link every 20 s so the queue
  /// drains (and the lock lifts) without the user having to do anything.
  void _scheduleProbe() {
    if (_count == 0) {
      _probeTimer?.cancel();
      _probeTimer = null;
      return;
    }
    if (_probeTimer != null) return;
    _probeTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _checkLink());
    // A normal online write acks within a second or two; if it's still here
    // after a few seconds, find out whether we're offline so the UI can say so.
    Timer(const Duration(seconds: 3), () {
      if (_count > 0) _checkLink();
    });
  }

  Future<void> _checkLink() async {
    if (await _probe()) {
      _failStreak = 0;
      _online = true;
      unawaited(syncNow());
      return;
    }
    // Two misses in a row before saying "offline", so one slow DNS lookup
    // doesn't flash the status strip on and off.
    if (++_failStreak < 2) {
      Timer(const Duration(seconds: 4), () {
        if (_count > 0) _checkLink();
      });
      return;
    }
    if (_online) {
      _online = false;
      notifyListeners();
    }
  }

  // ── JSON <-> Firestore value mapping ───────────────────────

  static String _uidOf(String path) {
    final parts = path.split('/');
    return parts.length > 1 && parts[0] == 'users' ? parts[1] : '';
  }

  static Object? _toJson(Object? v) {
    if (v is Timestamp) return {'__ts': v.millisecondsSinceEpoch};
    if (v is DateTime) return {'__ts': v.millisecondsSinceEpoch};
    if (v is Map) {
      return {for (final e in v.entries) e.key.toString(): _toJson(e.value)};
    }
    if (v is List) return [for (final x in v) _toJson(x)];
    return v;
  }

  static Map<String, dynamic> _toFirestore(Map<String, dynamic> m) =>
      {for (final e in m.entries) e.key: _fromJson(e.value)};

  static Object? _fromJson(Object? v) {
    if (v == serverTimestamp) return FieldValue.serverTimestamp();
    if (v is Timestamp) return v;
    if (v is Map) {
      if (v.length == 1 && v['__ts'] is int) {
        return Timestamp.fromMillisecondsSinceEpoch(v['__ts'] as int);
      }
      return {for (final e in v.entries) e.key.toString(): _fromJson(e.value)};
    }
    if (v is List) return [for (final x in v) _fromJson(x)];
    return v;
  }

  /// Forces the published stats — for widget tests of the banner / lock.
  @visibleForTesting
  void debugSetStats({required int count, required int bytes, bool? online}) {
    _count = count;
    _bytes = bytes;
    if (online != null) _online = online;
    notifyListeners();
  }

  @visibleForTesting
  static Map<String, dynamic> roundTrip(Map<String, dynamic> m) => _toFirestore(
      (jsonDecode(jsonEncode(_toJson(m))) as Map).cast<String, dynamic>());
}
