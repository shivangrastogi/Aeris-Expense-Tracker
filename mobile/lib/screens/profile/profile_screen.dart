import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../providers/auth_provider.dart';
import '../../utils/formatters.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                CircleAvatar(
                  radius: 32,
                  backgroundImage: profile?.photoBytes != null
                      ? MemoryImage(profile!.photoBytes!)
                      : (profile?.photoUrl != null
                          ? NetworkImage(profile!.photoUrl!) as ImageProvider
                          : null),
                  child: (profile?.photoBytes == null && profile?.photoUrl == null)
                      ? const Icon(Icons.person, size: 30)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile?.displayName ?? 'Unnamed',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(profile?.email ?? ''),
                      if (profile != null && profile.monthlyIncome > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              'Income: ${formatRupees(profile.monthlyIncome)}/mo',
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.editProfile),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          _tile(context, Icons.auto_awesome, 'Your month in money · Wrapped',
              () => Navigator.pushNamed(context, AppRoutes.wrapped)),
          _tile(context, Icons.videogame_asset, 'Aeris World · avatars, challenges & more',
              () => Navigator.pushNamed(context, AppRoutes.aerisWorld)),
          _tile(context, Icons.account_balance, 'Accounts',
              () => Navigator.pushNamed(context, AppRoutes.accounts)),
          _tile(context, Icons.upload_file, 'Import bank statement',
              () => Navigator.pushNamed(context, AppRoutes.importStatement)),
          _tile(context, Icons.sms, 'Review SMS imports',
              () => Navigator.pushNamed(context, AppRoutes.smsReview)),
          _tile(context, Icons.settings, 'Settings',
              () => Navigator.pushNamed(context, AppRoutes.settings)),
          _tile(context, Icons.logout, 'Sign out',
              () => ref.read(authServiceProvider).signOut(),
              destructive: true),
        ],
      ),
    );
  }

  Widget _tile(BuildContext c, IconData icon, String label, VoidCallback onTap,
      {bool destructive = false}) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: destructive ? Colors.red : null),
        title: Text(label, style: TextStyle(
            color: destructive ? Colors.red : null,
            fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
