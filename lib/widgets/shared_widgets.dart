import 'package:flutter/material.dart';

import '../store/store.dart';

const kGapXs = 4.0;
const kGapSm = 8.0;
const kGapMd = 12.0;
const kGapLg = 16.0;
const kGapXl = 20.0;

Widget live(Widget Function(BuildContext) f) =>
    ListenableBuilder(listenable: store, builder: (c, _) => f(c));

Widget card({
  required Widget child,
  Color? color,
  VoidCallback? onTap,
  EdgeInsets? pad,
}) => Padding(
  padding: const EdgeInsets.only(bottom: kGapMd),
  child: Builder(
    builder: (context) => Material(
      color: color ?? Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: color == null
            ? BorderSide(color: Theme.of(context).colorScheme.outlineVariant)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: pad ?? const EdgeInsets.all(kGapLg),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
  ),
);

/// Clamps [p] into 0..1 for progress widgets. Unlike a bare `.clamp`, this
/// never propagates NaN (0/0 from a zero-denominator goal) or infinities
/// (n/0) into [LinearProgressIndicator]/[CircularProgressIndicator], which
/// would otherwise throw or paint garbage.
double progressOf(double p) {
  if (p.isNaN) return 0.0;
  if (p == double.infinity) return 1.0;
  if (p == double.negativeInfinity) return 0.0;
  return p.clamp(0.0, 1.0);
}

/// Shared exercise icon selection for the library, routine rows, and the live
/// workout card, so the same movement always gets the same icon everywhere.
/// Selection order: movement identity (only where Material has a genuinely
/// matching icon), bodyweight figure (no equipment implied), equipment cue,
/// muscle-group category for custom/legacy exercises, then the neutral
/// dumbbell default. Category icons stay honest: nothing here pretends to
/// depict an exercise Material cannot depict.
IconData exerciseIconFor(Object? name, [Object? group]) {
  final n = (name ?? '').toString().trim().toLowerCase();
  bool has(List<String> cues) => cues.any(n.contains);

  // Movements Material depicts directly.
  if (has(['run', 'sprint', 'jog'])) return Icons.directions_run;
  if (has(['cycl', 'bike'])) return Icons.directions_bike;
  if (has(['swim'])) return Icons.pool;
  if (has(['yoga', 'pilates', 'plank'])) return Icons.self_improvement;

  // Bodyweight work: a plain figure, no equipment implied.
  if (has([
    'bodyweight',
    'push-up',
    'pushup',
    'lunge',
    'bridge',
    'jack',
    'knee',
    'burpee',
    'climber',
    'twist',
    'crunch',
    'bug',
    'jump',
    'sit-up',
  ])) {
    return Icons.accessibility_new;
  }

  // Loaded / equipment work.
  if (has([
    'barbell',
    'dumbbell',
    'kettlebell',
    'cable',
    'machine',
    'bench',
    'deadlift',
    'curl',
    'press',
    'row',
    'pull',
    'raise',
    'pushdown',
    'goblet',
    'squat',
    'lift',
    'fly',
  ])) {
    return Icons.fitness_center;
  }

  // Muscle-group category for custom or legacy exercises.
  return switch ((group ?? '').toString().trim().toLowerCase()) {
    'cardio' => Icons.bolt,
    'core' => Icons.self_improvement,
    _ => Icons.fitness_center,
  };
}

Widget bar(double p, {bool dark = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Builder(
    builder: (context) => ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: LinearProgressIndicator(
        value: progressOf(p),
        minHeight: 6,
        color: primaryOf(context),
        backgroundColor: dark
            ? Colors.white24
            : (isDark(context) ? kLineDark : kLn),
      ),
    ),
  ),
);

Widget btn(
  String label,
  VoidCallback f, {
  bool tonal = false,
  bool danger = false,
  IconData? icon,
}) => _AnimatedButton(
  label: label,
  onPressed: f,
  tonal: tonal,
  danger: danger,
  icon: icon,
);

class _AnimatedButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool tonal;
  final bool danger;
  final IconData? icon;

  const _AnimatedButton({
    required this.label,
    required this.onPressed,
    required this.tonal,
    required this.danger,
    required this.icon,
  });

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final primary = primaryOf(context);
    final foreground = widget.danger
        ? kRed
        : (widget.tonal ? primary : (dark ? kInk : Colors.white));
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: widget.danger
          ? const BorderSide(color: kRed, width: 1.2)
          : BorderSide.none,
    );

    return SizedBox(
      width: double.infinity,
      child: AnimatedScale(
        scale: _pressed ? .97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: () {
              setState(() => _pressed = false);
              widget.onPressed();
            },
            child: Ink(
              decoration: ShapeDecoration(
                color: widget.danger
                    ? Colors.transparent
                    : (widget.tonal ? tintOf(context) : primary),
                shape: shape,
              ),
              child: SizedBox(
                height: 50,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: widget.icon == null
                        ? Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(widget.icon, size: 18, color: foreground),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  widget.label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
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
  }
}

Widget tag(String s) => Builder(
  builder: (context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: tintOf(context),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      s,
      style: TextStyle(
        color: primaryOf(context),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
);

Widget h3(String s, {Widget? trailing}) => Padding(
  padding: const EdgeInsets.only(top: kGapXl, bottom: kGapSm),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Flexible(
        child: Text(
          s,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      ?trailing,
    ],
  ),
);

Widget hdr(
  BuildContext c,
  String k,
  String t, {
  bool back = false,
  List<Widget> act = const [],
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (back || act.isNotEmpty)
      Row(
        children: [
          if (back)
            CircleAvatar(
              backgroundColor: Theme.of(c).colorScheme.surface,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => Navigator.pop(c),
              ),
            ),
          const Spacer(),
          ...act,
        ],
      ),
    const SizedBox(height: kGapSm),
    Text(
      k.toUpperCase(),
      style: TextStyle(
        color: primaryOf(c),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .8,
      ),
    ),
    Text(
      t,
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.1,
        color: Theme.of(c).colorScheme.onSurface,
      ),
    ),
    const SizedBox(height: kGapLg),
  ],
);

Widget screen(List<Widget> kids) => Scaffold(
  body: SafeArea(
    child: ListView(padding: const EdgeInsets.all(kGapLg), children: kids),
  ),
);
Widget tabBody(List<Widget> kids) => SafeArea(
  child: ListView(padding: const EdgeInsets.all(kGapLg), children: kids),
);
PageRoute<T> _animatedRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, _, _) => page,
  transitionDuration: const Duration(milliseconds: 300),
  reverseTransitionDuration: const Duration(milliseconds: 240),
  transitionsBuilder: (_, animation, _, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.045, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);

void go(BuildContext c, Widget w) {
  Navigator.push(c, _animatedRoute<void>(w));
}

Future<T?> goForResult<T>(BuildContext c, Widget w) =>
    Navigator.push<T>(c, _animatedRoute<T>(w));
void snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<bool> confirm(BuildContext c, String title, String ok) async =>
    await showDialog<bool>(
      context: c,
      builder: (dc) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dc, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dc, true),
            style: FilledButton.styleFrom(
              backgroundColor: primaryOf(dc),
              foregroundColor: Theme.of(dc).colorScheme.onPrimary,
            ),
            child: Text(ok),
          ),
        ],
      ),
    ) ??
    false;

class F {
  final String k, label, v, type;
  final List<String> opts;
  F(this.k, this.label, this.v, {this.type = 'text', this.opts = const []});
}

Future<Map<String, String>?> form(
  BuildContext c,
  String title,
  List<F> fs, {
  String ok = 'Save',
}) => showDialog<Map<String, String>>(
  context: c,
  builder: (dc) => _FormDialog(title: title, fs: fs, ok: ok),
);

/// Dialog body that owns its text controllers: they are created in
/// [initState] and disposed in [dispose], i.e. when the dialog unmounts after
/// its exit animation. Disposing eagerly when the route future completes (the
/// previous behavior) hit rebuilds of still-animating [TextField]s with dead
/// controllers.
class _FormDialog extends StatefulWidget {
  const _FormDialog({required this.title, required this.fs, this.ok = 'Save'});
  final String title;
  final List<F> fs;
  final String ok;

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  late final Map<String, TextEditingController> ctl;

  @override
  void initState() {
    super.initState();
    ctl = {for (final f in widget.fs) f.k: TextEditingController(text: f.v)};
  }

  @override
  void dispose() {
    for (final controller in ctl.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget buildField(F f) => f.type == 'choice'
      ? StatefulBuilder(
          builder: (ctx, ss) => DropdownButtonFormField<String>(
            initialValue: ctl[f.k]!.text,
            decoration: InputDecoration(labelText: f.label),
            items: [
              for (final o in f.opts)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) {
              if (v != null) ss(() => ctl[f.k]!.text = v);
            },
          ),
        )
      : TextField(
          controller: ctl[f.k],
          readOnly: f.type == 'date' || f.type == 'time',
          obscureText: f.type == 'pass',
          keyboardType: f.type == 'number'
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          decoration: InputDecoration(labelText: f.label),
          onTap: () async {
            if (f.type == 'date') {
              final p = await showDatePicker(
                context: context,
                initialDate:
                    DateTime.tryParse(ctl[f.k]!.text) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (p == null || !mounted) return;
              ctl[f.k]!.text = isoOf(p);
            } else if (f.type == 'time') {
              final parts = ctl[f.k]!.text.split(':');
              final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
              final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
              final p = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: hour ?? 18, minute: minute ?? 0),
              );
              if (p == null || !mounted) return;
              ctl[f.k]!.text =
                  '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
            }
          },
        );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.fs.length; i++) ...[
            if (i > 0) const SizedBox(height: kGapMd),
            buildField(widget.fs[i]),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          for (final e in ctl.entries) e.key: e.value.text,
        }),
        style: FilledButton.styleFrom(
          backgroundColor: primaryOf(context),
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
        child: Text(widget.ok),
      ),
    ],
  );
}

double num_(String? s) => double.tryParse(s ?? '') ?? 0;

Future<String?> showTodayReminders(BuildContext c) =>
    showModalBottomSheet<String>(
      context: c,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(c).colorScheme.surface,
      builder: (_) => const _TodayRemindersSheet(),
    );

class _TodayRemindersSheet extends StatelessWidget {
  const _TodayRemindersSheet();

  @override
  Widget build(BuildContext context) => live((c) {
    final waterGoal = store.waterGoalMl;
    final remainingSteps = (store.stepGoal - store.steps).clamp(
      0,
      store.stepGoal,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGapLg, kGapSm, kGapLg, kGapMd),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(c).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: kGapLg),
            const Text(
              "Today's reminders",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: kGapXs),
            const Text(
              'In-app only. No system notifications are sent.',
              style: muted,
            ),
            const SizedBox(height: kGapLg),
            _ReminderAction(
              icon: Icons.water_drop_outlined,
              title: 'Stay hydrated',
              subtitle:
                  '${(store.water() / 1000).toStringAsFixed(1)} of ${(waterGoal / 1000).toStringAsFixed(1)} L so far',
              buttonLabel: '＋ 250 ml',
              onPressed: () => Navigator.pop(c, 'water'),
            ),
            const SizedBox(height: kGapSm),
            _ReminderAction(
              icon: Icons.directions_walk_outlined,
              title: 'Keep moving',
              subtitle:
                  '${store.withThousands(remainingSteps)} steps to your goal',
              buttonLabel: 'Log activity',
              onPressed: () => Navigator.pop(c, 'activity'),
            ),
            const SizedBox(height: kGapLg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(c),
                style: FilledButton.styleFrom(
                  backgroundColor: primaryOf(c),
                  foregroundColor: Theme.of(c).colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  });
}

class _ReminderAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _ReminderAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(kGapMd),
    decoration: BoxDecoration(
      color: tintOf(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(icon, color: primaryOf(context), size: 22),
        const SizedBox(width: kGapMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: muted),
            ],
          ),
        ),
        const SizedBox(width: kGapSm),
        FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: primaryOf(context),
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            minimumSize: const Size(88, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(buttonLabel),
        ),
      ],
    ),
  );
}
