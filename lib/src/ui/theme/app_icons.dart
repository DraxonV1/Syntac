import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Semantic vector icons and branded visual marks for providers and runtime systems.
/// Replaces all emojis with clean, crisp, outlined vector icons.
abstract class AppIcons {
  // Navigation & Core Actions
  static const IconData back = Icons.arrow_back_rounded;
  static const IconData forward = Icons.arrow_forward_rounded;
  static const IconData home = Icons.home_rounded;
  static const IconData menu = Icons.menu_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData add = Icons.add_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData settings = Icons.settings_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData copy = Icons.content_copy_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData externalLink = Icons.open_in_new_rounded;
  static const IconData chevronDown = Icons.keyboard_arrow_down_rounded;
  static const IconData chevronRight = Icons.keyboard_arrow_right_rounded;
  static const IconData chevronUp = Icons.keyboard_arrow_up_rounded;

  // Sizing & View Controls
  static const IconData minimize = Icons.fullscreen_exit_rounded;
  static const IconData maximize = Icons.fullscreen_rounded;
  static const IconData expandMore = Icons.unfold_more_rounded;
  static const IconData expandLess = Icons.unfold_less_rounded;

  // Workspace & Chat
  static const IconData chat = Icons.chat_bubble_outline_rounded;
  static const IconData chatFilled = Icons.chat_bubble_rounded;
  static const IconData project = Icons.folder_special_rounded;
  static const IconData folder = Icons.folder_rounded;
  static const IconData folderOpen = Icons.folder_open_rounded;
  static const IconData file = Icons.description_outlined;
  static const IconData upload = Icons.file_upload_outlined;
  static const IconData attach = Icons.attach_file_rounded;
  static const IconData send = Icons.arrow_upward_rounded;
  static const IconData stop = Icons.stop_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData model = Icons.auto_awesome_outlined;
  static const IconData prompt = Icons.terminal_rounded;

  // System, Runtime & Storage
  static const IconData terminal = Icons.terminal_rounded;
  static const IconData runtime = Icons.memory_rounded;
  static const IconData cpu = Icons.developer_board_rounded;
  static const IconData memory = Icons.memory_rounded;
  static const IconData storage = Icons.storage_rounded;
  static const IconData database = Icons.dns_rounded;
  static const IconData lock = Icons.lock_outline_rounded;
  static const IconData key = Icons.vpn_key_outlined;
  static const IconData code = Icons.code_rounded;

  // Status & Feedback
  static const IconData success = Icons.check_circle_rounded;
  static const IconData error = Icons.error_rounded;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData help = Icons.help_outline_rounded;
  static const IconData diff = Icons.difference_rounded;

  /// Returns a branded logo widget for the given provider key.
  static Widget providerLogo(
    String? providerKey, {
    double size = 18,
    Color? color,
  }) {
    final key = providerKey?.toLowerCase() ?? '';
    if (key.contains('google') ||
        key.contains('antigravity') ||
        key.contains('gemini')) {
      return GoogleBrandMark(size: size);
    }
    if (key.contains('openai') || key.contains('codex')) {
      return OpenAIBrandMark(size: size, color: color ?? AppColors.textPrimary);
    }
    if (key.contains('anthropic') || key.contains('claude')) {
      return AnthropicBrandMark(
        size: size,
        color: color ?? const Color(0xFFCC785C),
      );
    }
    if (key.contains('grok') || key.contains('xai')) {
      return Icon(
        Icons.bolt_rounded,
        size: size,
        color: color ?? AppColors.primaryBright,
      );
    }
    return Icon(
      Icons.api_rounded,
      size: size,
      color: color ?? AppColors.primaryBright,
    );
  }

  /// Returns a branded icon for runtime types (Arch Linux, Termux, etc.).
  static Widget runtimeLogo(
    String? runtimeKey, {
    double size = 18,
    Color? color,
  }) {
    final key = runtimeKey?.toLowerCase() ?? '';
    if (key.contains('arch') ||
        key.contains('archlinux') ||
        key.contains('local')) {
      return ArchLinuxBrandMark(
        size: size,
        color: color ?? const Color(0xFF1793D1),
      );
    }
    if (key.contains('termux')) {
      return TermuxBrandMark(size: size, color: color ?? AppColors.success);
    }
    return Icon(
      Icons.memory_rounded,
      size: size,
      color: color ?? AppColors.primary,
    );
  }
}

/// Google 4-color branded mark
class GoogleBrandMark extends StatelessWidget {
  const GoogleBrandMark({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: CustomPaint(size: Size(size, size), painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.22;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );

    // Red arc (top)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -3.14 * 0.75, 3.14 * 0.55, false, paint);

    // Yellow arc (left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, -3.14 * 1.3, 3.14 * 0.55, false, paint);

    // Green arc (bottom)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 3.14 * 0.25, 3.14 * 0.55, false, paint);

    // Blue bar & arc (right)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -3.14 * 0.2, 3.14 * 0.45, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// OpenAI branded vector mark
class OpenAIBrandMark extends StatelessWidget {
  const OpenAIBrandMark({super.key, this.size = 18, this.color = Colors.white});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.token_rounded, size: size, color: color);
  }
}

/// Anthropic branded vector mark
class AnthropicBrandMark extends StatelessWidget {
  const AnthropicBrandMark({
    super.key,
    this.size = 18,
    this.color = const Color(0xFFCC785C),
  });
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.flare_rounded, size: size, color: color);
  }
}

/// DeepSeek mark
class DeepSeekBrandMark extends StatelessWidget {
  const DeepSeekBrandMark({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.explore_rounded,
      size: size,
      color: const Color(0xFF4D6BFE),
    );
  }
}

/// Arch Linux triangle mark
class ArchLinuxBrandMark extends StatelessWidget {
  const ArchLinuxBrandMark({
    super.key,
    this.size = 18,
    this.color = const Color(0xFF1793D1),
  });
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.change_history_rounded, size: size, color: color);
  }
}

/// Termux prompt mark
class TermuxBrandMark extends StatelessWidget {
  const TermuxBrandMark({
    super.key,
    this.size = 18,
    this.color = AppColors.success,
  });
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceFloating,
        borderRadius: BorderRadius.circular(size * 0.2),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Text(
        '>_',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: size * 0.55,
          fontWeight: FontWeight.bold,
          color: color,
          height: 1,
        ),
      ),
    );
  }
}
