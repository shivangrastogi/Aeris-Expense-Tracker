import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// The app's root navigator — its Overlay is where toasts are drawn, above
/// every screen and the bottom nav.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// App-wide toasts that replace Material snackbars.
///
/// Why not plain snackbars: in this Flutter version a SnackBar with an action
/// ("UNDO", "Add another") *persists* until tapped, the floating one fades and
/// grows in slowly, and it sits on top of the bottom nav. A toast here:
/// slides up from the bottom, always auto-dismisses (actions just get a bit
/// longer), has a × button, can be swiped down, and slides away quickly.
///
/// Call sites keep building a normal [SnackBar] and use
/// `ScaffoldMessenger.of(context).showToast(bar)` — see [AerisToastX].
class AerisToast {
  AerisToast._();

  static _ToastEntry? _current;

  /// Shows [bar] as a toast; the previous one (if any) slides away at once.
  static ToastController show(SnackBar bar) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) throw StateError('No app overlay');
    // A new toast replaces the old one instantly — no stacking, no waiting.
    _current?.dismiss(SnackBarClosedReason.hide, animate: false);
    final entry = _ToastEntry(bar);
    _current = entry;
    entry.insert(overlay);
    entry.closed.whenComplete(() {
      if (identical(_current, entry)) _current = null;
    });
    return ToastController(
        entry.closed, () => entry.dismiss(SnackBarClosedReason.hide));
  }

  /// Hides the visible toast, if any.
  static void hide() => _current?.dismiss(SnackBarClosedReason.hide);

  static bool get _available => appNavigatorKey.currentState?.overlay != null;
}

/// Handle to one toast: await [closed] to learn how it went away (same
/// reasons as a snackbar, so UNDO logic keeps working).
class ToastController {
  final Future<SnackBarClosedReason> closed;
  final VoidCallback close;
  const ToastController(this.closed, this.close);
}

/// Drop-in for `showSnackBar` / `hideCurrentSnackBar`. Falls back to the
/// real snackbar when there's no app navigator (widget tests that build
/// their own MaterialApp).
extension AerisToastX on ScaffoldMessengerState {
  ToastController showToast(SnackBar bar) {
    if (AerisToast._available) return AerisToast.show(bar);
    final c = showSnackBar(bar);
    return ToastController(c.closed, c.close);
  }

  void hideToast() {
    AerisToast.hide();
    hideCurrentSnackBar();
  }
}

class _ToastEntry {
  final SnackBar bar;
  final _closed = Completer<SnackBarClosedReason>();
  final _key = GlobalKey<_ToastViewState>();
  OverlayEntry? _overlayEntry;
  bool _dismissing = false;

  _ToastEntry(this.bar);

  Future<SnackBarClosedReason> get closed => _closed.future;

  void insert(OverlayState overlay) {
    _overlayEntry = OverlayEntry(
      builder: (_) => _ToastView(
        key: _key,
        bar: bar,
        onDismiss: dismiss,
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  /// Plays the quick exit slide (unless [animate] is off or it was swiped
  /// away — already off screen), then removes the entry.
  Future<void> dismiss(SnackBarClosedReason reason,
      {bool animate = true}) async {
    if (_dismissing) return;
    _dismissing = true;
    if (!_closed.isCompleted) _closed.complete(reason);
    if (animate && reason != SnackBarClosedReason.swipe) {
      await _key.currentState?.animateOut();
    }
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _ToastView extends StatefulWidget {
  final SnackBar bar;
  final void Function(SnackBarClosedReason) onDismiss;
  const _ToastView({super.key, required this.bar, required this.onDismiss});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 1.4),
    end: Offset.zero,
  ).animate(CurvedAnimation(
      parent: _ctrl, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    // Actions get a little longer to reach, but nothing stays up forever.
    final base = widget.bar.duration;
    final visible =
        widget.bar.action != null && base < const Duration(seconds: 5)
            ? const Duration(seconds: 5)
            : base;
    _timer =
        Timer(visible, () => widget.onDismiss(SnackBarClosedReason.timeout));
  }

  Future<void> animateOut() async {
    _timer?.cancel();
    if (!mounted) return;
    await _ctrl.reverse();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    // Above the bottom nav (and above the keyboard when it's open).
    final bottom = (mq.viewInsets.bottom > 0
            ? mq.viewInsets.bottom
            : mq.viewPadding.bottom) +
        104;
    final bg = widget.bar.backgroundColor ??
        (dark ? const Color(0xFF1B2536) : AerisColors.inkLight);
    final fg = dark ? AerisColors.inkDark : Colors.white;
    final action = widget.bar.action;

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _ctrl,
          child: Dismissible(
            key: const ValueKey('toast'),
            direction: DismissDirection.down,
            onDismissed: (_) => widget.onDismiss(SnackBarClosedReason.swipe),
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AerisColors.arc
                            .withValues(alpha: dark ? 0.28 : 0.0)),
                    boxShadow: [
                      BoxShadow(
                        color: (dark ? AerisColors.arc : Colors.black)
                            .withValues(alpha: dark ? 0.14 : 0.22),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(children: [
                    Container(
                      width: 3,
                      height: 22,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: AerisColors.arc,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: DefaultTextStyle(
                        style: TextStyle(
                            fontFamily: kFontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: fg),
                        child: widget.bar.content,
                      ),
                    ),
                    if (action != null)
                      TextButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          action.onPressed();
                          widget.onDismiss(SnackBarClosedReason.action);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor:
                              dark ? AerisColors.arc : const Color(0xFF67E8F9),
                          textStyle: const TextStyle(
                              fontFamily: kFontFamily,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4),
                        ),
                        child: Text(action.label.toUpperCase()),
                      ),
                    IconButton(
                      tooltip: 'Dismiss',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: fg.withValues(alpha: 0.7)),
                      onPressed: () =>
                          widget.onDismiss(SnackBarClosedReason.dismiss),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
