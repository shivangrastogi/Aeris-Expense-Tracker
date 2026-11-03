import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'aeris_toast.dart';
import 'ds.dart';

/// Largest receipt we'll store. Encrypted + base64 it grows ~1.35×, which
/// keeps it comfortably under Firestore's 1 MiB document limit.
const int kMaxReceiptBytes = 600 * 1024;

/// [path] as a receipt to store: a JPEG whose shorter side is at most
/// 1080 px (so a phone screenshot keeps its full width), stepped down until
/// it fits [kMaxReceiptBytes]. Null if it won't fit or can't be read.
Future<Uint8List?> shrinkReceipt(String path) async {
  for (final (side, quality) in const [(1080, 80), (1080, 65), (800, 60)]) {
    try {
      final out = await FlutterImageCompress.compressWithFile(path,
          minWidth: side, minHeight: side, quality: quality);
      if (out != null && out.length <= kMaxReceiptBytes) return out;
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// A picked receipt: [bytes] to store, and the full-size original at [path]
/// to read the text from (small print needs every pixel).
typedef PickedReceipt = ({Uint8List bytes, String path});

/// Asks camera vs gallery, then returns the photo (or null if cancelled).
/// Shows a message and returns null if it can't be made small enough.
Future<PickedReceipt?> pickReceipt(BuildContext context) async {
  final source = await _askSource(context);
  if (source == null) return null;
  try {
    final x = await ImagePicker().pickImage(source: source);
    if (x == null) return null;
    final bytes = await shrinkReceipt(x.path);
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showToast(const SnackBar(
            content: Text('That image is too large — try a closer photo.')));
      }
      return null;
    }
    return (bytes: bytes, path: x.path);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showToast(SnackBar(content: Text('Could not open image: $e')));
    }
    return null;
  }
}

/// Asks camera vs gallery, then returns the full-size photo's path to scan
/// (or null if cancelled). The image itself is never stored.
Future<String?> pickScanImage(BuildContext context) async {
  final source = await _askSource(context);
  if (source == null) return null;
  try {
    return (await ImagePicker().pickImage(source: source))?.path;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showToast(SnackBar(content: Text('Could not open image: $e')));
    }
    return null;
  }
}

Future<ImageSource?> _askSource(BuildContext context) =>
    showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Ph.camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(s, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Ph.images),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(s, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

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
          if (picked != null) onPicked(picked.bytes);
        },
        icon: const Icon(Ph.receipt),
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
            icon: const Icon(Ph.trash),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
