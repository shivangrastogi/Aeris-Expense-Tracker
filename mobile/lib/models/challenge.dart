import 'transaction.dart';

enum ChallengeType { noSpend, dailyCap, noCategory }

enum ChallengeState { upcoming, active, won, failed }

/// A self-imposed money challenge that AERIS verifies **passively** from your
/// transactions — no manual check-ins. e.g. "no spend for 5 days", "keep daily
/// spend under ₹300", "no Food & Dining for a week".
class Challenge {
  final String id;
  final ChallengeType type;
  final String title;
  final DateTime start;
  final DateTime end; // inclusive (end-of-day)
  final double param; // dailyCap amount; 0 for the others
  final String? categoryId; // for noCategory
  final int reward; // Aura on success

  const Challenge({
    required this.id,
    required this.type,
    required this.title,
    required this.start,
    required this.end,
    required this.reward,
    this.param = 0,
    this.categoryId,
  });

  int get days => end.difference(start).inDays + 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'param': param,
        'categoryId': categoryId,
        'reward': reward,
      };

  factory Challenge.fromJson(Map<String, dynamic> m) => Challenge(
        id: m['id'] as String,
        type: ChallengeType.values
            .firstWhere((t) => t.name == m['type'], orElse: () => ChallengeType.noSpend),
        title: (m['title'] as String?) ?? 'Challenge',
        start: DateTime.fromMillisecondsSinceEpoch((m['start'] as num).toInt()),
        end: DateTime.fromMillisecondsSinceEpoch((m['end'] as num).toInt()),
        param: (m['param'] as num?)?.toDouble() ?? 0,
        categoryId: m['categoryId'] as String?,
        reward: (m['reward'] as num?)?.toInt() ?? 0,
      );

  /// Verify against the user's transactions.
  ChallengeStatus evaluate(List<Transaction> txns, DateTime now) {
    final inWindow = txns.where((t) =>
        t.isDebit &&
        !t.timestamp.isBefore(start) &&
        !t.timestamp.isAfter(end));

    bool broken;
    switch (type) {
      case ChallengeType.noSpend:
        broken = inWindow.isNotEmpty;
        break;
      case ChallengeType.noCategory:
        broken = inWindow.any((t) => t.categoryId == categoryId);
        break;
      case ChallengeType.dailyCap:
        final perDay = <String, double>{};
        for (final t in inWindow) {
          final k = '${t.timestamp.year}-${t.timestamp.month}-${t.timestamp.day}';
          perDay[k] = (perDay[k] ?? 0) + t.amount;
        }
        broken = perDay.values.any((v) => v > param);
        break;
    }

    if (broken) return const ChallengeStatus(ChallengeState.failed, 'Broken — better luck next time');
    if (now.isBefore(start)) {
      return ChallengeStatus(ChallengeState.upcoming, 'Starts soon', 0);
    }
    if (now.isAfter(end)) {
      return const ChallengeStatus(ChallengeState.won, 'Completed! Aura awarded', 1);
    }
    final total = end.difference(start).inSeconds;
    final done = now.difference(start).inSeconds;
    final p = total <= 0 ? 1.0 : (done / total).clamp(0.0, 1.0);
    final daysLeft = end.difference(now).inDays + 1;
    return ChallengeStatus(
        ChallengeState.active, 'On track · $daysLeft day${daysLeft == 1 ? '' : 's'} left', p);
  }
}

class ChallengeStatus {
  final ChallengeState state;
  final String detail;
  final double progress; // 0..1
  const ChallengeStatus(this.state, this.detail, [this.progress = 0]);
}
