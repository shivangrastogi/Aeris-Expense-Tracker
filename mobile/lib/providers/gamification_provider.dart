import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatar_skin.dart';
import '../models/budget.dart';
import '../models/challenge.dart';
import '../services/firestore_service.dart';
import '../widgets/aeris_avatar.dart' show AvatarMood;
import 'analytics_provider.dart';
import 'auth_provider.dart';
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
  /// Aura earned *inside* Aeris Town (building yields). Spendable, but it
  /// never raises your level — levels only come from real money habits.
  final int bonus;
  /// Gems: the rare currency (rushing construction). Earned only from
  /// milestones — streaks, months under budget, goals, challenges.
  final int gems;
  /// Day-key the user started (first run of this version). Events from
  /// before it (backfilled SMS history) don't award anything retroactively.
  final String? startedDay;
  final bool loaded;

  const GamificationState({
    this.earned = 0,
    this.spent = 0,
    this.unlocked = const {'sprout'},
    this.selected = 'sprout',
    this.challenges = const [],
    this.awardedKeys = const {},
    this.hiddenCards = const {},
    this.accent,
    this.checkinStreak = 0,
    this.lastCheckinDay,
    this.bonus = 0,
    this.gems = 10,
    this.startedDay,
    this.loaded = false,
  });

  int get available => earned + bonus - spent;
  int get level => levelForAura(earned);

  /// Canonical day-key (`YYYY-MM-DD`) used for all check-in bookkeeping.
  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Whether the user checked in on a specific calendar day. Reconstructed from
  /// [awardedKeys] (`checkin_<dayKey>`), which is the source of truth per day.
  bool checkedInOn(DateTime d) => awardedKeys.contains('checkin_${dayKey(d)}');

  /// The streak as it stands *right now*. The raw [checkinStreak] is only
  /// rewritten when [GamificationController.checkIn] runs, so on a brand-new
  /// day (or after a missed day) it would otherwise read stale. A streak is
  /// only "alive" if the last check-in was today or yesterday; once a whole day
  /// is missed it has lapsed and reads 0 until the next check-in.
  int get liveStreak {
    if (checkinStreak <= 0 || lastCheckinDay == null) return 0;
    final now = DateTime.now();
    final today = dayKey(now);
    final yesterday = dayKey(now.subtract(const Duration(days: 1)));
    if (lastCheckinDay == today || lastCheckinDay == yesterday) {
      return checkinStreak;
    }
    return 0; // a full day was missed — streak lapsed
  }

  /// The last seven calendar days, oldest first — today is always the last
  /// one. A rolling window, not a Sunday→Saturday week: when a new week
  /// starts the earlier check-ins stay in view instead of every dot wiping
  /// back to empty as if the streak had restarted.
  static List<DateTime> recentDays([DateTime? ref]) {
    final now = ref ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Calendar arithmetic (not 24 h steps), so DST shifts can't skip a day.
    return [
      for (var i = 6; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i),
    ];
  }

  /// Whether each of [recentDays] was checked in. Today stays empty until
  /// the user checks in.
  List<bool> recentCheckins([DateTime? ref]) =>
      [for (final d in recentDays(ref)) checkedInOn(d)];

  /// "M", "T"… for a day in [recentDays].
  static String dayLetter(DateTime d) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1];

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
    int? bonus,
    int? gems,
    String? startedDay,
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
        bonus: bonus ?? this.bonus,
        gems: gems ?? this.gems,
        startedDay: startedDay ?? this.startedDay,
        loaded: loaded ?? this.loaded,
      );
}

const _noChange = Object();

final gamificationProvider =
    StateNotifierProvider<GamificationController, GamificationState>(
        (ref) => GamificationController(ref));

typedef AvatarStatus = ({
  AvatarSkin skin,
  int level,
  int stage,
  AvatarMood mood
});

/// The avatar's live look: selected skin + evolution stage from level, and a
/// mood that reflects current financial health (over budget = sad, saving = excited).
final avatarStatusProvider = Provider<AvatarStatus>((ref) {
  final g = ref.watch(gamificationProvider);
  final skin = Avatars.byId(g.selected);
  final level = g.level;
  final analytics = ref.watch(monthAnalyticsProvider);
  final insights = ref.watch(insightsProvider).valueOrNull;
  AvatarMood mood;
  if (insights != null &&
      insights.budgetProjections.any((p) => p.alreadyOver)) {
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
  String? _pendingCloudUid;

  GamificationController(this._ref) : super(const GamificationState()) {
    _load();
    // Whenever a user signs in, restore/merge their cloud copy so streak +
    // aura survive reinstalls and travel across devices.
    _ref.listen<String?>(currentUserIdProvider, (_, uid) => _onUid(uid));
  }

  void _onUid(String? uid) {
    if (uid == null) return;
    if (!state.loaded) {
      // Prefs are still loading — restore once _load() finishes.
      _pendingCloudUid = uid;
      return;
    }
    _restoreFromCloud(uid);
  }

  static String _dayKey(DateTime d) => GamificationState.dayKey(d);
  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final accent = p.getInt('gam_accent');
    state = state.copyWith(
      earned: p.getInt('gam_earned') ?? 0,
      spent: p.getInt('gam_spent') ?? 0,
      unlocked: (p.getStringList('gam_unlocked') ?? const ['sprout']).toSet()
        ..add('sprout'),
      selected: p.getString('gam_selected') ?? 'sprout',
      awardedKeys: (p.getStringList('gam_awarded') ?? const []).toSet(),
      hiddenCards: (p.getStringList('dash_hidden') ?? const []).toSet(),
      accent: accent,
      checkinStreak: p.getInt('gam_checkin_streak') ?? 0,
      lastCheckinDay: p.getString('gam_checkin_day'),
      challenges: (p.getStringList('gam_challenges') ?? const [])
          .map((s) => Challenge.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList(),
      bonus: p.getInt('gam_bonus') ?? 0,
      gems: p.getInt('gam_gems') ?? 10,
      startedDay: p.getString('gam_started') ?? _dayKey(DateTime.now()),
      loaded: true,
    );
    sync();
    // Merge in the cloud copy if the user is already signed in (cold start)
    // or signed in while prefs were still loading.
    final uid = _pendingCloudUid ?? _ref.read(currentUserIdProvider);
    _pendingCloudUid = null;
    if (uid != null) await _restoreFromCloud(uid);
  }

  /// Merge the Firestore backup into local state. Union the award/unlock sets,
  /// keep the larger aura figures, and take whichever check-in record is most
  /// recent (tie → larger streak). Then write the merged result back to both
  /// stores. Safe to run repeatedly.
  Future<void> _restoreFromCloud(String uid) async {
    final p = await SharedPreferences.getInstance();
    // Prefs are per-device, not per-account: if a different account's data is
    // sitting in them, reset before merging so it can't leak across users.
    final owner = p.getString('gam_owner_uid');
    if (owner != null && owner != uid) {
      state = const GamificationState(loaded: true);
    }
    await p.setString('gam_owner_uid', uid);

    Map<String, dynamic>? cloud;
    try {
      cloud = await FirestoreService.instance.fetchGamification(uid);
    } catch (_) {
      cloud = null; // offline — local state stands, next persist will mirror
    }
    if (cloud != null) {
      // Tolerant parsing: numbers typed by hand in the Firebase console are
      // easy to create as strings ("10") — accept both.
      int asInt(Object? v) =>
          v is num ? v.toInt() : (int.tryParse('$v'.trim()) ?? 0);
      final cloudEarned = asInt(cloud['earned']);
      final cloudSpent = asInt(cloud['spent']);
      final cloudUnlocked =
          ((cloud['unlocked'] as List?) ?? const []).cast<String>().toSet();
      final cloudAwarded =
          ((cloud['awardedKeys'] as List?) ?? const []).cast<String>().toSet();
      final cloudStreak = asInt(cloud['checkinStreak']);
      final cloudDay = cloud['lastCheckinDay'] as String?;
      final cloudBonus = asInt(cloud['bonus']);
      final cloudGems = cloud.containsKey('gems') ? asInt(cloud['gems']) : null;
      final cloudStarted = cloud['startedDay'] as String?;

      var streak = state.checkinStreak;
      var day = state.lastCheckinDay;
      if (cloudDay != null &&
          (day == null ||
              cloudDay.compareTo(day) > 0 ||
              (cloudDay == day && cloudStreak > streak))) {
        streak = cloudStreak;
        day = cloudDay;
      }

      state = state.copyWith(
        earned: cloudEarned > state.earned ? cloudEarned : state.earned,
        spent: cloudSpent > state.spent ? cloudSpent : state.spent,
        unlocked: {...state.unlocked, ...cloudUnlocked},
        selected: state.selected != 'sprout'
            ? state.selected
            : (cloud['selected'] as String? ?? 'sprout'),
        awardedKeys: {...state.awardedKeys, ...cloudAwarded},
        checkinStreak: streak,
        lastCheckinDay: day,
        bonus: cloudBonus > state.bonus ? cloudBonus : state.bonus,
        // Gems go down when spent, so the cloud value only wins on a fresh
        // install (local still at the starting 10).
        gems: cloudGems != null && state.gems == 10 ? cloudGems : state.gems,
        startedDay: cloudStarted != null &&
                (state.startedDay == null ||
                    cloudStarted.compareTo(state.startedDay!) < 0)
            ? cloudStarted
            : state.startedDay,
      );
    }
    await _persist();
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
    await p.setStringList('gam_challenges',
        state.challenges.map((c) => jsonEncode(c.toJson())).toList());
    if (state.accent == null) {
      await p.remove('gam_accent');
    } else {
      await p.setInt('gam_accent', state.accent!);
    }
    await p.setInt('gam_bonus', state.bonus);
    await p.setInt('gam_gems', state.gems);
    if (state.startedDay != null) {
      await p.setString('gam_started', state.startedDay!);
    }
    // Mirror to Firestore (fire-and-forget) so streak/aura survive reinstalls.
    // hiddenCards/accent/challenges stay device-local on purpose.
    final uid = _ref.read(currentUserIdProvider);
    if (uid != null) {
      FirestoreService.instance.saveGamification(uid, {
        'earned': state.earned,
        'spent': state.spent,
        'unlocked': state.unlocked.toList(),
        'selected': state.selected,
        'awardedKeys': state.awardedKeys.toList(),
        'checkinStreak': state.checkinStreak,
        'lastCheckinDay': state.lastCheckinDay,
        'bonus': state.bonus,
        'gems': state.gems,
        if (state.startedDay != null) 'startedDay': state.startedDay,
      }).catchError((_) {/* offline — next persist retries */});
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
    var gems = state.gems;
    void grant(String key, int amt) {
      if (awarded.add(key)) earned += amt;
    }

    void gem(String key, int amt) {
      if (awarded.add('gem_$key')) gems += amt;
    }

    // Only events on/after the day the user started count — otherwise a
    // fresh SMS backfill would pay out months of "no-spend days" and
    // "months under budget" the user never actually played.
    final started = state.startedDay ?? _dayKey(now);
    final startMonth = started.substring(0, 7);

    grant('welcome', 50);

    for (final g in goals) {
      if (g.isComplete) {
        grant('goal_${g.id}', 200);
        gem('goal_${g.id}', 10);
      }
    }

    // Streak milestones pay gems once each.
    for (final (days, n) in const [(7, 5), (30, 15), (100, 40), (365, 120)]) {
      if (state.liveStreak >= days) gem('streak_$days', n);
    }

    // Completed months that stayed within the total budget cap — the explicit
    // overall "total monthly budget" wins, else the sum of per-category caps.
    final explicitTotal = budgets
        .where((b) => b.categoryId == Budget.totalId)
        .fold<double>(0, (s, b) => s + b.monthlyCap);
    final cap = explicitTotal > 0
        ? explicitTotal
        : budgets
            .where((b) => b.categoryId != Budget.totalId)
            .fold<double>(0, (s, b) => s + b.monthlyCap);
    if (cap > 0) {
      final monthExp = <String, double>{};
      for (final t in txns) {
        if (t.isSpend) {
          monthExp[_monthKey(t.timestamp)] =
              (monthExp[_monthKey(t.timestamp)] ?? 0) + t.spendAmount;
        }
      }
      final curK = _monthKey(now);
      monthExp.forEach((k, exp) {
        // A full month after the start month, finished, within the cap.
        if (k != curK && k.compareTo(startMonth) > 0 && exp <= cap) {
          grant('mub_$k', 100);
          gem('mub_$k', 10);
        }
      });
    }

    // No-spend days over the last 120 completed days (after first activity).
    if (txns.isNotEmpty) {
      final debitDays = <String>{};
      var first = now;
      for (final t in txns) {
        if (t.timestamp.isBefore(first)) first = t.timestamp;
        if (t.isSpend) debitDays.add(_dayKey(t.timestamp));
      }
      final today = DateTime(now.year, now.month, now.day);
      final firstDay = DateTime(first.year, first.month, first.day);
      var scan = today.subtract(const Duration(days: 120));
      if (scan.isBefore(firstDay)) scan = firstDay;
      final startDate = DateTime.tryParse(started);
      if (startDate != null && scan.isBefore(startDate)) scan = startDate;
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
        gem('ch_${c.id}', 3);
      }
    }

    if (earned != state.earned || gems != state.gems || state.startedDay == null) {
      state = state.copyWith(
          earned: earned, gems: gems, awardedKeys: awarded, startedDay: started);
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
    final int streak;
    if (state.lastCheckinDay == yesterday) {
      streak = state.checkinStreak + 1;
    } else if (state.lastCheckinDay == today && state.checkinStreak > 0) {
      // Streak already counts today (e.g. restored from cloud or granted
      // manually) — claiming the reward keeps it, not resets it.
      streak = state.checkinStreak;
    } else {
      streak = 1;
    }
    final bonus =
        ((streak - 1) * 5).clamp(0, 60); // grows with the streak, capped
    final total = checkinBase + bonus;
    state = state.copyWith(
      earned: state.earned + total,
      awardedKeys: {...state.awardedKeys, 'checkin_$today'},
      checkinStreak: streak,
      lastCheckinDay: today,
    );
    _persist();
    sync(); // streak-milestone gems
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

  // ── Generic Aura economy (used by the Village base-builder) ──
  /// Spends [cost] Aura if affordable. Returns false if not enough.
  bool spendAura(int cost) {
    if (cost <= 0) return true;
    if (cost > state.available) return false;
    state = state.copyWith(spent: state.spent + cost);
    _persist();
    return true;
  }

  /// Aura produced by town buildings. Goes to [GamificationState.bonus]:
  /// spendable, but it never raises your level.
  void addTownAura(int amt) {
    if (amt <= 0) return;
    state = state.copyWith(bonus: state.bonus + amt);
    _persist();
  }

  bool spendGems(int n) {
    if (n <= 0) return true;
    if (n > state.gems) return false;
    state = state.copyWith(gems: state.gems - n);
    _persist();
    return true;
  }
}
