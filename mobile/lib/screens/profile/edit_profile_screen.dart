import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_toast.dart';

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
  Uint8List? _photo;
  bool _photoRemoved = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(userProfileProvider).asData?.value;
    if (p != null) {
      _name.text = p.displayName ?? '';
      _phone.text = p.phone ?? '';
      _income.text =
          p.monthlyIncome > 0 ? inrToDisplayText(p.monthlyIncome) : '';
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
        imageQuality: 80,
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
        ScaffoldMessenger.of(context)
            .showToast(SnackBar(content: Text('Couldn\'t pick image: $e')));
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
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _photo = null;
                    _photoRemoved = true;
                  });
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
      monthlyIncome: _income.text.trim().isEmpty
          ? 0
          : displayToInr(_income.text) ?? p.monthlyIncome,
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
            .showToast(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = dark ? AerisColors.cardDark : Colors.white;

    final initials = _initials(_name.text.isNotEmpty ? _name.text : 'A');

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          // ── Avatar circle with camera badge ──────────────────
          const SizedBox(height: 12),
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: _photoSheet,
                  child: Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient:
                          _photo == null ? AerisColors.heroGradient : null,
                      color: _photo != null ? Colors.transparent : null,
                    ),
                    child: _photo != null
                        ? ClipOval(
                            child: Image.memory(_photo!, fit: BoxFit.cover))
                        : Align(
                            alignment: Alignment.center,
                            child: Text(initials,
                                style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: _photoSheet,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AerisColors.accent(context),
                        border: Border.all(color: scheme.surface, width: 3),
                      ),
                      child: Icon(Icons.camera_alt,
                          size: 15, color: AerisColors.onAccent(context)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Fields ───────────────────────────────────────────
          _Field(
            label: 'Full name',
            icon: Icons.person_outline,
            controller: _name,
            cardBg: cardBg,
            scheme: scheme,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          _Field(
            label: 'Phone',
            icon: Icons.phone_outlined,
            controller: _phone,
            cardBg: cardBg,
            scheme: scheme,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          _Field(
            label: 'Monthly income',
            icon: Icons.payments_outlined,
            prefix: kCurrency.symbol.trim(),
            controller: _income,
            cardBg: cardBg,
            scheme: scheme,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 22),

          // ── Save button ──────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AerisColors.accent(context),
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle:
                    const TextStyle(fontFamily: kFontFamily, fontSize: 15, fontWeight: FontWeight.w800),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: _busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AerisColors.onAccent(context)))
                  : const Text('Save changes'),
            ),
          ),

          // ── Remove photo ─────────────────────────────────────
          if (_photo != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => setState(() {
                _photo = null;
                _photoRemoved = true;
              }),
              child: Text('Remove photo',
                  style: TextStyle(color: AerisColors.danger(context), fontSize: 13.5)),
            ),
          ],
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'A';
  }
}

// ── Styled field ──────────────────────────────────────────────────────────────

class _Field extends StatefulWidget {
  final String label;
  final IconData icon;
  final String? prefix;
  final TextEditingController controller;
  final Color cardBg;
  final ColorScheme scheme;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.label,
    required this.icon,
    required this.controller,
    required this.cardBg,
    required this.scheme,
    this.prefix,
    this.keyboardType,
    this.onChanged,
  });

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final focused = _focus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface.withValues(alpha: 0.5))),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: widget.cardBg,
            border: Border.all(
                color: focused
                    ? AerisColors.accent(context).withValues(alpha: 0.6)
                    : scheme.onSurface.withValues(alpha: 0.12),
                width: focused ? 1.5 : 1),
            borderRadius: BorderRadius.circular(13),
          ),
          padding: const EdgeInsets.fromLTRB(15, 9, 9, 9),
          child: Row(
            children: [
              Icon(widget.icon,
                  size: 19, color: scheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 10),
              // ── greyish rectangle behind the input (right of the icon) ──
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.onSurface
                        .withValues(alpha: focused ? 0.10 : 0.05),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      if (widget.prefix != null) ...[
                        Text(widget.prefix!,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color:
                                    scheme.onSurface.withValues(alpha: 0.5))),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _focus,
                          keyboardType: widget.keyboardType,
                          onChanged: widget.onChanged,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                          // The surrounding row draws the field chrome, so
                          // switch off every themed border and the fill.
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
