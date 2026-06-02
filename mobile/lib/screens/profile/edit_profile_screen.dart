import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _income = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(userProfileProvider).asData?.value;
    if (p != null) {
      _name.text = p.displayName ?? '';
      _phone.text = p.phone ?? '';
      _income.text = p.monthlyIncome > 0 ? p.monthlyIncome.toStringAsFixed(0) : '';
    }
  }

  Future<void> _save() async {
    final p = ref.read(userProfileProvider).asData?.value;
    if (p == null) return;
    setState(() => _busy = true);
    final updated = p.copyWith(
      displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      monthlyIncome: double.tryParse(_income.text) ?? p.monthlyIncome,
    );
    await ref.read(authServiceProvider).saveProfile(updated);
    ref.invalidate(userProfileProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(children: [
          TextField(controller: _name, decoration: const InputDecoration(
              labelText: 'Display name', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(controller: _phone, decoration: const InputDecoration(
              labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined)),
              keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          TextField(
              controller: _income,
              decoration: const InputDecoration(
                  labelText: 'Monthly income (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                  helperText: 'Used for saving-rate recommendations'),
              keyboardType: TextInputType.number),
          const SizedBox(height: 20),
          ElevatedButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save')),
        ]),
      ),
    );
  }
}
