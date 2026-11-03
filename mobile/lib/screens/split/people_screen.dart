import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/loans_provider.dart';
import '../../providers/privacy_provider.dart';
import '../../providers/split_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/ds.dart';
import '../loans/loans_screen.dart';
import 'shared_screen.dart';

/// People — every kind of money between you and friends in one place:
/// shared bills (rent, electricity, trips) and money lent or borrowed.
class PeopleScreen extends ConsumerStatefulWidget {
  /// 0 = Shared bills, 1 = Lent & borrowed.
  final int initialTab;
  const PeopleScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  late int _tab = widget.initialTab.clamp(0, 1);

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    ref.watch(amountHiddenProvider);
    final owedShared =
        ref.watch(owedToYouProvider).values.fold<double>(0, (s, v) => s + v);
    final loans = ref.watch(loanTotalsProvider);
    final owed = owedShared + loans.owedToYou;
    final sub = Ts.bodyS.copyWith(color: tk.t2);
    final bold = Ts.bodyS.copyWith(fontWeight: FontWeight.w700);

    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(style: sub, children: [
                const TextSpan(text: 'Owed to you '),
                TextSpan(
                    text: formatRupees(owed),
                    style: bold.copyWith(color: tk.ok)),
                const TextSpan(text: ' · You owe '),
                TextSpan(
                    text: formatRupees(loans.youOwe),
                    style: bold.copyWith(color: tk.t1)),
              ]),
            ),
            const SizedBox(height: 12),
            DsSegmented(
              labels: const ['Shared bills', 'Lent and borrowed'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ]),
        ),
        Expanded(
          child: IndexedStack(index: _tab, children: const [
            SharedScreen(embedded: true),
            LoansScreen(embedded: true),
          ]),
        ),
      ]),
    );
  }
}
