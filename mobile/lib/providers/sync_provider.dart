import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sync_outbox.dart';

/// Live view of the offline outbox (pending count, bytes, online, level).
///
/// The outbox is a process-wide singleton, so this only *listens* to it —
/// a ChangeNotifierProvider would dispose it when the scope goes away.
final syncOutboxProvider = Provider<SyncOutbox>((ref) {
  final box = SyncOutbox.instance;
  void onChange() => ref.notifyListeners();
  box.addListener(onChange);
  ref.onDispose(() => box.removeListener(onChange));
  return box;
});
