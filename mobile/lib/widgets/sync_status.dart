import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sync_provider.dart';
import '../services/sync_outbox.dart';

String _mb(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _changes(int n) => n == 1 ? '1 change' : '$n changes';

/// Wraps the whole app (via `MaterialApp.builder`) and surfaces the offline
/// outbox:
///   • a status strip at the top while changes are stuck on the phone,
///     turning amber / red as the offline space fills up;
///   • an attention dialog when it crosses 80% and again at 95%;
///   • a full-screen lock once the limit is reached — nothing is tappable
///     except "Refresh" until the backlog syncs.
class SyncShell extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final bool signedIn;
  const SyncShell({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.signedIn,
  });

  @override
  ConsumerState<SyncShell> createState() => _SyncShellState();
}

class _SyncShellState extends ConsumerState<SyncShell> {
  /// Highest alert already shown for the current backlog (0 = none,
  /// 1 = 80% alert, 2 = 95% alert). Resets when the backlog drains.
  int _alerted = 0;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(syncOutboxProvider, (_, box) => _maybeAlert(box));
  }

  void _maybeAlert(SyncOutbox box) {
    if (box.count == 0) {
      _alerted = 0;
      return;
    }
    if (!widget.signedIn || box.level == OutboxLevel.full) return;
    final stage = box.fill >= 0.95
        ? 2
        : box.fill >= SyncOutbox.criticalAt
            ? 1
            : 0;
    if (stage <= _alerted || _dialogOpen) return;
    _alerted = stage;
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null) return;
    HapticFeedback.heavyImpact();
    _dialogOpen = true;
    showDialog<void>(
      context: ctx,
      builder: (d) => _StorageAlert(nearlyFull: stage == 2),
    ).whenComplete(() => _dialogOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild only when something visible changes — not on every write that
    // passes through the outbox while online.
    final signedIn = widget.signedIn;
    final view = ref.watch(syncOutboxProvider.select((b) {
      final active = signedIn && b.count > 0;
      return (
        strip: active &&
            b.level != OutboxLevel.full &&
            (!b.online || b.fill >= SyncOutbox.warnAt),
        locked: active && b.level == OutboxLevel.full,
        count: b.count,
        pct: (b.fill * 100).round(),
        online: b.online,
        syncing: b.syncing,
      );
    }));
    final box = ref.read(syncOutboxProvider);

    // The tree shape is identical whether or not the strip shows, so the
    // app's Navigator (widget.child) is never re-mounted — toggling the
    // strip used to rebuild every open screen.
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              if (view.strip) _SyncStrip(box: box) else const SizedBox.shrink(),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: view.strip,
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
        if (view.locked) Positioned.fill(child: _SyncLock(box: box)),
      ],
    );
  }
}

class _SyncStrip extends StatelessWidget {
  final SyncOutbox box;
  const _SyncStrip({required this.box});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (box.fill * 100).clamp(0, 100).round();
    final (Color bg, Color fg, IconData icon, String text) =
        switch (box.level) {
      OutboxLevel.critical => (
          scheme.error,
          scheme.onError,
          Icons.warning_amber_rounded,
          'Offline space $pct% full — connect to the internet now',
        ),
      OutboxLevel.warn => (
          const Color(0xFFF59E0B),
          Colors.black,
          Icons.cloud_off,
          'Offline space $pct% full · ${_changes(box.count)} waiting',
        ),
      _ => (
          scheme.inverseSurface,
          scheme.onInverseSurface,
          Icons.cloud_off,
          box.online
              ? 'Syncing ${_changes(box.count)}…'
              : 'Offline · ${_changes(box.count)} saved on this phone',
        ),
    };
    return Material(
      color: bg,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
              if (box.syncing)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: fg)),
                )
              else
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: fg,
                      visualDensity: VisualDensity.compact),
                  onPressed: box.syncNow,
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageAlert extends ConsumerWidget {
  final bool nearlyFull;
  const _StorageAlert({required this.nearlyFull});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final box = ref.watch(syncOutboxProvider);
    final scheme = Theme.of(context).colorScheme;
    final pct = (box.fill * 100).clamp(0, 100).round();
    return AlertDialog(
      icon: Icon(Icons.cloud_off, color: scheme.error, size: 36),
      title: Text(nearlyFull
          ? 'Offline space almost full'
          : 'Please connect to the internet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_changes(box.count)} (${_mb(box.bytes)}) are saved only on this '
            "phone and haven't reached the cloud yet.\n\n"
            '${nearlyFull ? 'AERIS will lock very soon' : 'When offline space runs out AERIS will lock'} '
            'until you reconnect, so nothing is lost.',
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: box.fill.clamp(0.0, 1.0),
              minHeight: 8,
              color: scheme.error,
            ),
          ),
          const SizedBox(height: 6),
          Text('$pct% of ${_mb(SyncOutbox.limitBytes)} used',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later')),
        FilledButton.icon(
          onPressed: box.syncing
              ? null
              : () async {
                  final ok = await box.syncNow();
                  if (ok && context.mounted) Navigator.pop(context);
                },
          icon: const Icon(Icons.refresh),
          label: const Text('Sync now'),
        ),
      ],
    );
  }
}

/// Full-screen blocker shown when the offline outbox is full.
class _SyncLock extends StatefulWidget {
  final SyncOutbox box;
  const _SyncLock({required this.box});

  @override
  State<_SyncLock> createState() => _SyncLockState();
}

class _SyncLockState extends State<_SyncLock> {
  bool _stillOffline = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  Future<void> _refresh() async {
    setState(() => _stillOffline = false);
    final ok = await widget.box.syncNow();
    if (!ok && mounted) setState(() => _stillOffline = true);
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.box;
    final scheme = Theme.of(context).colorScheme;
    // Opaque-ish scrim that swallows every tap to the app underneath.
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Material(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_rounded,
                          size: 38, color: scheme.onErrorContainer),
                    ),
                    const SizedBox(height: 18),
                    const Text('Connect to the internet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text(
                      'Offline space is full. ${_changes(box.count)} '
                      '(${_mb(box.bytes)}) are stored safely on this phone '
                      'but need to reach the cloud before you can continue.\n\n'
                      'Turn on Wi-Fi or mobile data — AERIS unlocks '
                      'automatically as soon as they sync.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                          value: 1, minHeight: 8, color: scheme.error),
                    ),
                    const SizedBox(height: 6),
                    Text('${_mb(box.bytes)} of ${_mb(SyncOutbox.limitBytes)}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    if (_stillOffline) ...[
                      const SizedBox(height: 12),
                      Text('Still offline — check your connection.',
                          style: TextStyle(
                              color: scheme.error,
                              fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50)),
                        onPressed: box.syncing ? null : _refresh,
                        icon: box.syncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.refresh),
                        label: Text(box.syncing ? 'Checking…' : 'Refresh'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
