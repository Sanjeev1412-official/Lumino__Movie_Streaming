import 'package:flutter/material.dart';
import 'package:lumino_app_moviestreaming/subtitle_settings_service.dart';
import 'package:lumino_app_moviestreaming/toast.dart';

class PlayerSubtitleSettingsPage extends StatefulWidget {
  const PlayerSubtitleSettingsPage({super.key});

  @override
  State<PlayerSubtitleSettingsPage> createState() => _PlayerSubtitleSettingsPageState();
}

class _PlayerSubtitleSettingsPageState extends State<PlayerSubtitleSettingsPage> {
  final SubtitleSettingsService _service = SubtitleSettingsService();
  late SubtitleSettings _current;

  static const List<Map<String, dynamic>> _textColorPresets = [
    {'name': 'White', 'color': Color(0xFFFFFFFF)},
    {'name': 'Yellow', 'color': Color(0xFFFFD700)},
    {'name': 'Amber', 'color': Color(0xFFFFB561)},
    {'name': 'Cyan', 'color': Color(0xFF00E5FF)},
    {'name': 'Green', 'color': Color(0xFF69F0AE)},
    {'name': 'Pink', 'color': Color(0xFFFF80AB)},
    {'name': 'Gray', 'color': Color(0xFFE0E0E0)},
  ];

  static const List<Map<String, dynamic>> _edgeColorPresets = [
    {'name': 'Black', 'color': Color(0xFF000000)},
    {'name': 'Charcoal', 'color': Color(0xFF262626)},
    {'name': 'Navy', 'color': Color(0xFF0A192F)},
    {'name': 'Dark Red', 'color': Color(0xFF3B0000)},
  ];

  @override
  void initState() {
    super.initState();
    _current = _service.current;
  }

  void _update(SubtitleSettings updated) {
    setState(() => _current = updated);
    _service.save(updated);
  }

  void _reset() {
    const defaults = SubtitleSettings();
    setState(() => _current = defaults);
    _service.resetToDefaults();
    AppToast.show(context, 'Reset subtitles to default style');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0D12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Player Subtitles',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFFFFB561)),
            label: const Text(
              'Reset',
              style: TextStyle(color: Color(0xFFFFB561), fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // 1. Live Preview Stage
          _buildLivePreviewStage(),
          const SizedBox(height: 24),

          // 2. Font Size
          _buildSectionCard(
            title: 'FONT SIZE',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB561).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_current.fontSize.toInt()} px',
                style: const TextStyle(
                  color: Color(0xFFFFB561),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSizeChip('Small', 18.0),
                    _buildSizeChip('Medium', 24.0),
                    _buildSizeChip('Large', 32.0),
                    _buildSizeChip('Extra', 40.0),
                  ],
                ),
                const SizedBox(height: 12),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFFFFB561),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                    thumbColor: const Color(0xFFFFB561),
                    overlayColor: const Color(0xFFFFB561).withValues(alpha: 0.2),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _current.fontSize.clamp(14.0, 52.0),
                    min: 14.0,
                    max: 52.0,
                    divisions: 38,
                    onChanged: (v) => _update(_current.copyWith(fontSize: v)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Text Color
          _buildSectionCard(
            title: 'TEXT COLOR',
            child: SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _textColorPresets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final preset = _textColorPresets[i];
                  final color = preset['color'] as Color;
                  final isSelected = _current.textColor.toARGB32() == color.toARGB32();

                  return GestureDetector(
                    onTap: () => _update(_current.copyWith(textColor: color)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? const Color(0xFFFFB561) : Colors.white24,
                              width: isSelected ? 2.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preset['name'] as String,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFFFFB561) : Colors.white38,
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4. Text Weight & Font Family
          _buildSectionCard(
            title: 'STYLE & FONT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildSelectablePill(
                        title: 'Normal Weight',
                        isSelected: !_current.isBold,
                        onTap: () => _update(_current.copyWith(isBold: false)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSelectablePill(
                        title: 'Bold Weight',
                        isSelected: _current.isBold,
                        onTap: () => _update(_current.copyWith(isBold: true)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Font Family',
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFontFamilyChip('Modern (Sans)', 'sans-serif'),
                    _buildFontFamilyChip('Classic (Serif)', 'serif'),
                    _buildFontFamilyChip('Monospace', 'monospace'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Edge / Outline Style
          _buildSectionCard(
            title: 'EDGE & SHADOW STYLE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildEdgeChip('Outline (Recommended)', SubtitleEdgeStyle.outline),
                    _buildEdgeChip('Drop Shadow', SubtitleEdgeStyle.dropShadow),
                    _buildEdgeChip('Raised', SubtitleEdgeStyle.raised),
                    _buildEdgeChip('Depressed', SubtitleEdgeStyle.depressed),
                    _buildEdgeChip('None', SubtitleEdgeStyle.none),
                  ],
                ),
                if (_current.edgeStyle != SubtitleEdgeStyle.none) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Edge Color',
                    style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: _edgeColorPresets.map((preset) {
                      final color = preset['color'] as Color;
                      final isSelected = _current.edgeColor.toARGB32() == color.toARGB32();
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () => _update(_current.copyWith(edgeColor: color)),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? const Color(0xFFFFB561) : Colors.white24,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check_rounded, size: 16, color: Color(0xFFFFB561))
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 6. Background Box
          _buildSectionCard(
            title: 'BACKGROUND BOX',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildBackgroundChip('None', SubtitleBackgroundStyle.none),
                _buildBackgroundChip('Subtle (35%)', SubtitleBackgroundStyle.subtle),
                _buildBackgroundChip('Semi-Dark (65%)', SubtitleBackgroundStyle.semiTransparent),
                _buildBackgroundChip('Solid Black (100%)', SubtitleBackgroundStyle.solid),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 7. Vertical Position (Bottom Offset)
          _buildSectionCard(
            title: 'VERTICAL POSITION',
            trailing: Text(
              '${_current.bottomPadding.toInt()} px from bottom',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            ),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFFFFB561),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                    thumbColor: const Color(0xFFFFB561),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _current.bottomPadding.clamp(15.0, 80.0),
                    min: 15.0,
                    max: 80.0,
                    divisions: 13,
                    onChanged: (v) => _update(_current.copyWith(bottomPadding: v)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildOffsetPreset('Low (20px)', 20.0),
                    _buildOffsetPreset('Standard (35px)', 35.0),
                    _buildOffsetPreset('High (60px)', 60.0),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreviewStage() {
    final previewBottom = (_current.bottomPadding * 0.5).clamp(8.0, 40.0);

    return Container(
      height: 175,
      decoration: BoxDecoration(
        color: const Color(0xFF161A24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Simulated cinematic video background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E2638),
                    Color(0xFF12141D),
                    Color(0xFF090A0E),
                  ],
                ),
              ),
            ),
            // Cinema lighting ambiance
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFB561).withValues(alpha: 0.08),
                ),
              ),
            ),
            // Header badge
            Positioned(
              top: 12,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.remove_red_eye_rounded, size: 12, color: Color(0xFFFFB561)),
                    SizedBox(width: 5),
                    Text(
                      'LIVE PREVIEW',
                      style: TextStyle(
                        color: Color(0xFFFFB561),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Live Subtitle Display
            Positioned(
              left: 16,
              right: 16,
              bottom: previewBottom,
              child: Center(
                child: Container(
                  padding: _current.backgroundStyle != SubtitleBackgroundStyle.none
                      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                      : EdgeInsets.zero,
                  decoration: _current.backgroundStyle != SubtitleBackgroundStyle.none
                      ? BoxDecoration(
                          color: _current.backgroundColor.withValues(alpha: _current.bgOpacity),
                          borderRadius: BorderRadius.circular(6),
                        )
                      : null,
                  child: Text(
                    'The journey of a thousand miles begins with a single step.',
                    textAlign: _current.textAlign,
                    style: TextStyle(
                      fontSize: (_current.fontSize * 0.70).clamp(11.0, 34.0),
                      height: 1.3,
                      color: _current.textColor,
                      fontWeight: _current.isBold ? FontWeight.bold : FontWeight.normal,
                      fontFamily: _current.fontFamily == 'sans-serif' ? null : _current.fontFamily,
                      shadows: _current.shadows,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141721),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildSizeChip(String label, double size) {
    final isSelected = (_current.fontSize - size).abs() < 1.0;
    return InkWell(
      onTap: () => _update(_current.copyWith(fontSize: size)),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFB561).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildFontFamilyChip(String label, String family) {
    final isSelected = _current.fontFamily == family;
    return InkWell(
      onTap: () => _update(_current.copyWith(fontFamily: family)),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFB561).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontFamily: family == 'sans-serif' ? null : family,
          ),
        ),
      ),
    );
  }

  Widget _buildEdgeChip(String label, SubtitleEdgeStyle style) {
    final isSelected = _current.edgeStyle == style;
    return InkWell(
      onTap: () => _update(_current.copyWith(edgeStyle: style)),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFB561).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundChip(String label, SubtitleBackgroundStyle style) {
    final isSelected = _current.backgroundStyle == style;
    return InkWell(
      onTap: () => _update(_current.copyWith(backgroundStyle: style)),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFB561).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectablePill({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFB561).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white70,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildOffsetPreset(String label, double offset) {
    final isSelected = (_current.bottomPadding - offset).abs() < 2.0;
    return GestureDetector(
      onTap: () => _update(_current.copyWith(bottomPadding: offset)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFB561).withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white38,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
