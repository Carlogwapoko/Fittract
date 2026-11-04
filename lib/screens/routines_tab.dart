import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../store/store.dart';
import '../widgets/shared_widgets.dart';
import 'exercise_library_screen.dart';
import 'workout_screen.dart';

int routineMinutes(Iterable exercises) {
  var seconds = 0;
  for (final raw in exercises) {
    if (raw is! Map) continue;
    final sets = (raw['s'] as num?)?.toInt() ?? 3;
    final amount = (raw['r'] as num?)?.toInt() ?? 10;
    final rest = (raw['rest'] as num?)?.toInt() ?? 60;
    final isTime = raw['unit'] == 'sec';
    seconds += sets * amount * (isTime ? 1 : 3);
    seconds += math.max(0, sets - 1) * rest;
    seconds += 60;
  }
  return seconds == 0 ? 0 : (seconds / 60).ceil();
}

class RoutinesTab extends StatefulWidget {
  const RoutinesTab({super.key});
  @override
  State<RoutinesTab> createState() => _RoutinesState();
}

class _RoutinesState extends State<RoutinesTab> {
  String q = '';
  String _exploreFilter = 'All';
  int seg = 0;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedPreviews = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> createRoutine(BuildContext context) async {
    final exercises = await goForResult<List<Map<String, dynamic>>>(
      context,
      const ExerciseLibraryScreen(title: 'Create a routine'),
    );
    if (exercises == null || exercises.isEmpty || !context.mounted) return;
    final cardio =
        exercises.where((exercise) => exercise['m'] == 'Cardio').length >
        exercises.length / 2;
    go(
      context,
      EditRoutine({
        'id': DateTime.now().millisecondsSinceEpoch,
        'name': '',
        'type': cardio ? 'Cardio' : 'Strength',
        'ex': exercises,
        'isNew': true,
      }),
    );
  }

  void _switchSegment(int value) {
    _searchController.clear();
    setState(() {
      seg = value;
      q = '';
    });
  }

  @override
  Widget build(BuildContext context) => live((c) {
    final routines = store.routines.whereType<Map>().toList();
    final myRoutines = routines
        .where(
          (routine) => (routine['name'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q.trim().toLowerCase()),
        )
        .toList();
    final explore = [
      ...exploreList(),
      {
        'name': 'Gentle mobility flow',
        'type': 'Mobility',
        'level': 'Beginner',
        'equipment': 'No equipment',
        'ex': [
          ex('Cat-cow stretch', 'Back', 2, 10, 30),
          ex('Hip flexor stretch', 'Legs', 2, 30, 30),
          ex('World’s greatest stretch', 'Full body', 2, 5, 30),
        ],
      },
    ];
    final exploreRoutines = explore
        .where(
          (routine) =>
              (_exploreFilter == 'All' || routine['type'] == _exploreFilter) &&
              (routine['name'] as String).toLowerCase().contains(
                q.trim().toLowerCase(),
              ),
        )
        .toList();
    final emptyMine = seg == 0 && routines.isEmpty && q.trim().isEmpty;

    return Stack(
      children: [
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kGapLg, kGapLg, kGapLg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    hdr(c, 'Build your momentum', 'Your routines'),
                    TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => q = value),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: seg == 0
                            ? 'Search your routines'
                            : 'Search all routines',
                      ),
                    ),
                    const SizedBox(height: kGapMd),
                    _RoutineSegments(selected: seg, onSelected: _switchSegment),
                  ],
                ),
              ),
              Expanded(
                child: seg == 0
                    ? (emptyMine
                          ? _emptyRoutineState(c)
                          : _myRoutineList(c, myRoutines, routines.length))
                    : _exploreListView(c, exploreRoutines),
              ),
            ],
          ),
        ),
        if (seg == 0 && routines.isNotEmpty)
          Positioned(
            right: 20,
            bottom: 12,
            child: FloatingActionButton.extended(
              heroTag: 'createRoutine',
              onPressed: () => createRoutine(c),
              focusColor: primaryOf(c).withValues(alpha: .2),
              backgroundColor: primaryOf(c),
              foregroundColor: isDark(c) ? kInk : Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Create routine'),
            ),
          ),
      ],
    );
  });

  Widget _emptyRoutineState(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(kGapXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              color: isDark(context)
                  ? const Color(0xFF214840)
                  : const Color(0xFF0A7F6F),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(14),
            child: SvgPicture.asset('assets/images/progress_rings.svg'),
          ),
          const SizedBox(height: kGapLg),
          Text(
            'No routines yet. Start with one that fits your week.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: kGapLg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => createRoutine(context),
              icon: const Icon(Icons.add),
              label: const Text('Create a routine'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: primaryOf(context),
                foregroundColor: isDark(context) ? kInk : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: kGapSm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _switchSegment(1),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: primaryOf(context),
                side: BorderSide(color: primaryOf(context)),
                overlayColor: primaryOf(context).withValues(alpha: .18),
              ),
              child: const Text('Try a starter routine'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _myRoutineList(
    BuildContext context,
    List<Map> routines,
    int totalCount,
  ) {
    if (routines.isEmpty) {
      return Center(
        child: Text(
          'No routines match.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(kGapLg, kGapSm, kGapLg, 100),
      children: [
        h3(
          'Made for your week',
          trailing: Text(
            '$totalCount routines',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final routine in routines) _myRoutineCard(context, routine),
      ],
    );
  }

  Widget _myRoutineCard(BuildContext context, Map routine) {
    final exs = routine['ex'] is List ? routine['ex'] as List : const [];
    final name = (routine['name'] ?? 'Untitled routine').toString();
    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: kGapSm),
                    Text(
                      '${routine['type'] ?? 'Strength'} · ${exs.length} exercises · ~${routineMinutes(exs)} min',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: kGapSm),
              _outlinedPillButton(
                context,
                label: 'Edit',
                icon: Icons.edit_outlined,
                onPressed: () => go(context, EditRoutine(routine)),
              ),
              PopupMenuButton<String>(
                tooltip: 'Routine options',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'start') {
                    go(context, WorkoutScreen(routine));
                  } else {
                    _deleteRoutine(context, routine);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'start', child: Text('Start workout')),
                  PopupMenuItem(value: 'delete', child: Text('Delete routine')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRoutine(BuildContext context, Map routine) async {
    if (!await confirm(context, 'Delete routine?', 'Delete') ||
        !context.mounted) {
      return;
    }
    store.routines.removeWhere((value) => value['id'] == routine['id']);
    store.sch.removeWhere((schedule) => schedule['r'] == routine['id']);
    final active = store.d['activeW'];
    if (active is Map &&
        (active['rid'] == routine['id'] || active['rid'] == routine['name'])) {
      store.d.remove('activeW');
    }
    store.save();
  }

  Widget _exploreListView(
    BuildContext context,
    List<Map<String, dynamic>> routines,
  ) => Column(
    children: [
      SizedBox(
        height: 58,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: kGapLg, vertical: 6),
          scrollDirection: Axis.horizontal,
          children: [
            for (final filter in const [
              'All',
              'Strength',
              'Cardio',
              'Mobility',
            ])
              Padding(
                padding: const EdgeInsets.only(right: kGapSm),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: filter == _exploreFilter,
                  showCheckmark: false,
                  selectedColor: primaryOf(context),
                  focusNode: null,
                  labelStyle: TextStyle(
                    color: filter == _exploreFilter
                        ? (isDark(context) ? kInk : Colors.white)
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => setState(() => _exploreFilter = filter),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: routines.isEmpty
            ? Center(
                child: Text(
                  'No routines match.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(kGapLg, 0, kGapLg, kGapXl),
                children: [
                  h3(
                    'Popular this week',
                    trailing: Text(
                      '${routines.length} routines',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final routine in routines)
                    _exploreRoutineCard(context, routine),
                ],
              ),
      ),
    ],
  );

  Widget _exploreRoutineCard(
    BuildContext context,
    Map<String, dynamic> routine,
  ) {
    final name = routine['name'] as String;
    final exs = routine['ex'] as List;
    final expanded = _expandedPreviews.contains(name);
    final added = store.routines.any((value) => value['name'] == name);
    final level = (routine['level'] ?? 'Beginner').toString();
    final equipment = (routine['equipment'] ?? 'No equipment').toString();
    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  overlayColor: WidgetStatePropertyAll(
                    primaryOf(context).withValues(alpha: .18),
                  ),
                  onTap: () => setState(() {
                    if (expanded) {
                      _expandedPreviews.remove(name);
                    } else {
                      _expandedPreviews.add(name);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: kGapSm),
                        tag(routine['type'] as String),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: kGapSm),
              _outlinedPillButton(
                context,
                label: added ? 'Added ✓' : '+ Add',
                onPressed: added
                    ? null
                    : () => _addExploreRoutine(context, routine),
                filled: added,
              ),
            ],
          ),
          const SizedBox(height: kGapSm),
          Text(
            '${exs.length} exercises · ~${routineMinutes(exs)} min · $level · $equipment',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: kGapSm),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            for (final exercise in exs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${exercise['n']} · ${exercise['m']}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${exercise['s']} × ${exercise['r']} ${exercise['unit'] == 'sec' ? 'sec' : 'reps'}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _addExploreRoutine(BuildContext context, Map<String, dynamic> routine) {
    final name = routine['name'] as String;
    if (store.routines.any((value) => value['name'] == name)) return;
    store.routines.add({
      ...routine,
      'id': DateTime.now().millisecondsSinceEpoch,
    });
    store.save();
    if (!mounted || !context.mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Added $name to My routines'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => _switchSegment(0),
          ),
        ),
      );
  }
}

class _RoutineSegments extends StatelessWidget {
  const _RoutineSegments({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < 2; index++) ...[
        if (index > 0) const SizedBox(width: kGapSm),
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: () => onSelected(index),
              style: OutlinedButton.styleFrom(
                backgroundColor: selected == index
                    ? primaryOf(context)
                    : Theme.of(context).colorScheme.surface,
                foregroundColor: selected == index
                    ? (isDark(context) ? kInk : Colors.white)
                    : Theme.of(context).colorScheme.onSurface,
                side: BorderSide(
                  color: selected == index
                      ? primaryOf(context)
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
                overlayColor: primaryOf(context).withValues(alpha: .18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                index == 0 ? 'My routines' : 'Explore',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

Widget _outlinedPillButton(
  BuildContext context, {
  required String label,
  required VoidCallback? onPressed,
  IconData? icon,
  bool filled = false,
}) => OutlinedButton(
  onPressed: onPressed,
  style: OutlinedButton.styleFrom(
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    backgroundColor: filled ? tintOf(context) : null,
    foregroundColor: primaryOf(context),
    side: BorderSide(color: primaryOf(context)),
    shape: const StadiumBorder(),
    overlayColor: primaryOf(context).withValues(alpha: .18),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  ),
);

class EditRoutine extends StatefulWidget {
  final Map src;
  const EditRoutine(this.src, {super.key});
  @override
  State<EditRoutine> createState() => _EditState();
}

class _EditState extends State<EditRoutine> {
  late final Map<String, dynamic> r = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(widget.src)),
  );
  late final bool _isNew = r['isNew'] == true;
  late final TextEditingController _nameController = TextEditingController(
    text: _isNew ? '' : (r['name'] ?? '').toString(),
  );
  late final List<Key> _rowKeys;
  late final String _initialSnapshot;
  final Set<Key> _expanded = {};
  bool _allowPop = false;

  bool get _hasUnsavedChanges => _isNew || jsonEncode(r) != _initialSnapshot;
  List get _exercises => r['ex'] is List ? r['ex'] as List : <dynamic>[];

  @override
  void initState() {
    super.initState();
    if (_isNew) r['name'] = '';
    r['ex'] ??= <dynamic>[];
    _rowKeys = [for (final _ in _exercises) UniqueKey()];
    _initialSnapshot = jsonEncode(r);
    _nameController.addListener(_nameChanged);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_nameChanged)
      ..dispose();
    super.dispose();
  }

  void _nameChanged() {
    r['name'] = _nameController.text;
    if (mounted) setState(() {});
  }

  Future<void> _requestPop() async {
    if (!_hasUnsavedChanges) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: primaryOf(dialogContext),
              foregroundColor: isDark(dialogContext) ? kInk : Colors.white,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final exs = _exercises;
    final hasName = _nameController.text.trim().isNotEmpty;
    final canSave = hasName && exs.isNotEmpty;
    final category = (r['type'] ?? 'Strength').toString();
    return PopScope<void>(
      canPop: _allowPop || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestPop();
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(kGapLg, kGapSm, kGapLg, 112),
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      tooltip: 'Back',
                      focusColor: primaryOf(context).withValues(alpha: .18),
                      onPressed: _requestPop,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(width: kGapSm),
                  Text(
                    _isNew ? 'NEW ROUTINE' : 'MAKE IT YOUR OWN',
                    style: TextStyle(
                      color: primaryOf(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 52, bottom: kGapLg),
                child: Text(
                  _isNew ? 'Name your routine' : 'Edit routine',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Push day',
                  border: OutlineInputBorder(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: kGapSm,
                  top: kGapXs,
                  bottom: kGapMd,
                ),
                child: Text(
                  'Pick something you will recognise in your week',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              Row(
                children: [
                  PopupMenuButton<String>(
                    tooltip: 'Choose category',
                    onSelected: (value) => setState(() => r['type'] = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'Strength', child: Text('Strength')),
                      PopupMenuItem(value: 'Cardio', child: Text('Cardio')),
                      PopupMenuItem(value: 'Mobility', child: Text('Mobility')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: tintOf(context),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$category ▾',
                            style: TextStyle(
                              color: primaryOf(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: kGapSm),
                  Expanded(
                    child: Text(
                      '${exs.length} exercises · ~${routineMinutes(exs)} min',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              h3('Your exercises'),
              if (exs.isEmpty)
                card(
                  child: Text(
                    'No exercises yet. Browse exercises to build your routine.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (var index = 0; index < exs.length; index++)
                _exerciseCard(index, exs[index] as Map),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _browseExercises,
                  icon: const Icon(Icons.add),
                  label: const Text('Browse exercises'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: tintOf(context),
                    foregroundColor: primaryOf(context),
                    side: BorderSide(
                      color: primaryOf(context).withValues(alpha: .4),
                    ),
                    overlayColor: primaryOf(context).withValues(alpha: .18),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0),
                Theme.of(context).scaffoldBackgroundColor,
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                kGapLg,
                kGapLg,
                kGapLg,
                kGapMd,
              ),
              child: FilledButton(
                onPressed: canSave ? _save : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: primaryOf(context),
                  foregroundColor: isDark(context) ? kInk : Colors.white,
                  disabledBackgroundColor: isDark(context)
                      ? const Color(0xFF293735)
                      : const Color(0xFFD8E0DF),
                  disabledForegroundColor: isDark(context)
                      ? const Color(0xFFB7C3C0)
                      : const Color(0xFF53615E),
                ),
                child: const Text('Save routine'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _exerciseCard(int index, Map exercise) {
    final key = _rowKeys[index];
    final expanded = _expanded.contains(key);
    final name = (exercise['n'] ?? 'Exercise').toString();
    final group = (exercise['m'] ?? 'Other').toString();
    final sets = (exercise['s'] as num?)?.toInt() ?? 3;
    final amount = (exercise['r'] as num?)?.toInt() ?? 10;
    final rest = (exercise['rest'] as num?)?.toInt() ?? 60;
    final unit = exercise['unit'] == 'sec' ? 'sec' : 'reps';

    return KeyedSubtree(
      key: key,
      child: card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  children: [
                    SizedBox(
                      width: 36,
                      height: 34,
                      child: IconButton(
                        tooltip: 'Move $name up',
                        padding: EdgeInsets.zero,
                        onPressed: index == 0
                            ? null
                            : () => _moveExercise(index, -1),
                        focusColor: primaryOf(context).withValues(alpha: .18),
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 34,
                      child: IconButton(
                        tooltip: 'Move $name down',
                        padding: EdgeInsets.zero,
                        onPressed: index == _exercises.length - 1
                            ? null
                            : () => _moveExercise(index, 1),
                        focusColor: primaryOf(context).withValues(alpha: .18),
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: kGapXs),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    focusColor: primaryOf(context).withValues(alpha: .18),
                    onTap: () => setState(() {
                      if (expanded) {
                        _expanded.remove(key);
                      } else {
                        _expanded.add(key);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: kGapSm),
                      child: Row(
                        children: [
                          Icon(
                            exerciseIconFor(name, group),
                            color: primaryOf(context),
                            size: 19,
                          ),
                          const SizedBox(width: kGapSm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: kGapXs),
                                Text(
                                  '$group · $sets × $amount $unit · $rest sec',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More options for $name',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) {
                    if (value == 'remove') _removeExercise(index);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
                IconButton(
                  tooltip: expanded ? 'Collapse $name' : 'Edit $name',
                  onPressed: () => setState(() {
                    if (expanded) {
                      _expanded.remove(key);
                    } else {
                      _expanded.add(key);
                    }
                  }),
                  focusColor: primaryOf(context).withValues(alpha: .18),
                  icon: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: primaryOf(context),
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: _numberStepper(
                      label: 'Sets',
                      value: sets,
                      min: 1,
                      max: kSetsMax,
                      onChanged: (value) =>
                          setState(() => exercise['s'] = value),
                    ),
                  ),
                  const SizedBox(width: kGapMd),
                  Expanded(
                    child: _numberStepper(
                      label: unit == 'sec' ? 'Duration (sec)' : 'Reps',
                      value: amount,
                      min: unit == 'sec' ? 5 : 1,
                      max: 300,
                      step: unit == 'sec' ? 5 : 1,
                      onChanged: (value) =>
                          setState(() => exercise['r'] = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: kGapMd),
              Text(
                'Rest (sec)',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: kGapSm),
              Wrap(
                spacing: kGapSm,
                children: [
                  for (final value in const [30, 45, 60, 90])
                    ChoiceChip(
                      label: Text('$value'),
                      selected: rest == value,
                      showCheckmark: false,
                      selectedColor: primaryOf(context),
                      labelStyle: TextStyle(
                        color: rest == value
                            ? (isDark(context) ? kInk : Colors.white)
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      onSelected: (_) =>
                          setState(() => exercise['rest'] = value),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numberStepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    int step = 1,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: kGapXs),
      Container(
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: 'Decrease $label',
                onPressed: value > min
                    ? () => onChanged(math.max(min, value - step))
                    : null,
                focusColor: primaryOf(context).withValues(alpha: .18),
                icon: const Icon(Icons.remove, size: 18),
              ),
            ),
            Expanded(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: 'Increase $label',
                onPressed: value < max
                    ? () => onChanged(math.min(max, value + step))
                    : null,
                focusColor: primaryOf(context).withValues(alpha: .18),
                icon: const Icon(Icons.add, size: 18),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _browseExercises() async {
    final picked = await goForResult<List<Map<String, dynamic>>>(
      context,
      const ExerciseLibraryScreen(title: 'Add exercises'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _exercises.addAll(picked);
      _rowKeys.addAll([for (final _ in picked) UniqueKey()]);
    });
  }

  void _moveExercise(int index, int delta) {
    setState(() {
      final next = index + delta;
      final exercise = _exercises.removeAt(index);
      final key = _rowKeys.removeAt(index);
      _exercises.insert(next, exercise);
      _rowKeys.insert(next, key);
    });
  }

  void _removeExercise(int index) {
    final removed = _exercises.removeAt(index);
    final key = _rowKeys.removeAt(index);
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${removed['n']}'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (!mounted) return;
              setState(() {
                _exercises.insert(index.clamp(0, _exercises.length), removed);
                _rowKeys.insert(index.clamp(0, _rowKeys.length), key);
              });
            },
          ),
        ),
      );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _exercises.isEmpty) return;
    for (final exercise in _exercises) {
      final err = validateExerciseConfig(
        exercise['s'] as num? ?? 0,
        exercise['r'] as num? ?? 0,
        exercise['rest'] as num? ?? 0,
      );
      if (err != null) {
        snack(context, "${exercise['n']}: $err");
        return;
      }
    }
    r['name'] = name;
    r.remove('isNew');
    final index = store.routines.indexWhere((value) => value['id'] == r['id']);
    if (index >= 0) {
      store.routines[index] = r;
    } else {
      store.routines.add(r);
    }
    store.save();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }
}
