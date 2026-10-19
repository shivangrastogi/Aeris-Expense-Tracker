import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/loans_provider.dart';
import '../../providers/split_provider.dart';
import '../../utils/formatters.dart';
import '../loans/loans_screen.dart';
import 'shared_screen.dart';

/// People — every kind of money between you and friends in one place:
/// shared bills (rent, electricity, trips) and money lent or borrowed.
class PeopleScreen extends ConsumerWidget {
  /// 0 = Shared bills, 1 = Lent & borrowed.
  final int initialTab;
  const PeopleScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owedShared =
        ref.watch(owedToYouProvider).values.fold<double>(0, (s, v) => s + v);
    final loans = ref.watch(loanTotalsProvider);
    final owed = owedShared + loans.owedToYou;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('People'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(78),
            child: Column(children: [
              if (owed > 0 || loans.youOwe > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      [
                        if (owed > 0) 'Owed to you ${formatRupees(owed)}',
                        if (loans.youOwe > 0) 'You owe ${formatRupees(loans.youOwe)}',
                      ].join(' · '),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              else
                const SizedBox(height: 26),
              const TabBar(tabs: [
                Tab(text: 'Shared bills'),
                Tab(text: 'Lent & borrowed'),
              ]),
            ]),
          ),
        ),
        body: const TabBarView(children: [
          SharedScreen(embedded: true),
          LoansScreen(embedded: true),
        ]),
      ),
    );
  }
}
