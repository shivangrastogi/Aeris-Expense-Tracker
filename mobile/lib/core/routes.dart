import 'package:flutter/material.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/home/root_shell.dart';
import '../screens/transactions/add_transaction_screen.dart';
import '../screens/transactions/transaction_detail_screen.dart';
import '../screens/transactions/transactions_screen.dart';
import '../screens/transactions/statement_import_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/accounts/accounts_screen.dart';
import '../screens/gamification/aeris_world_screen.dart';
import '../screens/sms_inbox/sms_review_screen.dart';
import '../screens/budgets/budget_edit_screen.dart';
import '../screens/goals/goals_screen.dart';
import '../screens/assistant/assistant_screen.dart';
import '../screens/subscriptions/subscriptions_screen.dart';
import '../models/transaction.dart';

class AppRoutes {
  AppRoutes._();
  static const login = '/login';
  static const signup = '/signup';
  static const otp = '/otp';
  static const home = '/home';
  static const addTxn = '/transactions/add';
  static const txnDetail = '/transactions/detail';
  static const transactions = '/transactions';
  static const importStatement = '/transactions/import';
  static const accounts = '/accounts';
  static const aerisWorld = '/aeris-world';
  static const editProfile = '/profile/edit';
  static const settings = '/settings';
  static const smsReview = '/sms/review';
  static const budgetEdit = '/budgets/edit';
  static const goals = '/goals';
  static const assistant = '/assistant';
  static const subscriptions = '/subscriptions';

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
        page = AddTransactionScreen(
            initialDirection: s.arguments as TxnDirection?);
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
      case editProfile:
        page = const EditProfileScreen();
        break;
      case settings:
        page = const SettingsScreen();
        break;
      case smsReview:
        page = const SmsReviewScreen();
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
      default:
        return null;
    }
    return MaterialPageRoute(builder: (_) => page, settings: s);
  }
}
