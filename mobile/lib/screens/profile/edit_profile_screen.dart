import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../utils/amount_input_formatter.dart';
import '../../utils/formatters.dart';
import '../../widgets/aeris_toast.dart';
import '../../widgets/discard_guard.dart';
import '../../widgets/ds.dart';
import '../../services/app_lock_service.dart';
import '../../providers/income_lock_provider.dart';

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

  // The screen opens behind the phone's lock (see verifyForProfile).
  late final IncomeLockController _lockCtl;
  bool? _deviceLock; // null while checking
  bool _verifying = false;

  // What was loaded, so leaving with unsaved edits asks first.
  late final String _name0, _phone0, _income0;
  late final Uint8List? _photo0;

  bool get _dirty =>
      _name.text != _name0 ||
      _phone.text != _phone0 ||
      _income.text != _income0 ||
      !identical(_photo, _photo0);

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
    _name0 = _name.text;
    _phone0 = _phone.text;
    _income0 = _income.text;
    _photo0 = _photo;
    for (final c in [_phone, _income]) {
      c.addListener(() => setState(() {}));
    }
    _lockCtl = ref.read(incomeLockProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  Future<void> _verify() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    final has = await AppLockService.instance.isAvailable();
    if (has) await _lockCtl.verifyForProfile();
    if (mounted) {
      setState(() {
        _deviceLock = has;
        _verifying = false;
      });
    }
  }

  // Salary on/off. Opening Profile already checked it's you, so no second
  // prompt here.
  Future<void> _setHideSalary(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _lockCtl.setEnabled(on, alreadyVerified: true);
    if (!ok || !mounted) return;
    messenger.showToast(SnackBar(
        content: Text(on
            ? 'Salary hidden across the app. Unlock it with your fingerprint or PIN.'
            : 'Salary will always show.')));
  }

  @override
  void dispose() {
    // Leaving Profile ends the unlocked visit (after this frame: providers
    // can't change while the tree is being torn down).
    Future.microtask(_lockCtl.relock);
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
              leading: const Icon(Ph.images),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Ph.camera),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            if (_photo != null)
              ListTile(
                leading: Icon(Ph.trash, color: context.tk.bad),
                title: Text('Remove photo',
                    style: TextStyle(color: context.tk.bad)),
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
    final cardBg = context.tk.surface;

    final initials = _initials(_name.text.isNotEmpty ? _name.text : 'A');

    final lock = ref.watch(incomeLockProvider);
    if (!(_deviceLock == false || (_deviceLock == true && lock.revealed))) {
      return _LockedProfile(busy: _verifying, onUnlock: _verify);
    }
    final hasLock = _deviceLock == true;

    return DiscardGuard(
      dirty: _dirty && !_busy,
      title: 'Discard changes?',
      message: "Your profile edits haven't been saved.",
      child: Scaffold(
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
                        color: _photo == null
                            ? const Color(0xFF8A7ED3).withValues(alpha: 0.22)
                            : Colors.transparent,
                      ),
                      child: _photo != null
                          ? ClipOval(
                              child: Image.memory(_photo!, fit: BoxFit.cover))
                          : Align(
                              alignment: Alignment.center,
                              child: Text(initials,
                                  style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                      color: context.tk.t1)),
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
                          border: Border.all(color: context.tk.bg, width: 3),
                        ),
                        child: Icon(Ph.camera,
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
              icon: Ph.user,
              controller: _name,
              cardBg: cardBg,
              scheme: scheme,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Phone',
              icon: Ph.phone,
              controller: _phone,
              cardBg: cardBg,
              scheme: scheme,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'Monthly income',
              icon: Ph.money,
              prefix: kCurrency.symbol.trim(),
              controller: _income,
              cardBg: cardBg,
              scheme: scheme,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            // Salary privacy lives next to the salary itself.
            AerisCard(
              padding: EdgeInsets.zero,
              child: SettingsRow(
                icon: lock.enabled ? Ph.eyeSlash : Ph.eye,
                title: 'Hide salary',
                sub: !hasLock
                    ? 'Set a screen lock on your phone to use this'
                    : lock.enabled
                        ? 'Shows as ₹•••• · fingerprint or PIN to see it'
                        : 'Salary shows like any other amount',
                trailing: Switch(
                  value: lock.enabled,
                  onChanged: hasLock ? _setHideSalary : null,
                ),
                onTap: hasLock ? () => _setHideSalary(!lock.enabled) : null,
              ),
            ),
            const SizedBox(height: 22),

            // ── Save button ──────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: _busy
                    ? RisingLoader(color: context.tk.onAcc)
                    : const Text('Save'),
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
                    style: TextStyle(
                        color: AerisColors.danger(context), fontSize: 13.5)),
              ),
            ],
          ],
        ),
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

// ── Locked: shown until the phone's lock confirms it's you ───────────────────

class _LockedProfile extends StatelessWidget {
  final bool busy;
  final VoidCallback onUnlock;
  const _LockedProfile({required this.busy, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final tk = context.tk;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: tk.accSoft, borderRadius: BorderRadius.circular(22)),
              child: Icon(Ph.lockSimple, size: 34, color: tk.acc),
            ),
            const SizedBox(height: 16),
            Text('Profile is locked',
                textAlign: TextAlign.center,
                style: Ts.title.copyWith(color: tk.t1)),
            const SizedBox(height: 6),
            Text(
                'Your salary and phone number are here. Unlock with your '
                'fingerprint, face or phone PIN.',
                textAlign: TextAlign.center,
                style: Ts.bodyS.copyWith(color: tk.t2)),
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              child: FilledButton.icon(
                onPressed: busy ? null : onUnlock,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                icon: busy
                    ? const SizedBox.shrink()
                    : const Icon(Ph.fingerprint, size: 20),
                label: busy
                    ? RisingLoader(color: tk.t2)
                    : const Text('Unlock'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
