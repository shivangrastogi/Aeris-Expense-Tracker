import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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

  Uint8List? _photo;     // current picture bytes (existing or newly picked)
  bool _photoRemoved = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(userProfileProvider).asData?.value;
    if (p != null) {
      _name.text = p.displayName ?? '';
      _phone.text = p.phone ?? '';
      _income.text = p.monthlyIncome > 0 ? p.monthlyIncome.toStringAsFixed(0) : '';
      _photo = p.photoBytes;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _income.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80, // keeps the encrypted blob small (~20-50 KB)
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (mounted) {
        setState(() {
          _photo = bytes;
          _photoRemoved = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn\'t pick image: $e')));
      }
    }
  }

  void _photoSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () { Navigator.pop(context); _pick(ImageSource.gallery); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () { Navigator.pop(context); _pick(ImageSource.camera); },
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() { _photo = null; _photoRemoved = true; });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final p = ref.read(userProfileProvider).asData?.value;
    if (p == null) return;
    setState(() => _busy = true);
    final updated = p.copyWith(
      displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      monthlyIncome: double.tryParse(_income.text) ?? p.monthlyIncome,
      photoBytes: _photoRemoved ? null : _photo,
      photoCleared: _photoRemoved,
    );
    try {
      await ref.read(authServiceProvider).saveProfile(updated);
      ref.invalidate(userProfileProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(children: [
          // ── Avatar with edit badge ──
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: scheme.surfaceContainerHighest,
                  backgroundImage: _photo != null ? MemoryImage(_photo!) : null,
                  child: _photo == null
                      ? Icon(Icons.person, size: 48, color: scheme.onSurfaceVariant)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: scheme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _photoSheet,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.camera_alt,
                            size: 18, color: scheme.onPrimary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Tap to change · stored end-to-end encrypted',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 22),

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
