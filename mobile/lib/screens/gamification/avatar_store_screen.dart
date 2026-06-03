import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/avatar_skin.dart';
import '../../providers/gamification_provider.dart';
import '../../widgets/aeris_avatar.dart';

class AvatarStoreScreen extends ConsumerWidget {
  const AvatarStoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gamificationProvider);
    final status = ref.watch(avatarStatusProvider);
    final ctrl = ref.read(gamificationProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avatars'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Chip(
                avatar: const Icon(Icons.auto_awesome, size: 16),
                label: Text('${g.available}'),
              ),
            ),
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(14),
        crossAxisCount: 2,
        childAspectRatio: 0.74,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: [
          for (final skin in Avatars.all)
            _SkinCard(
              skin: skin,
              stage: status.stage,
              unlocked: g.unlocked.contains(skin.id),
              selected: g.selected == skin.id,
              canAfford: g.available >= skin.cost,
              onSelect: () => ctrl.select(skin.id),
              onUnlock: () {
                final ok = ctrl.unlock(skin);
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Need ${skin.cost - g.available} more Aura to unlock ${skin.name}.')));
                }
              },
            ),
        ],
      ),
    );
  }
}

class _SkinCard extends StatelessWidget {
  final AvatarSkin skin;
  final int stage;
  final bool unlocked, selected, canAfford;
  final VoidCallback onSelect, onUnlock;
  const _SkinCard({
    required this.skin,
    required this.stage,
    required this.unlocked,
    required this.selected,
    required this.canAfford,
    required this.onSelect,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: selected
            ? BorderSide(color: skin.aura, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(
              child: Opacity(
                opacity: unlocked ? 1 : 0.55,
                child: AerisAvatar(
                    skin: skin,
                    stage: stage,
                    mood: AvatarMood.happy,
                    size: 110,
                    animate: false),
              ),
            ),
            Text(skin.name,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text(skin.tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: selected
                  ? const FilledButton(onPressed: null, child: Text('Selected'))
                  : unlocked
                      ? OutlinedButton(onPressed: onSelect, child: const Text('Use'))
                      : FilledButton.icon(
                          onPressed: onUnlock,
                          icon: const Icon(Icons.lock_open, size: 16),
                          label: Text('${skin.cost}'),
                          style: FilledButton.styleFrom(
                              backgroundColor: canAfford ? skin.aura : null),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
