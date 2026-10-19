import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_intake.dart';
import '../services/notification_service.dart';
import '../services/reminder_scheduler.dart';
import '../services/sms_service.dart';
import 'auth_provider.dart';
import 'money_providers.dart';
import 'transactions_provider.dart';

/// Where a new user is in setting AERIS up.
class SetupStatus {
  final bool sms, notifications, income, budget, reminders;
  const SetupStatus({
    required this.sms,
    required this.notifications,
    required this.income,
    required this.budget,
    required this.reminders,
  });

  int get done => [sms, notifications, income, budget, reminders]
      .where((x) => x)
      .length;
  static const total = 5;
  bool get complete => done == total;
}

/// Re-read by the Home checklist on resume (permissions change outside the
/// app) — `ref.invalidate(setupStatusProvider)`.
final setupStatusProvider = FutureProvider.autoDispose<SetupStatus>((ref) async {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  final budgets = ref.watch(effectiveBudgetsProvider);
  final prefs = await SharedPreferences.getInstance();
  // A failing permission check means "not done yet", never "hide the card".
  Future<bool> safe(Future<bool> Function() check) async {
    try {
      return await check();
    } catch (_) {
      return false;
    }
  }

  return SetupStatus(
    sms: await safe(SmsService.instance.hasPermission),
    notifications: await safe(NotificationIntake.instance.isEnabled),
    income: (profile?.monthlyIncome ?? 0) > 0,
    budget: budgets.isNotEmpty,
    reminders: prefs.getBool('reminders_on') ?? false,
  );
});

/// Ask for notification permission and switch smart reminders on. Returns
/// false if the user said no.
Future<bool> turnOnReminders(WidgetRef ref) async {
  if (!await NotificationService.instance.requestPermission()) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('reminders_on', true);
  await NotificationService.instance.scheduleDailyCheckin();
  await ReminderScheduler.refresh(
    txns: ref.read(transactionsStreamProvider).valueOrNull ?? const [],
    budgets: ref.read(effectiveBudgetsProvider),
    bills: ref.read(billsProvider),
  );
  return true;
}
