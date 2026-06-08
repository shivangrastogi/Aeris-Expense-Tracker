import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatar_skin.dart';
import '../models/challenge.dart';
import '../widgets/aeris_avatar.dart' show AvatarMood;
import 'analytics_provider.dart';
import 'budgets_provider.dart';
import 'goals_provider.dart';
import 'insights_provider.dart';
import 'transactions_provider.dart';

/// Immutable gamification state. Aura is earned deterministically (each
/// rewardable event is awarded exactly once via [awardedKeys]) and spent on
/// unlocks, so the balance can never be double-counted or drift.
class GamificationState {
  final int earned;
  final int spent;
  final Set<String> unlocked;
  final String selected;
  final List<Challenge> challenges;
  final Set<String> awardedKeys;
  final Set<String> hiddenCards; // dashboard cards the user hid
  final int? accent; // dashboard accent colour value
  final int checkinStreak; // consecutive daily check-ins
  final String? lastCheckinDay; // day-key of the most recent check-in
  final bool loaded;

  const GamificationState({
    this.earned = 0,
    this.spent = 0,
    this.unlocked = const {'spark'},
    this.selected = 'spark',
    this.challenges = const [],
    this.awardedKeys = const {},
    this.hiddenCards = const {},
    this.accent,
    this.checkinStreak = 0,
    this.lastCheckinDay,
    this.loaded = false,
  });

  int get available => earned - spent;
  int get level => levelForAura(earned);

  GamificationState copyWith({
    int? earned,
    int? spent,
    Set<String>? unlocked,
    String? selected,
    List<Challenge>? challenges,
    Set<String>? awardedKeys,
    Set<String>? hiddenCards,
    Object? accent = _noChange,
    int? checkinStreak,
    String? lastCheckinDay,
    bool? loaded,
  }) =>
      GamificationState(
        earned: earned ?? this.earned,
        spent: spent ?? this.spent,
        unlocked: unlocked ?? this.unlocked,
        selected: selected ?? this.selected,
        challenges: challenges ?? this.challenges,
        awardedKeys: awardedKeys ?? this.awardedKeys,
        hiddenCards: hiddenCards ?? this.hiddenCards,
        accent: accent == _noChange ? this.accent : accent as int?,
        checkinStreak: checkinStreak ?? this.checkinStreak,
        lastCheckinDay: lastCheckinDay ?? this.lastCheckinDay,
        loaded: loaded ?? this.loaded,
      );
}

const _noChange = Object();

final gamificationProvider =
    StateNotifierProvider<GamificationController, GamificationState>(
        (ref) => GamificationController(ref));

typedef AvatarStatus = ({AvatarSkin skin, int level, int stage, AvatarMood mood});

/// The avatar's live look: selected skin + evolution stage from level, and a
/// mood that reflects current financial health (over budget = sad, saving = excited).
final avatarStatusProvider = Provider<AvatarStatus>((ref) {
  final g = ref.watch(gamificationProvider);
  final skin = Avatars.byId(g.selected);
  final level = g.level;
  final analytics = ref.watch(analyticsProvider).valueOrNull;
  final insights = ref.watch(insightsProvider).valueOrNull;
  AvatarMood mood;
  if (insights != null && insights.budgetProjections.any((p) => p.alreadyOver)) {
    mood = AvatarMood.sad;
  } else if (analytics != null && analytics.monthNet > 0) {
    mood = AvatarMood.excited;
  } else if (analytics != null && analytics.monthExpense > 0) {
    mood = AvatarMood.happy;
  } else {
    mood = AvatarMood.neutral;
  }
  return (skin: skin, level: level, stage: evolutionStage(level), mood: mood);
});

class GamificationController extends StateNotifier<GamificationState> {
  final Ref _ref;
  GamificationController(this._ref) : super(const GamificationState()) {
    _load();
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final accent = p.getInt('gam_accent');
    state = state.copyWith(
      earned: p.getInt('gam_earned') ?? 0,
      spent: p.getInt('gam_spent') ?? 0,
      unlocked: (p.getStringList('gam_unlocked') ?? const ['spark']).toSet()
        ..add('spark'),
      selected: p.getString('gam_selected') ?? 'spark',
      awardedKeys: (p.getStringList('gam_awarded') ?? const []).toSet(),
      hiddenCards: (p.getStringList('dash_hidden') ?? const []).toSet(),
      accent: accent,
      checkinStreak: p.getInt('gam_checkin_streak') ?? 0,
      lastCheckinDay: p.getString('gam_checkin_day'),
      challenges: (p.getStringList('gam_challenges') ?? const [])
          .map((s) => Challenge.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList(),
      loaded: true,
    );
    sync();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('gam_earned', state.earned);
    await p.setInt('gam_spent', state.spent);
    await p.setStringList('gam_unlocked', state.unlocked.toList());
    await p.setString('gam_selected', state.selected);
    await p.setStringList('gam_awarded', state.awardedKeys.toList());
    await p.setStringList('dash_hidden', state.hiddenCards.toList());
    await p.setInt('gam_checkin_streak', state.checkinStreak);
    if (state.lastCheckinDay == null) {
      await p.remove('gam_checkin_day');
    } else {
      await p.setString('gam_checkin_day', state.lastCheckinDay!);
    }
    await p.setStringList(
        'gam_challenges', state.challenges.map((c) => jsonEncode(c.toJson())).toList());
    if (state.accent == null) {
      await p.remove('gam_accent');
    } else {
      await p.setInt('gam_accent', state.accent!);
    }
  }

  /// Award Aura for any newly-completed events. Idempotent — each event key is
  /// granted only once. Safe to call on every data change.
  void sync() {
    if (!state.loaded) return;
    final txns = _ref.read(transactionsStreamProvider).valueOrNull ?? const [];
    final budgets = _ref.read(budgetsStreamProvider).valueOrNull ?? const [];
    final goals = _ref.read(goalsStreamProvider).valueOrNull ?? const [];
    final now = DateTime.now();

    final awarded = {...state.awardedKeys};
    var earned = state.earned;
    void grant(String key, int amt) {
      if (awarded.add(key)) earned += amt;
    }

    grant('welcome', 50);

    for (final g in goals) {
      if (g.isComplete) grant('goal_${g.id}', 200);
    }

    // Completed months that stayed within the total budget cap — the explicit
    // overall "total monthly budget" wins, else the sum of per-category caps.
    final explicitTotal = budgets
        .where((b) => b.categoryId == '__total__')
        .fold<double>(0, (s, b) => s + b.monthlyCap);
    final cap = explicitTotal > 0
        ? explicitTotal
        : budgets
            .where((b) => b.categoryId != '__total__')
            .fold<double>(0, (s, b) => s + b.monthlyCap);
    if (cap > 0) {
      final monthExp = <String, double>{};
      for (final t in txns) {
        if (t.isDebit) {
          monthExp[_monthKey(t.timestamp)] =
              (monthExp[_monthKey(t.timestamp)] ?? 0) + t.amount;
        }
      }
      final curK = _monthKey(now);
      monthExp.forEach((k, exp) {
        if (k != curK && exp <= cap) grant('mub_$k', 100);
      });
    }

    // No-spend days over the last 120 completed days (after first activity).
    if (txns.isNotEmpty) {
      final debitDays = <String>{};
      var first = now;
      for (final t in txns) {
        if (t.timestamp.isBefore(first)) first = t.timestamp;
        if (t.isDebit) debitDays.add(_dayKey(t.timestamp));
      }
      final today = DateTime(now.year, now.month, now.day);
      final firstDay = DateTime(first.year, first.month, first.day);
      var scan = today.subtract(const Duration(days: 120));
      if (scan.isBefore(firstDay)) scan = firstDay;
      for (var d = scan;
          d.isBefore(today);
          d = d.add(const Duration(days: 1))) {
        if (!debitDays.contains(_dayKey(d))) grant('ns_${_dayKey(d)}', 10);
      }
    }

    // Won challenges.
    for (final c in state.challenges) {
      if (c.evaluate(txns, now).state == ChallengeState.won) {
        grant('ch_${c.id}', c.reward);
      }
    }

    if (earned != state.earned) {
      state = state.copyWith(earned: earned, awardedKeys: awarded);
      _persist();
    }
  }

  // ── Daily check-in ─────────────────────────────────────────
  /// True if the user has already claimed today's check-in reward.
  bool get checkedInToday =>
      state.awardedKeys.contains('checkin_${_dayKey(DateTime.now())}');

  /// Base aura granted for a daily check-in (before the streak bonus).
  static const checkinBase = 15;

  /// Claim today's check-in: grants a base reward once per calendar day plus a
  /// growing (but capped) streak bonus for consecutive days. Returns the total
  /// aura awarded, or 0 if already claimed today.
  int checkIn() {
    if (!state.loaded) return 0;
    final now = DateTime.now();
    final today = _dayKey(now);
    if (state.awardedKeys.contains('checkin_$today')) return 0;
    final yesterday = _dayKey(now.subtract(const Duration(days: 1)));
    final streak = state.lastCheckinDay == yesterday ? state.checkinStreak + 1 : 1;
    final bonus = ((streak - 1) * 5).clamp(0, 60); // grows with the streak, capped
    final total = checkinBase + bonus;
    state = state.copyWith(
      earned: state.earned + total,
      awardedKeys: {...state.awardedKeys, 'checkin_$today'},
      checkinStreak: streak,
      lastCheckinDay: today,
    );
    _persist();
    return total;
  }

  // ── Categorisation reward ──────────────────────────────────
  /// Aura granted the first time the user categorises/confirms a transaction.
  static const categorizeReward = 5;

  /// Reward the user once for categorising a given transaction. Idempotent —
  /// re-categorising the same transaction won't grant again. Returns the aura
  /// awarded (0 if it was already rewarded).
  int rewardCategorization(String txnId) {
    if (!state.loaded) return 0;
    final key = 'cat_$txnId';
    if (state.awardedKeys.contains(key)) return 0;
    state = state.copyWith(
      earned: state.earned + categorizeReward,
      awardedKeys: {...state.awardedKeys, key},
    );
    _persist();
    return categorizeReward;
  }

  // ── Store / avatar ─────────────────────────────────────────
  bool unlock(AvatarSkin skin) {
    if (state.unlocked.contains(skin.id)) return true;
    if (state.available < skin.cost) return false;
    state = state.copyWith(
      spent: state.spent + skin.cost,
      unlocked: {...state.unlocked, skin.id},
      selected: skin.id,
    );
    _persist();
    return true;
  }

  void select(String id) {
    if (!state.unlocked.contains(id)) return;
    state = state.copyWith(selected: id);
    _persist();
  }

  // ── Challenges ─────────────────────────────────────────────
  void addChallenge(Challenge c) {
    state = state.copyWith(challenges: [...state.challenges, c]);
    _persist();
    sync();
  }

  void removeChallenge(String id) {
    state = state.copyWith(
        challenges: state.challenges.where((c) => c.id != id).toList());
    _persist();
  }

  // ── Dashboard ──────────────────────────────────────────────
  void setCardHidden(String cardId, bool hidden) {
    final set = {...state.hiddenCards};
    hidden ? set.add(cardId) : set.remove(cardId);
    state = state.copyWith(hiddenCards: set);
    _persist();
  }

  void setAccent(int? value) {
    state = state.copyWith(accent: value);
    _persist();
  }
}
