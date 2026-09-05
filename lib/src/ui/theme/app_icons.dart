import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'app_colors.dart';

abstract class AppIcons {
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
  static const IconData minimize = Icons.fullscreen_exit_rounded;
  static const IconData maximize = Icons.fullscreen_rounded;
  static const IconData expandMore = Icons.unfold_more_rounded;
  static const IconData expandLess = Icons.unfold_less_rounded;
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
  static const IconData terminal = Icons.terminal_rounded;
  static const IconData runtime = Icons.memory_rounded;
  static const IconData cpu = Icons.developer_board_rounded;
  static const IconData memory = Icons.memory_rounded;
  static const IconData storage = Icons.storage_rounded;
  static const IconData database = Icons.dns_rounded;
  static const IconData lock = Icons.lock_outline_rounded;
  static const IconData key = Icons.vpn_key_outlined;
  static const IconData code = Icons.code_rounded;
  static const IconData success = Icons.check_circle_rounded;
  static const IconData error = Icons.error_rounded;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData help = Icons.help_outline_rounded;
  static const IconData diff = Icons.difference_rounded;

  static Widget providerLogo(
    String? providerKey, {
    double size = 18,
    Color? color,
  }) {
    final slug = _providerSlug(providerKey);
    return LobeLogo(
      slug: slug,
      size: size,
      color: color ?? AppColors.textPrimary,
      preserveColors: slug == 'google' || slug == 'codex',
    );
  }

  static Widget modelLogo(
    String modelId, {
    String? providerKey,
    double size = 20,
    Color? color,
  }) => LobeLogo(
    slug: _modelSlug(modelId, providerKey: providerKey),
    size: size,
    color: color ?? AppColors.textPrimary,
  );
  static Widget runtimeLogo(
    String? runtimeKey, {
    double size = 18,
    Color? color,
  }) {
    final key = runtimeKey?.toLowerCase() ?? '';
    final url = key.contains('termux')
        ? 'https://api.iconify.design/arcticons:termux.svg'
        : 'https://api.iconify.design/simple-icons:archlinux.svg';
    return RemoteSvgLogo(
      url: url,
      size: size,
      color: color ?? AppColors.textPrimary,
      semanticsLabel: '$runtimeKey logo',
    );
  }

  static String _providerSlug(String? providerKey) {
    final key = providerKey?.toLowerCase() ?? '';
    return switch (true) {
      _ when key == 'google-antigravity' => 'antigravity',
      _ when key.contains('google') || key.contains('gemini') => 'google',
      _ when key == 'openai-codex' || key.contains('codex') => 'codex',
      _ when key == 'xai-oauth' || key.contains('grok') => 'grok',
      _ when key == 'xai' => 'xai',
      _ when key.contains('deepseek') => 'deepseek',
      _ when key.contains('openrouter') => 'openrouter',
      _ when key.contains('anthropic') || key.contains('claude') => 'anthropic',
      _ => 'lobehub',
    };
  }

  static String _modelSlug(String modelId, {String? providerKey}) {
    final key = modelId.toLowerCase();
    return switch (true) {
      _ when key.contains('claude') => 'claude',
      _ when key.contains('gemini') => 'gemini',
      _ when key.contains('grok') => 'grok',
      _ when key.contains('deepseek') => 'deepseek',
      _ when key.contains('qwen') => 'qwen',
      _ when key.contains('llama') => 'meta',
      _ when key.contains('mistral') => 'mistral',
      _ when key.contains('gpt') || key.contains('openai') => 'openai',
      _ => _providerSlug(providerKey),
    };
  }
}

class LobeLogo extends StatelessWidget {
  const LobeLogo({
    super.key,
    required this.slug,
    this.size = 18,
    this.color = Colors.white,
    this.preserveColors = false,
  });

  static const cdnBase =
      'https://unpkg.com/@lobehub/icons-static-svg@latest/icons';

  final String slug;
  final double size;
  final Color color;
  final bool preserveColors;

  @override
  Widget build(BuildContext context) => RemoteSvgLogo(
    url: '$cdnBase/${preserveColors ? '$slug-color' : slug}.svg',
    size: size,
    color: color,
    preserveColors: preserveColors,
    semanticsLabel: '$slug logo',
  );
}

class RemoteSvgLogo extends StatefulWidget {
  const RemoteSvgLogo({
    super.key,
    required this.url,
    required this.semanticsLabel,
    this.size = 18,
    this.color = Colors.white,
    this.preserveColors = false,
  });

  final String url;
  final String semanticsLabel;
  final double size;
  final Color color;
  final bool preserveColors;
  @override
  State<RemoteSvgLogo> createState() => _RemoteSvgLogoState();
}

class _RemoteSvgLogoState extends State<RemoteSvgLogo> {
  late Future<String?> _svg;

  @override
  void initState() {
    super.initState();
    _svg = _loadSvg();
  }

  @override
  void didUpdateWidget(covariant RemoteSvgLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _svg = _loadSvg();
  }

  Future<String?> _loadSvg() async {
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode != 200) return null;
      final svg = response.body.trimLeft();
      return svg.startsWith('<svg') ? svg : null;
    } catch (_) {
      return null;
    }
  }

  Widget _fallback() => SizedBox(
    width: widget.size,
    height: widget.size,
    child: Icon(Icons.circle, size: widget.size * 0.45, color: widget.color),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _svg,
    builder: (context, snapshot) {
      final svg = snapshot.data;
      if (svg == null) return _fallback();
      return SvgPicture.string(
        svg,
        width: widget.size,
        height: widget.size,
        colorFilter: widget.preserveColors
            ? null
            : ColorFilter.mode(widget.color, BlendMode.srcIn),
        semanticsLabel: widget.semanticsLabel,
      );
    },
  );
}
