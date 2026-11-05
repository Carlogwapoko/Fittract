import 'package:flutter/material.dart';

import '../store/store.dart';
import 'shared_widgets.dart';

const _todayTeal = Color(0xFF0B6B60);
const _todayMint = Color(0xFFA6E9D7);
const _todayDarkGreen = Color(0xFF1B4943);

class StreakChip extends StatelessWidget {
  final int days;

  const StreakChip({super.key, required this.days});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark(context) ? .16 : .06),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department,
            color: Color(0xFFEA7A35),
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            '$days-day streak',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class RoundActionButton extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final double height;
  final double? width;
  final bool circular;

  const RoundActionButton({
    super.key,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
    this.label,
    this.icon,
    this.tooltip,
    this.height = 44,
    this.width,
    this.circular = false,
  });

  @override
  State<RoundActionButton> createState() => _RoundActionButtonState();
}

class _RoundActionButtonState extends State<RoundActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.circular ? widget.height : null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.circular ? 99 : 99),
      side: BorderSide(
        color: _hovered
            ? _todayTeal
            : (widget.borderColor ?? Colors.transparent),
        width: _hovered || widget.borderColor != null ? 1.2 : 0,
      ),
    );

    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      child: AnimatedScale(
        scale: _pressed ? .96 : (_hovered ? 1.025 : 1),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: widget.circular ? widget.height : 44,
          ),
          child: SizedBox(
            width: widget.width ?? size,
            height: widget.height,
            child: Material(
              color: widget.backgroundColor,
              shape: shape,
              elevation: _hovered ? 4 : 0,
              shadowColor: _todayTeal.withValues(alpha: .24),
              child: InkWell(
                customBorder: shape,
                splashFactory: NoSplash.splashFactory,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTapDown: (_) => setState(() => _pressed = true),
                onTapCancel: () => setState(() => _pressed = false),
                onTap: () {
                  setState(() => _pressed = false);
                  widget.onPressed();
                },
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.circular ? 0 : 10,
                    ),
                    child: widget.icon != null && widget.label == null
                        ? Icon(
                            widget.icon,
                            size: 20,
                            color: widget.foregroundColor,
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(
                                  widget.icon,
                                  size: 17,
                                  color: widget.foregroundColor,
                                ),
                                if (widget.label != null)
                                  const SizedBox(width: 4),
                              ],
                              if (widget.label != null)
                                Text(
                                  widget.label!,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: widget.foregroundColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.icon != null && widget.label == null && widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

class ProgressRingCard extends StatefulWidget {
  final String title;
  final String value;
  final String? unit;
  final String? supportingText;
  final String subtitle;
  final IconData icon;
  final Color? accentColor;
  final Color? backgroundColor;
  final Color? subtitleColor;
  final double? progress;
  final bool estimated;
  final VoidCallback onTap;

  const ProgressRingCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accentColor,
    this.unit,
    this.supportingText,
    this.backgroundColor,
    this.subtitleColor,
    this.progress,
    this.estimated = false,
  });

  @override
  State<ProgressRingCard> createState() => _ProgressRingCardState();
}

class _ProgressRingCardState extends State<ProgressRingCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(20);
    final iconColor =
        widget.accentColor ?? (isDark(context) ? _todayMint : _todayTeal);
    final border = RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(
        color: _hovered ? _todayTeal : colors.outlineVariant,
        width: _hovered ? 1.2 : 1,
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      child: AnimatedScale(
        scale: _pressed ? .985 : (_hovered ? 1.01 : 1),
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          height: 144,
          child: Material(
            color: widget.backgroundColor ?? colors.surface,
            shape: border,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: border,
              splashFactory: NoSplash.splashFactory,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (widget.progress != null)
                                SizedBox.expand(
                                  child: CircularProgressIndicator(
                                    value: progressOf(widget.progress!),
                                    strokeWidth: 2.5,
                                    strokeCap: StrokeCap.round,
                                    color: iconColor,
                                    backgroundColor: colors.outlineVariant
                                        .withValues(alpha: .65),
                                  ),
                                ),
                              Icon(widget.icon, size: 21, color: iconColor),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            widget.title,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: RichText(
                        textAlign: TextAlign.left,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: widget.value.length > 11 ? 19 : 24,
                            fontWeight: FontWeight.w800,
                          ),
                          children: [
                            TextSpan(text: widget.value),
                            if (widget.unit != null)
                              TextSpan(
                                text: ' ${widget.unit}',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.supportingText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.supportingText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ],
                    if (widget.estimated) ...[
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark(context)
                              ? const Color(0xFF1D3934)
                              : const Color(0xFFD7F1E9),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'Estimated',
                          style: TextStyle(
                            color: isDark(context) ? _todayMint : _todayTeal,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.subtitleColor ?? colors.onSurfaceVariant,
                        fontSize: 14,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TodayWorkoutCard extends StatelessWidget {
  final String? title;
  final String? detail;
  final List<String> badges;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final int weeklyCount;
  final int weeklyGoal;
  final VoidCallback onChooseRoutine;
  final VoidCallback onScheduleWorkout;

  const TodayWorkoutCard({
    super.key,
    required this.title,
    required this.detail,
    required this.weeklyCount,
    required this.weeklyGoal,
    required this.onChooseRoutine,
    required this.onScheduleWorkout,
    this.badges = const [],
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final background = dark ? const Color(0xFF163B36) : _todayDarkGreen;
    final badgeColor = dark
        ? Colors.white.withValues(alpha: .1)
        : const Color(0xFF315D56);
    final completedCount = weeklyCount.clamp(0, weeklyGoal);
    final empty = title == null;

    Widget heroButton(
      String label,
      VoidCallback onPressed, {
      bool primary = false,
    }) => RoundActionButton(
      label: label,
      onPressed: onPressed,
      foregroundColor: primary ? const Color(0xFF10302C) : Colors.white,
      borderColor: primary ? null : Colors.white.withValues(alpha: .5),
      backgroundColor: primary
          ? _todayMint
          : Colors.white.withValues(alpha: .08),
      height: 48,
      width: double.infinity,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: background.withValues(alpha: dark ? .36 : .2),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TODAY'S WORKOUT",
            style: TextStyle(
              color: _todayMint,
              fontSize: 11,
              letterSpacing: .9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title ?? 'Nothing planned yet',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail ?? 'Choose a routine for today or schedule one for later.',
            style: const TextStyle(color: Color(0xFFCFDCD8), fontSize: 13),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final badge in badges)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (empty) ...[
            heroButton('Choose a routine', onChooseRoutine, primary: true),
            const SizedBox(height: 8),
            heroButton('Schedule a workout', onScheduleWorkout),
          ] else if (actionLabel != null && onAction != null) ...[
            heroButton(actionLabel!, onAction!, primary: true),
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: 8),
              heroButton(secondaryActionLabel!, onSecondaryAction!),
            ],
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'This week',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                '$weeklyCount of $weeklyGoal workouts',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var index = 0; index < weeklyGoal; index++) ...[
                if (index > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: index < completedCount
                          ? _todayMint
                          : const Color(0xFF3D6A62),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
