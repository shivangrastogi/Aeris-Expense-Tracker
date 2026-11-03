import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../services/assistant_service.dart';
import '../../utils/motion.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/ds.dart';

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
    final tk = context.tk;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          const AerisBrandMark(size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ask Aeris', style: Ts.title.copyWith(color: tk.t1)),
                Row(children: [
                  Icon(PhFill.lockSimple, size: 11, color: tk.t2),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('Answered on your phone, privately',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: tk.t2)),
                  ),
                ]),
              ],
            ),
          ),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tk.hair),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _msgs.length,
              itemBuilder: (_, i) => _bubble(_msgs[i]),
            ),
          ),
          // Suggestion chips (disabled while thinking)
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Material(
                color: tk.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Rad.chip),
                    side: BorderSide(color: tk.hair2)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Rad.chip),
                  onTap: _thinking ? null : () => _send(_suggestions[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(_suggestions[i],
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _thinking ? tk.t3 : tk.t1)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Input (Scaffold already resizes above the keyboard, so no manual
          // viewInsets padding — that was pushing the field to the top).
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
                decoration: BoxDecoration(
                  color: tk.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: tk.hair),
                  boxShadow: tk.shadow,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _thinking ? null : _send,
                        onChanged: (_) => setState(() {}),
                        maxLength: 160,
                        minLines: 1,
                        maxLines: 3,
                        buildCounter: (_,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null, // hide the character counter
                        decoration: const InputDecoration(
                          hintText: 'Ask about your money',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _SendButton(
                      busy: _thinking,
                      enabled: !_thinking && _input.text.trim().isNotEmpty,
                      onTap: () => _send(_input.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final tk = context.tk;
    final maxW = MediaQuery.sizeOf(context).width * 0.8;
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: maxW),
          decoration: BoxDecoration(
            color: tk.acc,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(m.text,
              style: TextStyle(
                  fontSize: 15, height: 21 / 15, color: tk.onAcc)),
        ),
      ).animate().fadeIn(duration: Mo.standard).slideY(begin: 0.15, end: 0);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: BoxConstraints(maxWidth: maxW),
        decoration: BoxDecoration(
          color: tk.surface,
          border: tk.edge,
          boxShadow: tk.shadow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: m.typing
            ? const _TypingDots()
            : Text(m.text,
                style: TextStyle(fontSize: 15, height: 22 / 15, color: tk.t1)),
      ),
    ).animate().fadeIn(duration: Mo.standard).slideY(begin: 0.15, end: 0);
  }
}

/// 44 dp round send button: accent when there's something to send, the
/// rising-line loader while Aeris is answering.
class _SendButton extends StatelessWidget {
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;
  const _SendButton(
      {required this.busy, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Semantics(
      button: true,
      label: 'Send',
      child: Material(
        color: enabled ? tk.acc : tk.press,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: busy
                  ? const RisingLoader(width: 20)
                  : Icon(PhBold.arrowUp,
                      size: 20, color: enabled ? tk.onAcc : tk.t3),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingDots extends StatelessWidget {
  const _TypingDots();
  @override
  Widget build(BuildContext context) {
    final c = context.tk.t2;
    if (reduceMotion(context)) {
      return Text('Thinking…', style: TextStyle(fontSize: 14, color: c));
    }
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
