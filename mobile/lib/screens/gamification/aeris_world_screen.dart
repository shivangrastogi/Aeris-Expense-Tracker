import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/avatar_skin.dart';
import '../../providers/gamification_provider.dart';
import '../../widgets/aeris_avatar.dart';
import 'avatar_store_screen.dart';
import 'bosses_screen.dart';
import 'challenges_screen.dart';
import 'customize_dashboard_screen.dart';
import 'future_self_screen.dart';
import 'garden_screen.dart';

class AerisWorldScreen extends ConsumerStatefulWidget {
  const AerisWorldScreen({super.key});
  @override
  ConsumerState<AerisWorldScreen> createState() => _AerisWorldScreenState();
}

class _AerisWorldScreenState extends ConsumerState<AerisWorldScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(gamificationProvider.notifier).sync());
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(gamificationProvider);
    final status = ref.watch(avatarStatusProvider);
    final progress = (g.earned % auraPerLevel) / auraPerLevel;

    return Scaffold(
      appBar: AppBar(title: const Text('Aeris World')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          Center(
            child: AerisAvatar(
                skin: status.skin,
                stage: status.stage,
                mood: status.mood,
                size: 200),
          ),
          Center(
            child: Text(
              'Level ${status.level} · ${stageNames[status.stage]} ${status.skin.name}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Chip(
              avatar: const Icon(Icons.auto_awesome, size: 16),
              label: Text('${g.available} Aura available'),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: progress, minHeight: 10, color: status.skin.aura),
          ),
          const SizedBox(height: 4),
          Text('${auraToNextLevel(g.earned)} Aura to level ${status.level + 1}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _hub(context, '🧑‍🎤', 'Avatars', 'Unlock & switch', AerisColors.info,
                  const AvatarStoreScreen()),
              _hub(context, '🔥', 'Challenges', 'Auto-verified', AerisColors.warning,
                  const ChallengesScreen()),
              _hub(context, '🌱', 'Money Garden', 'Grows as you save',
                  AerisColors.credit, const GardenScreen()),
              _hub(context, '🔮', 'Future Self', 'Project your wealth',
                  AerisColors.seed, const FutureSelfScreen()),
              _hub(context, '⚔️', 'Boss battles', 'Beat your budgets',
                  AerisColors.debit, const BossesScreen()),
              _hub(context, '🎨', 'Customize', 'Your dashboard',
                  AerisColors.moodWorried, const CustomizeDashboardScreen()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hub(BuildContext context, String emoji, String title, String sub,
      Color color, Widget screen) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => screen)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 6),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
