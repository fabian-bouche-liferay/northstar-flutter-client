import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/entry.dart';

/// Shows the QR code encoding the entry's external reference code.
Future<void> showEntryQr(BuildContext context, Entry entry) => showDialog(
  context: context,
  builder: (context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white, // dark-mode safe: QR needs a light quiet zone
            padding: const EdgeInsets.all(12),
            // Fixed size: AlertDialog measures intrinsic sizes, which the
            // LayoutBuilder inside QrImageView does not support.
            child: SizedBox.square(
              dimension: 220,
              child: QrImageView(
                data: entry.erc,
                size: 220,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            entry.erc,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'Scan it with the Northstar KB mobile app',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy code'),
          onPressed: () => Clipboard.setData(ClipboardData(text: entry.erc)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  },
);
