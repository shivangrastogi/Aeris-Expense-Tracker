import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/assistant_service.dart';
import '../../widgets/mascot/aeris_mascot.dart';

class _Msg {
  final String text;
  final bool fromUser;
  final bool typing;
  const _Msg(this.text, this.fromUser, {this.typing = false});
}

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});
  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[
    const _Msg(
        "Hi! I'm Aeris. Ask me about your spending — it's all answered on "
        "your device, privately.",
        false),
  ];
  bool _thinking = false;

  static const _suggestions = [
    'How much did I spend this month?',
    "What's my biggest category?",
    'Am I over budget?',
    'How much did I earn this month?',
    'What was my largest expense?',
  ];

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    // Gate: ignore empties and block while Aeris is "typing" (anti-spam).
    if (q.isEmpty || _thinking) return;

    final txns = ref.read(transactionsStreamProvider).valueOrNull ?? const [];
    final budgets = ref.read(budgetsStreamProvider).valueOrNull ?? const [];
    final income = ref.read(userProfileProvider).asData?.value?.monthlyIncome;

    setState(() {
      _msgs.add(_Msg(q, true));
      _msgs.add(const _Msg('', false, typing: true)); // typing indicator
      _thinking = true;
    });
    _input.clear();
    _scrollDown();

    // Small, realistic "thinking" delay — also prevents one-by-one spamming.
    await Future.delayed(const Duration(milliseconds: 700));
    final reply = AssistantService.answer(q,
        txns: txns, budgets: budgets, monthlyIncome: income);
    if (!mounted) return;
    setState(() {
      _msgs.removeLast(); // remove typing bubble
      _msgs.add(_Msg(reply, false));
      _thinking = false;
    });
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ask Aeris')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(14),
              itemCount: _msgs.length,
              itemBuilder: (_, i) => _bubble(_msgs[i], scheme),
            ),
          ),
          // Suggestion chips (disabled while thinking)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in _suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                    child: ActionChip(
                      label: Text(s),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: _thinking ? null : () => _send(s),
                    ),
                  ),
              ],
            ),
          ),
          // Input (Scaffold already resizes above the keyboard, so no manual
          // viewInsets padding — that was pushing the field to the top).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _thinking ? null : _send,
                    maxLength: 160,
                    minLines: 1,
                    maxLines: 3,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null, // hide the character counter
                    decoration: const InputDecoration(
                      hintText: 'Ask about your money…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _thinking ? null : () => _send(_input.text),
                  icon: _thinking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m, ColorScheme scheme) {
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(m.text, style: TextStyle(color: scheme.onPrimary)),
        ),
      ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.1, end: 0);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AerisMascot(mood: MascotMood.neutral, size: 40),
        const SizedBox(width: 6),
        Flexible(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceVariant.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: m.typing
                ? const _TypingDots()
                : Text(m.text, style: const TextStyle(height: 1.35)),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 220.ms).slideX(begin: -0.1, end: 0);
  }
}

class _TypingDots extends StatelessWidget {
  const _TypingDots();
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget dot(int i) => Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        )
            .animate(onPlay: (ctrl) => ctrl.repeat())
            .fadeIn(duration: 400.ms, delay: (i * 150).ms)
            .then()
            .fadeOut(duration: 400.ms);
    return Row(mainAxisSize: MainAxisSize.min, children: [dot(0), dot(1), dot(2)]);
  }
}
