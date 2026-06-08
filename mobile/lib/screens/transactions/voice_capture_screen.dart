import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/category_rules.dart';
import '../../services/nlu_parser.dart';
import '../../services/voice_service.dart';
import '../../utils/formatters.dart';

enum _Phase { starting, listening, processing, review, denied, unavailable }

/// Full-screen, ChatGPT-voice-mode-style capture: tap once, speak naturally
/// (one or many transactions), and AERIS parses them on-device. An animated orb
/// reacts to your voice; the recognised text is parsed into editable entries you
/// can save in one tap.
class VoiceCaptureScreen extends ConsumerStatefulWidget {
  const VoiceCaptureScreen({super.key});
  @override
  ConsumerState<VoiceCaptureScreen> createState() => _VoiceCaptureScreenState();
}

class _VoiceCaptureScreenState extends ConsumerState<VoiceCaptureScreen> {
  _Phase _phase = _Phase.starting;
  StreamSubscription<VoiceEvent>? _sub;
  String _partial = '';
  double _rms = 0;
  String _error = '';
  List<NluResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _sub?.cancel();
    VoiceService.instance.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() {
      _phase = _Phase.starting;
      _partial = '';
      _results = const [];
    });
    if (!await VoiceService.instance.isAvailable()) {
      if (mounted) setState(() => _phase = _Phase.unavailable);
      return;
    }
    _sub?.cancel();
    _sub = VoiceService.instance.events().listen(_onEvent);
    // Native side requests RECORD_AUDIO if needed (handled in MainActivity so it
    // doesn't collide with the telephony plugin's permission handler). A denial
    // comes back as an 'error' event → the denied UI below.
    await VoiceService.instance.start();
    if (mounted) setState(() => _phase = _Phase.listening);
  }

  void _onEvent(VoiceEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case 'rms':
        setState(() => _rms = (e.value as num?)?.toDouble() ?? 0);
        break;
      case 'partial':
        setState(() => _partial = e.value as String? ?? _partial);
        break;
      case 'status':
        if (e.value == 'processing') setState(() => _phase = _Phase.processing);
        break;
      case 'final':
        _onFinal(e.value as String? ?? '');
        break;
      case 'error':
        setState(() {
          _phase = _Phase.denied;
          _error = _humanError(e.value?.toString());
        });
        break;
    }
  }

  String _humanError(String? code) {
    // Android SpeechRecognizer error codes; 7 = no match, 6 = timeout.
    if (code == '7' || code == '6') {
      return 'Didn\'t catch that. Tap to try again.';
    }
    if (code == 'unavailable') {
      return 'Speech recognition isn\'t available on this device.';
    }
    return 'Something went wrong. Tap to try again.';
  }

  void _onFinal(String text) {
    final parsed = NluParser.parseMulti(text);
    setState(() {
      _partial = text;
      _results = parsed;
      _phase = _Phase.review;
    });
  }

  Future<void> _saveAll() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || _results.isEmpty) return;
    final fs = ref.read(firestoreServiceProvider);
    for (final r in _results) {
      final t = Transaction(
        id: const Uuid().v4(),
        amount: r.amount!,
        direction: r.direction,
        timestamp: r.when,
        merchant: r.merchant,
        categoryId: r.categoryId,
        source: TxnSource.manual,
      );
      await fs.addTransaction(uid, t);
      if (r.merchant != null && r.merchant!.isNotEmpty) {
        await CategoryRules.instance.remember(r.merchant!, r.categoryId);
      }
    }
    if (mounted) {
      final n = _results.length;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$n transaction${n == 1 ? '' : 's'} added 🎉')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B1416) : const Color(0xFF06292B),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: _phase == _Phase.review ? _review() : _capture(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Listening / capture view ───────────────────────────────
  Widget _capture() {
    final level = ((_rms + 2) / 12).clamp(0.0, 1.0);
    final listening = _phase == _Phase.listening;
    const base = 150.0;
    final size = base + (listening ? level * 90 : 0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        // Animated orb that swells with your voice.
        SizedBox(
          height: base + 110,
          width: base + 110,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              height: size,
              width: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AerisColors.heroGradient,
                boxShadow: [
                  BoxShadow(
                    color: AerisColors.seed.withValues(alpha: 0.5 + level * 0.4),
                    blurRadius: 50 + level * 60,
                    spreadRadius: 4 + level * 10,
                  ),
                ],
              ),
              child: Icon(
                _phase == _Phase.processing ? Icons.hourglass_top : Icons.mic,
                color: Colors.white,
                size: 46,
              ),
            ),
          ),
        ),
        const SizedBox(height: 36),
        Text(
          switch (_phase) {
            _Phase.starting => 'Getting ready…',
            _Phase.listening => 'Listening… speak naturally',
            _Phase.processing => 'Got it — understanding…',
            _Phase.denied => _error.isEmpty ? 'Microphone needed' : _error,
            _Phase.unavailable =>
              'Speech recognition isn\'t available on this device.',
            _Phase.review => '',
          },
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        if (_partial.isNotEmpty)
          Text('"$_partial"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
        const Spacer(),
        if (_phase == _Phase.denied || _phase == _Phase.unavailable)
          Column(
            children: [
              if (_phase == _Phase.denied)
                FilledButton.icon(
                  onPressed: _begin,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('Open settings',
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          )
        else
          Text(
            'e.g. "spent 200 on chai and 500 on petrol, got 5000 salary"',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
          ),
      ],
    );
  }

  // ── Review parsed transactions ─────────────────────────────
  Widget _review() {
    if (_results.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.hearing_disabled, color: Colors.white54, size: 48),
          const SizedBox(height: 14),
          if (_partial.isNotEmpty)
            Text('"$_partial"',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          const Text("Couldn't find an amount in that.",
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: _begin,
              icon: const Icon(Icons.mic),
              label: const Text('Try again')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        const Text('Tap save if this looks right',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _resultCard(_results[i], i),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _begin,
                icon: const Icon(Icons.mic, color: Colors.white),
                label: const Text('Redo',
                    style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _saveAll,
                icon: const Icon(Icons.check),
                label: Text('Save ${_results.length}'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _resultCard(NluResult r, int i) {
    final cat = Categories.byId(r.categoryId);
    final income = r.direction == TxnDirection.credit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cat.color.withValues(alpha: 0.25),
            child: Icon(cat.icon, color: cat.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.merchant ?? cat.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                Text('${cat.label} · ${income ? 'Income' : 'Expense'}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${income ? '+' : '−'} ${formatRupees(r.amount ?? 0)}',
            style: TextStyle(
                color: income ? AerisColors.credit : Colors.white,
                fontWeight: FontWeight.w800),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
            onPressed: () => setState(() {
              final next = [..._results]..removeAt(i);
              _results = next;
              if (next.isEmpty) _phase = _Phase.review;
            }),
          ),
        ],
      ),
    );
  }
}
