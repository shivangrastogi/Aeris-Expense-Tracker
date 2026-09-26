import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Largest receipt we'll store. Encrypted + base64 it grows ~1.35×, which
/// keeps it comfortably under Firestore's 1 MiB document limit.
const int kMaxReceiptBytes = 600 * 1024;

/// Asks camera vs gallery, then returns a downscaled JPEG (or null if
/// cancelled). Shows a message and returns null if it's still too large.
Future<Uint8List?> pickReceipt(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (s) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(s, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(s, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    final x = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 60,
    );
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    if (bytes.length > kMaxReceiptBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('That image is too large — try a closer photo.')));
      }
      return null;
    }
    return bytes;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open image: $e')));
    }
    return null;
  }
}

/// Full-screen, pinch-to-zoom receipt viewer.
void showReceiptViewer(BuildContext context, Uint8List bytes) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Receipt'),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(bytes),
        ),
      ),
    ),
  ));
}

/// "Attach receipt" button, or a thumbnail with view / remove once attached.
class ReceiptField extends StatelessWidget {
  final Uint8List? bytes;
  final bool loading;
  final ValueChanged<Uint8List> onPicked;
  final VoidCallback onRemove;

  const ReceiptField({
    super.key,
    required this.bytes,
    required this.onPicked,
    required this.onRemove,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) {
      return const SizedBox(
          height: 56, child: Center(child: CircularProgressIndicator()));
    }
    final b = bytes;
    if (b == null) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: () async {
          final picked = await pickReceipt(context);
          if (picked != null) onPicked(picked);
        },
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Attach receipt (optional)'),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => showReceiptViewer(context, b),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(b, width: 56, height: 56, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Receipt attached',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text('${(b.length / 1024).round()} KB · tap to view',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove receipt',
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
