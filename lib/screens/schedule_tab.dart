import 'package:flutter/material.dart';

import '../store/store.dart';
import '../widgets/shared_widgets.dart';
import 'workout_screen.dart';

class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key});
  @override
  State<ScheduleTab> createState() => _ScheduleState();
}

class _ScheduleState extends State<ScheduleTab> {
  DateTime cm = DateTime(DateTime.now().year, DateTime.now().month);
  String sel = today();

  static const mn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const wd = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  String t12(String t) {
    final p = t.split(':');
    final h = int.parse(p[0]);
    return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> add(BuildContext c) async {
    if (store.routines.isEmpty) {
      snack(c, 'Create a routine before scheduling a workout.');
      return;
    }
    final workout = await showModalBottomSheet<Map<String, dynamic>>(
      context: c,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ScheduleWorkoutSheet(initialDate: sel),
    );
    if (workout == null || !mounted) return;
    store.sch.add({
      'id': DateTime.now().millisecondsSinceEpoch,
      'r': workout['r'],
      'd': workout['d'],
      't': workout['t'],
    });
    store.save();
    final d = DateTime.parse(workout['d'] as String);
    setState(() {
      sel = workout['d'] as String;
      cm = DateTime(d.year, d.month);
    });
  }

  // One calendar cell: compact, teal selected square, dot under days with workouts.
  Widget day(DateTime dt) {
    final k = isoOf(dt);
    final inMonth = dt.month == cm.month;
    final selected = k == sel, isToday = k == today();
    final has = store.sch.any((e) => e['d'] == k);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          sel = k;
          if (!inMonth) cm = DateTime(dt.year, dt.month);
        }),
        child: SizedBox(
          height: 42,
          child: Center(
            child: Container(
              width: 34,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? primaryOf(context) : null,
                borderRadius: BorderRadius.circular(10),
                border: isToday && !selected
                    ? Border.all(color: primaryOf(context))
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${dt.day}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected
                          ? Colors.white
                          : (inMonth
                                ? Theme.of(context).colorScheme.onSurface
                                : kMut.withValues(alpha: .5)),
                    ),
                  ),
                  has
                      ? Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            color: selected ? Colors.white : primaryOf(context),
                            shape: BoxShape.circle,
                          ),
                        )
                      : const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget entry(BuildContext c, Map s) {
    final r = store.routine(s['r']);
    final dt = DateTime.parse(s['d']);
    final isToday = s['d'] == today();
    final mins = r == null ? null : (r['ex'] as List).length * 7;
    return card(
      color: isToday ? tintOf(c) : null,
      pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(
                  isToday ? 'TODAY' : wd[dt.weekday - 1],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isToday ? primaryOf(c) : kMut,
                  ),
                ),
                Text(
                  '${dt.day}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: kGapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r?['name'] ?? '(deleted routine)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                  Text(
                    r == null
                        ? '${t12(s['t'])} · routine deleted'
                        : '${t12(s['t'])} · $mins min${store.on('wr') ? ' · Today reminder on' : ''}',
                    style: muted,
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            tooltip: 'Workout options',
            onSelected: (v) {
              if (v == 'start' && r != null) go(c, WorkoutScreen(r));
              if (v == 'delete') {
                store.sch.remove(s);
                store.save();
              }
            },
            // No Start action when the routine is gone: it would silently
            // do nothing. Delete (and re-schedule later) is the way out.
            itemBuilder: (_) => [
              if (r != null)
                const PopupMenuItem(
                  value: 'start',
                  child: Text('Start workout'),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: kRed)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => live((c) {
    final first = DateTime(cm.year, cm.month, 1);
    final lead = (first.weekday + 6) % 7; // Monday-first
    final days = DateTime(cm.year, cm.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    final endOfWeek = isoOf(DateTime.now().add(const Duration(days: 6)));
    final items =
        store.sch
            .where(
              (s) =>
                  s['d'] == sel ||
                  (sel == today() &&
                      (s['d'] as String).compareTo(today()) >= 0 &&
                      (s['d'] as String).compareTo(endOfWeek) <= 0),
            )
            .toList()
          ..sort(
            (a, b) => ('${a['d']}${a['t']}').compareTo('${b['d']}${b['t']}'),
          );

    return tabBody([
      hdr(
        c,
        'Your workout schedule',
        'Make time for you.',
        act: [
          IconButton(
            tooltip: 'Jump to today',
            onPressed: () => setState(() {
              cm = DateTime(DateTime.now().year, DateTime.now().month);
              sel = today();
            }),
            icon: const Icon(Icons.calendar_today_outlined),
          ),
        ],
      ),
      card(
        pad: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () =>
                      setState(() => cm = DateTime(cm.year, cm.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${mn[cm.month - 1]} ${cm.year}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () =>
                      setState(() => cm = DateTime(cm.year, cm.month + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final x in 'MTWTFSS'.split(''))
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(x, style: muted),
                      ),
                    ),
                  ),
              ],
            ),
            for (int r = 0; r < rows; r++)
              Row(
                children: [
                  for (int col = 0; col < 7; col++)
                    day(DateTime(cm.year, cm.month, 1 - lead + r * 7 + col)),
                ],
              ),
          ],
        ),
      ),
      h3(
        'Coming up',
        trailing: Text(
          sel == today() ? 'This week' : sel,
          style: TextStyle(
            color: primaryOf(c),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (items.isEmpty)
        card(child: const Text('Nothing planned for this day.', style: muted)),
      for (final s in items) entry(c, s),
      card(
        pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.notifications_none, color: primaryOf(c)),
            const SizedBox(width: kGapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Workout reminders (in-app)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Shows a card on Today. No system notifications yet.',
                    style: muted,
                  ),
                ],
              ),
            ),
            Switch(
              value: store.on('wr'),
              activeThumbColor: primaryOf(c),
              onChanged: (_) => store.toggle('wr'),
            ),
          ],
        ),
      ),
      btn('+  Schedule a workout', () => add(c)),
    ]);
  });
}

class _ScheduleWorkoutSheet extends StatefulWidget {
  final String initialDate;

  const _ScheduleWorkoutSheet({required this.initialDate});

  @override
  State<_ScheduleWorkoutSheet> createState() => _ScheduleWorkoutSheetState();
}

class _ScheduleWorkoutSheetState extends State<_ScheduleWorkoutSheet> {
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  dynamic _routineId;

  @override
  void initState() {
    super.initState();
    _date = DateTime.tryParse(widget.initialDate) ?? DateTime.now();
    _routineId = store.routines.first['id'];
  }

  @override
  Widget build(BuildContext context) {
    final routine = store.routine(_routineId);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Plan your next workout',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose a routine, date and time.',
                style: muted,
              ),
              const SizedBox(height: kGapLg),
              DropdownButtonFormField<dynamic>(
                initialValue: _routineId,
                decoration: const InputDecoration(
                  labelText: 'Routine',
                  prefixIcon: Icon(Icons.fitness_center),
                ),
                items: [
                  for (final item in store.routines)
                    DropdownMenuItem<dynamic>(
                      value: item['id'],
                      child: Text(item['name'] as String),
                    ),
                ],
                onChanged: (value) => setState(() => _routineId = value),
              ),
              const SizedBox(height: kGapMd),
              Row(
                children: [
                  Expanded(
                    child: _pickerTile(
                      icon: Icons.calendar_month_outlined,
                      label: 'Date',
                      value: MaterialLocalizations.of(context)
                          .formatMediumDate(_date),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: kGapMd),
                  Expanded(
                    child: _pickerTile(
                      icon: Icons.schedule_outlined,
                      label: 'Time',
                      value: _time.format(context),
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              if (routine != null) ...[
                const SizedBox(height: kGapLg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(kGapLg),
                  decoration: BoxDecoration(
                    color: tintOf(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, color: primaryOf(context)),
                      const SizedBox(width: kGapMd),
                      Expanded(
                        child: Text(
                          '${routine['name']} · ${(routine['ex'] as List).length} exercises',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: kGapLg),
              btn('Add to schedule', _save),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) =>
      Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: primaryOf(context)),
                    const SizedBox(width: kGapSm),
                    Text(label, style: muted),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(todayDate) ? todayDate : _date,
      firstDate: todayDate,
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _time);
    if (time != null && mounted) setState(() => _time = time);
  }

  void _save() {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    if (_date.isBefore(todayDate)) {
      snack(context, 'Choose today or a future date for your workout.');
      return;
    }
    Navigator.pop(context, {
      'r': _routineId,
      'd': isoOf(_date),
      't':
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
    });
  }
}
