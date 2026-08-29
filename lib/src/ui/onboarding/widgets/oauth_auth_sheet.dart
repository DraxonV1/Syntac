import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ai/oauth/google_antigravity_oauth.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_typography.dart';
import '../../widgets/adaptive_sheet.dart';
import '../../widgets/app_buttons.dart';

/// Modal bottom sheet for OAuth authentication flows.
/// Displays clear instructions, one-tap URL copying, and browser launch.
class OAuthAuthSheet extends StatelessWidget {
  const OAuthAuthSheet({
    super.key,
    required this.request,
    required this.providerName,
  });

  final OAuthAuthRequest request;
  final String providerName;

  static Future<void> show({
    required BuildContext context,
    required OAuthAuthRequest request,
    required String providerName,
  }) {
    return AdaptiveSheet.show(
      context: context,
      title: 'Sign in to $providerName',
      subtitle: 'Complete authorization in your default browser',
      leading: AppIcons.providerLogo(providerName, size: 24),
      child: OAuthAuthSheet(request: request, providerName: providerName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            request.instructions,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Auth URL field
        Text('Authorization URL', style: AppTypography.label),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.codeBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.codeBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  request.launchUrl ?? request.url,
                  style: AppTypography.codeSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              AppIconButton(
                icon: AppIcons.copy,
                tooltip: 'Copy URL',
                size: 28,
                iconSize: 14,
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: request.launchUrl ?? request.url),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Authorization URL copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Actions
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Copy URL',
                icon: AppIcons.copy,
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: request.launchUrl ?? request.url),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Authorization URL copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
