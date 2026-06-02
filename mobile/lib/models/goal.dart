/// A savings goal the user is working toward (e.g. "Trip to Goa").
/// All fields are JSON-safe (dates as epoch millis) so the whole object can be
/// encrypted into a single blob before it touches Firestore.
class Goal {
  final String id;
  final String title;
  final double target;
  final double saved;
  final String emoji;
  final DateTime? deadline;
  final DateTime createdAt;

  const Goal({
    required this.id,
    required this.title,
    required this.target,
    required this.createdAt,
    this.saved = 0,
    this.emoji = '🎯',
    this.deadline,
  });

  double get progress => target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0);
  bool get isComplete => target > 0 && saved >= target;
  double get remaining => (target - saved).clamp(0, double.infinity);

  Map<String, dynamic> toMap() => {
        'title': title,
        'target': target,
        'saved': saved,
        'emoji': emoji,
        'deadline': deadline?.millisecondsSinceEpoch,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Goal.fromMap(String id, Map<String, dynamic> m) => Goal(
        id: id,
        title: (m['title'] as String?) ?? 'Goal',
        target: (m['target'] as num?)?.toDouble() ?? 0,
        saved: (m['saved'] as num?)?.toDouble() ?? 0,
        emoji: (m['emoji'] as String?) ?? '🎯',
        deadline: m['deadline'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((m['deadline'] as num).toInt()),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (m['createdAt'] as num?)?.toInt() ?? 0),
      );

  Goal copyWith({String? title, double? target, double? saved, String? emoji,
          DateTime? deadline}) =>
      Goal(
        id: id,
        title: title ?? this.title,
        target: target ?? this.target,
        saved: saved ?? this.saved,
        emoji: emoji ?? this.emoji,
        deadline: deadline ?? this.deadline,
        createdAt: createdAt,
      );
}
