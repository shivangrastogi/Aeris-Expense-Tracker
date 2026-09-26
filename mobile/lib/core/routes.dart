import 'package:flutter/material.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/home/root_shell.dart';
import '../screens/transactions/add_transaction_screen.dart';
import '../screens/transactions/quick_add_screen.dart';
import '../screens/transactions/transaction_detail_screen.dart';
import '../screens/transactions/voice_capture_screen.dart';
import '../screens/transactions/transactions_screen.dart';
import '../screens/transactions/statement_import_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/profile/widgets_screen.dart';
import '../screens/profile/widget_configure_screen.dart';
import '../screens/accounts/accounts_screen.dart';
import '../screens/gamification/aeris_world_screen.dart';
import '../screens/gamification/village_screen.dart';
import '../screens/sms_inbox/sms_review_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/budgets/budget_edit_screen.dart';
import '../screens/budgets/budgets_screen.dart';
import '../screens/goals/goals_screen.dart';
import '../screens/assistant/assistant_screen.dart';
import '../screens/subscriptions/subscriptions_screen.dart';
import '../screens/loans/loans_screen.dart';
import '../screens/insights/wrapped_screen.dart';
import '../screens/insights/insights_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../models/transaction.dart';

class AppRoutes {
  AppRoutes._();
  static const login = '/login';
  static const signup = '/signup';
  static const otp = '/otp';
  static const home = '/home';
  static const addTxn = '/transactions/add';
  static const quickAdd = '/transactions/quick-add';
  static const voice = '/voice';
  static const wrapped = '/wrapped';
  static const txnDetail = '/transactions/detail';
  static const transactions = '/transactions';
  static const importStatement = '/transactions/import';
  static const accounts = '/accounts';
  static const aerisWorld = '/aeris-world';
  static const village = '/village';
  static const editProfile = '/profile/edit';
  static const settings = '/settings';
  static const widgets = '/widgets';
  static const widgetConfigure = '/widget-configure';
  static const smsReview = '/sms/review';
  static const notifications = '/notifications';
  static const budgetEdit = '/budgets/edit';
  static const budgets = '/budgets';
  static const goals = '/goals';
  static const assistant = '/assistant';
  static const subscriptions = '/subscriptions';
  static const loans = '/loans';
  static const insights = '/insights';
  static const analytics = '/analytics';

  static Route<dynamic>? onGenerateRoute(RouteSettings s) {
    Widget page;
    switch (s.name) {
      case login:
        page = const LoginScreen();
        break;
      case signup:
        page = const SignupScreen();
        break;
      case otp:
        page = OtpScreen(verificationId: s.arguments as String? ?? '');
        break;
      case home:
        page = const RootShell();
        break;
      case addTxn:
        // A TxnDirection opens a new entry; a Transaction opens it for editing.
        final arg = s.arguments;
        page = AddTransactionScreen(
          initialDirection: arg is TxnDirection ? arg : null,
          existing: arg is Transaction ? arg : null,
        );
        break;
      case quickAdd:
        page = const QuickAddScreen();
        break;
      case voice:
        page = const VoiceCaptureScreen();
        break;
      case wrapped:
        page = const WrappedScreen();
        break;
      case transactions:
        final a = s.arguments;
        page = TransactionsScreen(
          initialDir: a is TxnDirection ? a : null,
          initialCategory: a is String ? a : null,
        );
        break;
      case txnDetail:
        page = TransactionDetailScreen(txn: s.arguments as Transaction);
        break;
      case importStatement:
        page = const StatementImportScreen();
        break;
      case accounts:
        page = const AccountsScreen();
        break;
      case aerisWorld:
        page = const AerisWorldScreen();
        break;
      case village:
        page = const VillageScreen();
        break;
      case editProfile:
        page = const EditProfileScreen();
        break;
      case settings:
        page = const SettingsScreen();
        break;
      case widgets:
        page = const WidgetsScreen();
        break;
      case widgetConfigure:
        page = const WidgetConfigureScreen();
        break;
      case smsReview:
        page = const SmsReviewScreen();
        break;
      case notifications:
        page = const NotificationsScreen();
        break;
      case budgetEdit:
        page = BudgetEditScreen(categoryId: s.arguments as String?);
        break;
      case goals:
        page = const GoalsScreen();
        break;
      case assistant:
        page = const AssistantScreen();
        break;
      case subscriptions:
        page = const SubscriptionsScreen();
        break;
      case loans:
        page = const LoansScreen();
        break;
      case budgets:
        page = const BudgetsScreen();
        break;
      case insights:
        page = const InsightsScreen();
        break;
      case analytics:
        page = const AnalyticsScreen();
        break;
      default:
        return null;
    }
    return MaterialPageRoute(builder: (_) => page, settings: s);
  }
}
