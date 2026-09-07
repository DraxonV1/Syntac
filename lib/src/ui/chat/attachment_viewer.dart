// Safe local attachment viewer for images, text, and unreadable files.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

Future<void> showAttachmentViewer(
  BuildContext context,
  Attachment attachment,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AttachmentViewerSheet(attachment: attachment),
  );
}

class _AttachmentViewerSheet extends StatelessWidget {
  const _AttachmentViewerSheet({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderSubtle),
            Expanded(
              child: attachment.kind == AttachmentKind.image
                  ? _ImagePreview(attachment: attachment)
                  : _TextPreview(attachment: attachment),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Image.file(
          File(attachment.path),
          fit: BoxFit.contain,
          errorBuilder: (_, error, stackTrace) => const _NotReadable(),
        ),
      ),
    );
  }
}

class _TextPreview extends StatelessWidget {
  const _TextPreview({required this.attachment});

  final Attachment attachment;

  Future<String?> _readText() async {
    try {
      final file = File(attachment.path);
      final length = await file.length();
      if (length > 120000) {
        return '[Not Readable: file is too large to preview]';
      }
      final bytes = await file.readAsBytes();
      if (bytes.any((byte) => byte == 0)) return null;
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _readText(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final text = snapshot.data;
        if (text == null || text.isEmpty) return const _NotReadable();
        if (text.startsWith('[Not Readable:')) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                text,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            text,
            style: AppTypography.codeSmall.copyWith(
              color: AppColors.textPrimary,
              height: 1.45,
            ),
          ),
        );
      },
    );
  }
}

class _NotReadable extends StatelessWidget {
  const _NotReadable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Not Readable',
        style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}
