import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../store/store.dart';
import '../widgets/shared_widgets.dart';

const _library = <Map<String, dynamic>>[
  {
    'n': 'Push-ups',
    'm': 'Chest',
    'lvl': 'Beginner',
    's': 3,
    'r': 12,
    'rest': 45,
  },
  {
    'n': 'Dumbbell bench press',
    'm': 'Chest',
    'lvl': 'Intermediate',
    's': 3,
    'r': 10,
    'rest': 60,
  },
  {
    'n': 'Barbell bench press',
    'm': 'Chest',
    'lvl': 'Intermediate',
    's': 4,
    'r': 8,
    'rest': 90,
  },
  {
    'n': 'Dumbbell fly',
    'm': 'Chest',
    'lvl': 'Intermediate',
    's': 3,
    'r': 12,
    'rest': 60,
  },
  {
    'n': 'Lat pulldown',
    'm': 'Back',
    'lvl': 'Beginner',
    's': 3,
    'r': 12,
    'rest': 60,
  },
  {
    'n': 'Seated cable row',
    'm': 'Back',
    'lvl': 'Beginner',
    's': 3,
    'r': 12,
    'rest': 60,
  },
  {
    'n': 'Bent-over row',
    'm': 'Back',
    'lvl': 'Intermediate',
    's': 4,
    'r': 10,
    'rest': 75,
  },
  {'n': 'Pull-ups', 'm': 'Back', 'lvl': 'Advanced', 's': 4, 'r': 8, 'rest': 90},
  {
    'n': 'Bodyweight squat',
    'm': 'Legs',
    'lvl': 'Beginner',
    's': 3,
    'r': 15,
    'rest': 45,
  },
  {
    'n': 'Glute bridge',
    'm': 'Legs',
    'lvl': 'Beginner',
    's': 3,
    'r': 15,
    'rest': 45,
  },
  {'n': 'Lunges', 'm': 'Legs', 'lvl': 'Beginner', 's': 3, 'r': 12, 'rest': 60},
  {
    'n': 'Goblet squat',
    'm': 'Legs',
    'lvl': 'Intermediate',
    's': 3,
    'r': 12,
    'rest': 60,
  },
  {
    'n': 'Back squat',
    'm': 'Legs',
    'lvl': 'Intermediate',
    's': 4,
    'r': 8,
    'rest': 90,
  },
  {
    'n': 'Romanian deadlift',
    'm': 'Legs',
    'lvl': 'Intermediate',
    's': 3,
    'r': 10,
    'rest': 90,
  },
  {
    'n': 'Lateral raise',
    'm': 'Shoulders',
    'lvl': 'Beginner',
    's': 3,
    'r': 15,
    'rest': 45,
  },
  {
    'n': 'Face pull',
    'm': 'Shoulders',
    'lvl': 'Beginner',
    's': 3,
    'r': 15,
    'rest': 45,
  },
  {
    'n': 'Shoulder press',
    'm': 'Shoulders',
    'lvl': 'Intermediate',
    's': 3,
    'r': 10,
    'rest': 60,
  },
  {
    'n': 'Biceps curl',
    'm': 'Arms',
    'lvl': 'Beginner',
    's': 3,
    'r': 12,
    'rest': 45,
  },
  {
    'n': 'Triceps pushdown',
    'm': 'Arms',
    'lvl': 'Beginner',
    's': 3,
    'r': 15,
    'rest': 45,
  },
  {
    'n': 'Hammer curl',
    'm': 'Arms',
    'lvl': 'Beginner',
    's': 3,
    'r': 12,
    'rest': 45,
  },
  {'n': 'Plank', 'm': 'Core', 'lvl': 'Beginner', 's': 3, 'r': 30, 'rest': 30},
  {
    'n': 'Crunches',
    'm': 'Core',
    'lvl': 'Beginner',
    's': 3,
    'r': 20,
    'rest': 30,
  },
  {
    'n': 'Dead bug',
    'm': 'Core',
    'lvl': 'Beginner',
    's': 3,
    'r': 12,
    'rest': 30,
  },
  {
    'n': 'Russian twist',
    'm': 'Core',
    'lvl': 'Intermediate',
    's': 3,
    'r': 20,
    'rest': 30,
  },
  {
    'n': 'Jumping jacks',
    'm': 'Cardio',
    'lvl': 'Beginner',
    's': 3,
    'r': 40,
    'rest': 30,
  },
  {
    'n': 'High knees',
    'm': 'Cardio',
    'lvl': 'Beginner',
    's': 3,
    'r': 30,
    'rest': 30,
  },
  {
    'n': 'Mountain climbers',
    'm': 'Cardio',
    'lvl': 'Intermediate',
    's': 4,
    'r': 30,
    'rest': 30,
  },
  {
    'n': 'Burpees',
    'm': 'Cardio',
    'lvl': 'Intermediate',
    's': 4,
    'r': 12,
    'rest': 30,
  },
  {
    'n': 'Jump rope',
    'm': 'Cardio',
    'lvl': 'Intermediate',
    's': 4,
    'r': 60,
    'rest': 30,
  },
  {
    'n': 'Sprint intervals',
    'm': 'Cardio',
    'lvl': 'Advanced',
    's': 6,
    'r': 30,
    'rest': 60,
  },
];

class ExerciseLibraryScreen extends StatefulWidget {
  final String title;
  const ExerciseLibraryScreen({super.key, this.title = 'Choose exercises'});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  static const _levels = ['All', 'Beginner', 'Intermediate', 'Advanced'];
  static const _groups = [
    'All',
    'Chest',
    'Back',
    'Legs',
    'Shoulders',
    'Arms',
    'Core',
    'Cardio',
    'Full body',
  ];

  String _query = '';
  String _level = 'All';
  String _group = 'All';
  final Map<String, Map<String, dynamic>> _selected = {};
  final List<Map<String, dynamic>> _custom = [];

  Future<void> _addCustom() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CustomExerciseSheet(),
    );
    if (result == null || !mounted) return;
    final name = result['n'] as String;
    if (_library.any((exercise) => exercise['n'] == name) ||
        _custom.any((exercise) => exercise['n'] == name)) {
      snack(context, 'An exercise with that name already exists.');
      return;
    }

    setState(() {
      _custom.add(result);
      _selected[name] = result;
    });
  }

  Widget _filterChips(
    List<String> options,
    String selected,
    ValueChanged<String> onSelected,
  ) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      stops: [0, .82, 1],
      colors: [Colors.black, Colors.black, Colors.transparent],
    ).createShader(bounds),
    child: SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final active = option == selected;
          return ChoiceChip(
            label: Text(option),
            selected: active,
            showCheckmark: false,
            selectedColor: primaryOf(context),
            labelStyle: TextStyle(
              color: active
                  ? (isDark(context) ? kInk : Colors.white)
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => onSelected(option),
          );
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final exercises = [..._library, ..._custom]
        .where(
          (exercise) =>
              (_level == 'All' || exercise['lvl'] == _level) &&
              (_group == 'All' || exercise['m'] == _group) &&
              (exercise['n'] as String).toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kGapLg, kGapLg, kGapLg, 0),
              child: hdr(
                context,
                'Build your workout',
                widget.title,
                back: true,
                act: [
                  TextButton.icon(
                    onPressed: _addCustom,
                    icon: const Icon(Icons.add),
                    label: const Text('Custom'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGapLg),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search exercises',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGapLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: kGapMd),
                  _filterLabel('LEVEL'),
                  _filterChips(
                    _levels,
                    _level,
                    (value) => setState(() => _level = value),
                  ),
                  const SizedBox(height: kGapSm),
                  _filterLabel('MUSCLE'),
                  _filterChips(
                    _groups,
                    _group,
                    (value) => setState(() => _group = value),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kGapLg,
                kGapMd,
                kGapLg,
                kGapSm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${exercises.length} exercises',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(kGapLg, kGapXs, kGapLg, 120),
                children: [
                  if (exercises.isEmpty) ...[
                    const SizedBox(height: kGapXl),
                    Center(
                      child: Text(
                        'No exercises match your filters.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ] else ...[
                    for (final exercise in exercises) _exerciseCard(exercise),
                  ],
                  _createExerciseLink(),
                ],
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
            padding: const EdgeInsets.fromLTRB(kGapLg, kGapLg, kGapLg, kGapMd),
            child: FilledButton.icon(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, _selected.values.toList()),
              icon: const Icon(Icons.playlist_add_check),
              label: Text(
                _selected.isEmpty
                    ? 'Pick at least 1 exercise'
                    : 'Continue (${_selected.length} selected)',
              ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: kGapXs),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    ),
  );

  Widget _createExerciseLink() => Padding(
    padding: const EdgeInsets.symmetric(vertical: kGapMd),
    child: Center(
      child: TextButton.icon(
        onPressed: _addCustom,
        icon: const Icon(Icons.add, size: 19),
        label: const Text("Can't find it? Create a custom exercise"),
        style: TextButton.styleFrom(
          foregroundColor: primaryOf(context),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );

  Widget _exerciseCard(Map<String, dynamic> exercise) {
    final name = exercise['n'] as String;
    final selected = _selected.containsKey(name);
    final borderColor = selected
        ? primaryOf(context)
        : Theme.of(context).colorScheme.outlineVariant;
    final levelColor = _difficultyColor(context, exercise['lvl'] as String);
    return Padding(
      padding: const EdgeInsets.only(bottom: kGapMd),
      child: Material(
        color: selected
            ? tintOf(context)
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borderColor, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          focusColor: primaryOf(context).withValues(alpha: .18),
          onTap: () => setState(() {
            if (selected) {
              _selected.remove(name);
            } else {
              _selected[name] = Map<String, dynamic>.from(exercise);
            }
          }),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: tintOf(context),
                    child: Icon(
                      _libraryIconFor(name, exercise['m']),
                      color: primaryOf(context),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: kGapMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: kGapXs),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: levelColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              exercise['lvl'] as String,
                              style: TextStyle(
                                color: levelColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                '${exercise['m']} · ${exercise['s']} × ${exercise['r']}${exercise['unit'] == 'sec' ? ' sec' : ''}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: kGapSm),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.add_circle_outline,
                        color: primaryOf(context),
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _difficultyColor(BuildContext context, String level) {
    final dark = isDark(context);
    return switch (level) {
      'Beginner' => dark ? const Color(0xFFA7F3B1) : const Color(0xFF14532D),
      'Intermediate' =>
        dark ? const Color(0xFFFFD080) : const Color(0xFF7A4300),
      _ => dark ? const Color(0xFFFF9B91) : const Color(0xFF8B1E1E),
    };
  }

  IconData _libraryIconFor(Object? name, Object? group) {
    final value = (name ?? '').toString().toLowerCase();
    if (value.contains('dumbbell')) return Icons.fitness_center;
    if (value.contains('barbell')) return Icons.sports_gymnastics;
    if (value.contains('cable') || value.contains('pulldown')) {
      return Icons.settings_input_component;
    }
    return exerciseIconFor(name, group);
  }
}

class _CustomExerciseSheet extends StatefulWidget {
  const _CustomExerciseSheet();

  @override
  State<_CustomExerciseSheet> createState() => _CustomExerciseSheetState();
}

class _CustomExerciseSheetState extends State<_CustomExerciseSheet> {
  static const _groups = [
    'Chest',
    'Back',
    'Legs',
    'Shoulders',
    'Arms',
    'Core',
    'Cardio',
    'Full body',
  ];
  static const _levels = ['Beginner', 'Intermediate', 'Advanced'];
  static const _restOptions = [30, 45, 60, 90];

  final _name = TextEditingController();
  int _sets = 3;
  int _amount = 10;
  int _rest = 60;
  String _measure = 'Reps';
  String _group = 'Chest';
  String _level = 'Beginner';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = math.min(
      MediaQuery.sizeOf(context).height * .9,
      MediaQuery.sizeOf(context).height - insets - 24,
    );
    final canSave = _name.text.trim().isNotEmpty;
    final nameError = _name.text.isNotEmpty && _name.text.trim().isEmpty
        ? 'Name cannot contain only spaces'
        : null;
    final amountUnit = _measure == 'Time' ? 'sec' : 'reps';
    final summaryName = _name.text.trim().isEmpty
        ? 'Your exercise'
        : _name.text.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Create your exercise',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: kGapXs),
                        Text(
                          'Add a move that fits your workout.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: kGapLg),
                        TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          decoration: _fieldDecoration(
                            'Exercise name',
                            hint: 'e.g. Resistance band press',
                            errorText: nameError,
                          ),
                        ),
                        const SizedBox(height: kGapMd),
                        _sectionLabel('Muscle group'),
                        Wrap(
                          spacing: kGapSm,
                          runSpacing: kGapXs,
                          children: [
                            for (final group in _groups)
                              _choiceChip(
                                group,
                                selected: group == _group,
                                onSelected: () =>
                                    setState(() => _group = group),
                              ),
                          ],
                        ),
                        const SizedBox(height: kGapMd),
                        _sectionLabel('Difficulty'),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: [
                              for (final level in _levels)
                                ButtonSegment(value: level, label: Text(level)),
                            ],
                            selected: {_level},
                            onSelectionChanged: (selection) =>
                                setState(() => _level = selection.first),
                            showSelectedIcon: false,
                          ),
                        ),
                        const SizedBox(height: kGapMd),
                        _sectionLabel('Measure by'),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'Reps', label: Text('Reps')),
                              ButtonSegment(value: 'Time', label: Text('Time')),
                            ],
                            selected: {_measure},
                            onSelectionChanged: (selection) => setState(() {
                              _measure = selection.first;
                              _amount = _measure == 'Time' ? 30 : 10;
                            }),
                            showSelectedIcon: false,
                          ),
                        ),
                        const SizedBox(height: kGapMd),
                        Row(
                          children: [
                            Expanded(
                              child: _stepper(
                                label: 'Sets',
                                value: _sets,
                                minimum: 1,
                                maximum: 10,
                                onChanged: (value) =>
                                    setState(() => _sets = value),
                              ),
                            ),
                            const SizedBox(width: kGapMd),
                            Expanded(
                              child: _stepper(
                                label: _measure == 'Time'
                                    ? 'Duration'
                                    : 'Amount',
                                value: _amount,
                                minimum: _measure == 'Time' ? 5 : 1,
                                maximum: _measure == 'Time' ? 300 : 300,
                                step: _measure == 'Time' ? 5 : 1,
                                suffix: _measure == 'Time' ? 'sec' : 'reps',
                                onChanged: (value) =>
                                    setState(() => _amount = value),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: kGapMd),
                        _sectionLabel('Rest between sets'),
                        Wrap(
                          spacing: kGapSm,
                          children: [
                            for (final rest in _restOptions)
                              _choiceChip(
                                '$rest sec',
                                selected: _rest == rest,
                                onSelected: () => setState(() => _rest = rest),
                              ),
                          ],
                        ),
                        const SizedBox(height: kGapLg),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(kGapMd),
                          decoration: BoxDecoration(
                            color: tintOf(context),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 19,
                                backgroundColor: primaryOf(context),
                                foregroundColor: isDark(context)
                                    ? kInk
                                    : Colors.white,
                                child: Text(
                                  summaryName.characters.first.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: kGapMd),
                              Expanded(
                                child: Text(
                                  '$summaryName · $_sets × $_amount $amountUnit · ${_rest}s rest · $_level · $_group',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: kGapMd),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canSave ? _save : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: primaryOf(context),
                      foregroundColor: isDark(context) ? kInk : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Add custom exercise'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    String label, {
    String? hint,
    String? errorText,
  }) {
    final dark = isDark(context);
    final borderColor = dark
        ? const Color(0xFF8AA39D)
        : const Color(0xFF526A65);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: TextStyle(color: dark ? const Color(0xFFD2E1DD) : kDk),
      floatingLabelStyle: TextStyle(
        color: primaryOf(context),
        fontWeight: FontWeight.w700,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: primaryOf(context), width: 3),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: kGapSm),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _choiceChip(
    String label, {
    required bool selected,
    required VoidCallback onSelected,
  }) => ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    selectedColor: primaryOf(context),
    labelStyle: TextStyle(
      color: selected
          ? (isDark(context) ? kInk : Colors.white)
          : Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    ),
    onSelected: (_) => onSelected(),
  );

  Widget _stepper({
    required String label,
    required int value,
    required int minimum,
    required int maximum,
    required ValueChanged<int> onChanged,
    int step = 1,
    String? suffix,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionLabel(label),
      Container(
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                tooltip: 'Decrease $label',
                focusColor: primaryOf(context).withValues(alpha: .2),
                onPressed: value > minimum
                    ? () => onChanged(math.max(minimum, value - step))
                    : null,
                icon: const Icon(Icons.remove),
              ),
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  suffix == null ? '$value' : '$value $suffix',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                tooltip: 'Increase $label',
                focusColor: primaryOf(context).withValues(alpha: .2),
                onPressed: value < maximum
                    ? () => onChanged(math.min(maximum, value + step))
                    : null,
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      snack(context, 'Add an exercise name first.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'n': name,
      'm': _group,
      'lvl': _level,
      's': _sets,
      'r': _amount,
      'unit': _measure == 'Time' ? 'sec' : 'reps',
      'rest': _rest,
    });
  }
}
