import 'package:flutter/material.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'theme.dart';

/// A full-bleed placeholder shown before the user has picked anything: an
/// icon, a headline, a short hint, and a prominent call-to-action button.
class EmptyState extends StatelessWidget {
  /// Creates an [EmptyState].
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.onPressed,
  });

  /// The icon shown above the title.
  final IconData icon;

  /// The short headline.
  final String title;

  /// A one- or two-line supporting message.
  final String message;

  /// The label of the primary action button.
  final String buttonLabel;

  /// The icon of the primary action button.
  final IconData buttonIcon;

  /// Called when the primary action button is pressed.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(buttonIcon),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small, bold section title used above a group of related controls.
class SectionHeader extends StatelessWidget {
  /// Creates a [SectionHeader].
  const SectionHeader(this.title, {super.key, this.trailing});

  /// The section's title text.
  final String title;

  /// An optional trailing widget (e.g. a button) aligned to the end.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

/// A single label/value row, e.g. inside a metadata or estimate card.
class StatRow extends StatelessWidget {
  /// Creates a [StatRow].
  const StatRow(this.label, this.value, {super.key, this.valueColor});

  /// The row's label (left column).
  final String label;

  /// The row's value (right column).
  final String value;

  /// An optional override colour for the value text.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A large, rounded badge highlighting a size-reduction percentage, e.g.
/// `−42%`.
class ReductionBadge extends StatelessWidget {
  /// Creates a [ReductionBadge] for the given [ratio] (0..100).
  const ReductionBadge({super.key, required this.ratio});

  /// The size-reduction percentage to display.
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '−${ratio.toStringAsFixed(0)}%',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: scheme.onTertiaryContainer,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// A labelled chip group offering all five [VideoQuality] presets (wraps to a
/// second row on narrow screens instead of squeezing five segments onto one).
class QualitySelector extends StatelessWidget {
  /// Creates a [QualitySelector].
  const QualitySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The currently selected quality.
  final VideoQuality value;

  /// Called with the newly selected quality.
  final ValueChanged<VideoQuality>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader('Quality'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              for (final MapEntry<VideoQuality, String> e
                  in const <VideoQuality, String>{
                VideoQuality.very_low: 'Very low',
                VideoQuality.low: 'Low',
                VideoQuality.medium: 'Medium',
                VideoQuality.high: 'High',
                VideoQuality.very_high: 'Very high',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: value == e.key,
                  onSelected:
                      onChanged == null ? null : (_) => onChanged!(e.key),
                ),
            ],
          ),
        ],
      );
}

/// A labelled [SegmentedButton] choosing between H.264 and H.265 (HEVC).
class CodecSelector extends StatelessWidget {
  /// Creates a [CodecSelector].
  const CodecSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The currently selected codec.
  final VideoFormat value;

  /// Called with the newly selected codec.
  final ValueChanged<VideoFormat>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader('Codec'),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<VideoFormat>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<VideoFormat>>[
              ButtonSegment<VideoFormat>(
                value: VideoFormat.h264,
                label: Text('H.264 (AVC)'),
              ),
              ButtonSegment<VideoFormat>(
                value: VideoFormat.h265,
                label: Text('H.265 (HEVC)'),
              ),
            ],
            selected: <VideoFormat>{value},
            onSelectionChanged: onChanged == null
                ? null
                : (Set<VideoFormat> s) => onChanged!(s.first),
          ),
          if (value == VideoFormat.h265)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Falls back to H.264 automatically if the device has no '
                'hardware HEVC encoder.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      );
}

/// A numeric text field with a compact label/helper, used for the "Advanced"
/// section's free-form inputs (target size, fps, audio kbps, trim bounds).
class NumberField extends StatelessWidget {
  /// Creates a [NumberField].
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.enabled,
    this.helperText,
    this.suffixText,
  });

  /// The backing controller.
  final TextEditingController controller;

  /// The floating label text.
  final String label;

  /// The helper text shown below the field.
  final String? helperText;

  /// An optional unit shown inside the trailing edge of the field (e.g. `MB`).
  final String? suffixText;

  /// Whether the field accepts input.
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          suffixText: suffixText,
          border: const OutlineInputBorder(),
        ),
      );
}

/// A labelled slider with a numeric readout, used for the colour-adjust
/// controls (brightness/contrast/saturation).
class LabeledSlider extends StatelessWidget {
  /// Creates a [LabeledSlider].
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  /// The slider's label.
  final String label;

  /// The current value.
  final double value;

  /// The minimum selectable value.
  final double min;

  /// The maximum selectable value.
  final double max;

  /// Called with the new value as the slider moves; `null` disables it.
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      );
}
