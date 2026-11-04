import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/session_wake_lock_stub.dart'
    if (dart.library.js_interop) '../services/session_wake_lock_web.dart';
import '../store/store.dart';
import '../widgets/shared_widgets.dart';

class WorkoutScreen extends StatefulWidget {
  final Map r;
  const WorkoutScreen(this.r, {super.key});
  @override
  State<WorkoutScreen> createState() => _WorkoutState();
}

class _WorkoutState extends State<WorkoutScreen> with WidgetsBindingObserver {
  late final List exs = widget.r['ex'] is List
      ? widget.r['ex'] as List
      : <dynamic>[];
  int i = 0, secs = 0;
  bool paused = false;
  bool _allowLeave = false;
  bool _askingLeave = false;
  bool _finished = false;
  bool _blockedByOtherSession = false;
  int restLeft = 0, restTotal = 0;
  late List<bool> done;
  late List<bool> bodyweight;
  late List<List<Map<String, dynamic>>> sets;
  Timer? tm;
  final SessionWakeLock _wakeLock = SessionWakeLock();

  dynamic get _rid => widget.r['id'] ?? widget.r['name'];
  bool get _isEmptyRoutine => exs.isEmpty;
  int get _doneCount => done.where((value) => value).length;
  int get _setCount => sets.fold<int>(0, (sum, row) => sum + row.length);
  int get _setsDone => sets.fold<int>(
    0,
    (sum, row) => sum + row.where((set) => set['ok'] == true).length,
  );
  String get _category => (widget.r['type'] ?? 'Strength').toString();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    done = List<bool>.filled(exs.length, false);
    bodyweight = [for (final exercise in exs) _isBodyweight(exercise)];
    sets = _freshSets();
    _adoptSavedProgress();
    tm = Timer.periodic(const Duration(seconds: 1), _tick);
    if (!_blockedByOtherSession && !_isEmptyRoutine) _persist();
    if (!paused && !_blockedByOtherSession && !_isEmptyRoutine) {
      unawaited(_wakeLock.enable());
    }
    if (_restoredFromSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) snack(context, 'Resumed your saved session.');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    tm?.cancel();
    if (!_finished && !_blockedByOtherSession && !_isEmptyRoutine) _persist();
    unawaited(_wakeLock.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!paused && !_finished && !_blockedByOtherSession) {
        unawaited(_wakeLock.enable());
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _persist();
    }
  }

  bool _restoredFromSession = false;

  bool _isBodyweight(dynamic exercise) {
    if (exercise is! Map) return false;
    if (exercise['bodyweight'] is bool) return exercise['bodyweight'] == true;
    final name = (exercise['n'] ?? '').toString().toLowerCase();
    return [
      'burpee',
      'push-up',
      'pushup',
      'bodyweight',
      'jumping jack',
      'mountain climber',
      'pull-up',
      'pullup',
      'plank',
    ].any(name.contains);
  }

  bool _isTimeExercise(dynamic exercise) {
    if (exercise is! Map) return false;
    if (exercise['unit'] == 'sec') return true;
    final name = (exercise['n'] ?? '').toString().toLowerCase();
    return [
      'plank',
      'mountain climber',
      'high knees',
      'jumping jack',
      'sprint interval',
      'jump rope',
    ].any(name.contains);
  }

  List<Map<String, dynamic>> _previousSets(dynamic exercise) {
    final history = store.d['lastWorkout'];
    if (history is! Map) return const [];
    final routineHistory = history['$_rid'];
    if (routineHistory is! Map) return const [];
    final rows = routineHistory[exercise['n']];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  List<List<Map<String, dynamic>>> _freshSets() => [
    for (final exercise in exs)
      [
        for (var index = 0; index < _exerciseSetCount(exercise); index++)
          _newSet(exercise, index),
      ],
  ];

  int _exerciseSetCount(dynamic exercise) =>
      (((exercise['s'] as num?) ?? kSetsMin).toInt()).clamp(kSetsMin, kSetsMax);

  Map<String, dynamic> _newSet(dynamic exercise, int index) {
    final previous = _previousSets(exercise);
    final last = previous.isEmpty
        ? const <String, dynamic>{}
        : previous[math.min(index, previous.length - 1)];
    return {
      'kg': last['kg'] ?? 0,
      'rp': last['rp'] ?? exercise['r'] ?? 10,
      'ok': false,
    };
  }

  void _adoptSavedProgress() {
    final raw = store.d['activeW'];
    if (raw is! Map) return;
    final saved = Map<String, dynamic>.from(raw);

    if (saved['rid'] != _rid) {
      _blockedByOtherSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final discard = await _confirmDialog(
          title:
              'Discard the saved session for ${saved['name'] ?? 'another workout'}?',
          cancelLabel: 'Keep session',
          confirmLabel: 'Discard',
          destructive: true,
        );
        if (!mounted) return;
        if (discard) {
          _blockedByOtherSession = false;
          store.d.remove('activeW');
          store.save();
          _persist();
          setState(() {});
        } else {
          _popSafely();
        }
      });
      return;
    }

    final savedDone = saved['done'];
    final savedSets = saved['sets'];
    if (savedDone is! List ||
        savedDone.length != exs.length ||
        savedSets is! List ||
        savedSets.length != exs.length) {
      return;
    }
    for (var index = 0; index < exs.length; index++) {
      if (savedSets[index] is! List) return;
    }
    done = List<bool>.from(savedDone.map((value) => value == true));
    sets = [
      for (final row in savedSets)
        [
          for (final rawSet in row as List)
            if (rawSet is Map) Map<String, dynamic>.from(rawSet),
        ],
    ];
    while (sets.length < exs.length) {
      sets.add([]);
    }
    for (var index = 0; index < exs.length; index++) {
      while (sets[index].length < _exerciseSetCount(exs[index])) {
        sets[index].add(_newSet(exs[index], sets[index].length));
      }
    }
    final savedBodyweight = saved['bodyweight'];
    if (savedBodyweight is List && savedBodyweight.length == exs.length) {
      bodyweight = List<bool>.from(
        savedBodyweight.map((value) => value == true),
      );
    }
    final hi = exs.length - 1;
    i = hi < 0 ? 0 : (((saved['i'] as num?) ?? 0).toInt()).clamp(0, hi);
    secs = (((saved['secs'] as num?) ?? 0).toInt()).clamp(0, 86400);
    restLeft = (((saved['restLeft'] as num?) ?? 0).toInt()).clamp(0, kRestMax);
    restTotal = (((saved['restTotal'] as num?) ?? 0).toInt()).clamp(
      0,
      kRestMax,
    );
    paused = saved['paused'] == true;
    if (restLeft > 0) {
      final savedAt = ((saved['savedAt'] as num?) ?? 0).toInt();
      if (savedAt > 0) {
        final gap = ((DateTime.now().millisecondsSinceEpoch - savedAt) ~/ 1000)
            .clamp(0, kRestMax)
            .toInt();
        if (gap >= restLeft) {
          restLeft = 0;
          restTotal = 0;
        } else {
          restLeft -= gap;
        }
      }
    }
    _restoredFromSession = true;
  }

  void _persist() {
    if (_blockedByOtherSession || _isEmptyRoutine || _finished) return;
    store.d['activeW'] = {
      'rid': _rid,
      'name': widget.r['name'],
      'routine': Map<String, dynamic>.from(widget.r),
      'i': i,
      'secs': secs,
      'done': done,
      'sets': sets,
      'bodyweight': bodyweight,
      'restLeft': restLeft,
      'restTotal': restTotal,
      'paused': paused,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };
    store.saveQuiet();
  }

  Future<void> _releaseAndPersist() async {
    if (!_finished && !_blockedByOtherSession) {
      paused = true;
      _persist();
    }
    await _wakeLock.disable();
  }

  void _clearProgress() {
    _finished = true;
    store.d.remove('activeW');
    store.save();
    unawaited(_wakeLock.disable());
  }

  void _popSafely() {
    if (!mounted) return;
    setState(() => _allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void _tick(Timer timer) {
    if (!mounted || paused) return;
    var restEnded = false;
    setState(() {
      secs++;
      if (restLeft > 0) {
        restLeft--;
        if (restLeft == 0) {
          restTotal = 0;
          restEnded = true;
        }
      }
      if (secs % 5 == 0 || restEnded) _persist();
    });
    if (restEnded) unawaited(HapticFeedback.vibrate());
  }

  String _clock(int total) =>
      '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';

  void _togglePause() {
    setState(() => paused = !paused);
    if (paused) {
      unawaited(_wakeLock.disable());
    } else {
      unawaited(_wakeLock.enable());
    }
    _persist();
  }

  void _changeRest(int delta) {
    setState(() {
      restLeft = (restLeft + delta).clamp(0, kRestMax);
      restTotal = math.max(restTotal, restLeft);
    });
    _persist();
  }

  void _skipRest() {
    setState(() {
      restLeft = 0;
      restTotal = 0;
    });
    _persist();
  }

  void _toggleSet(int index) {
    final checking = sets[i][index]['ok'] != true;
    if (checking) {
      final validation = _validateSet(sets[i][index], i);
      if (validation != null) {
        snack(context, validation);
        return;
      }
    }
    setState(() {
      sets[i][index]['ok'] = checking;
      if (!checking) {
        done[i] = false;
        restLeft = 0;
        restTotal = 0;
      } else {
        done[i] =
            sets[i].isNotEmpty && sets[i].every((set) => set['ok'] == true);
        if (!(i == exs.length - 1 && index == sets[i].length - 1)) {
          final rest = (((exs[i]['rest'] as num?) ?? 0).toInt()).clamp(
            kRestMin,
            kRestMax,
          );
          restLeft = rest;
          restTotal = rest;
        }
      }
      _persist();
    });
  }

  String? _validateSet(Map<String, dynamic> set, int exerciseIndex) {
    final exercise = exs[exerciseIndex] as Map;
    if (_isTimeExercise(exercise)) {
      final amount = set['rp'] as num? ?? 0;
      return amount < 1 || amount > kRepsMax
          ? 'Seconds must be between $kRepsMin and $kRepsMax.'
          : null;
    }
    final reps = set['rp'] as num? ?? 0;
    if (reps < kRepsMin || reps > kRepsMax) {
      return 'Reps must be between $kRepsMin and $kRepsMax.';
    }
    if (!bodyweight[exerciseIndex]) {
      final kg = set['kg'] as num? ?? 0;
      if (kg < kKgMin || kg > kKgMax) {
        return validateSetLoad(kg, reps);
      }
    }
    return null;
  }

  void _changeSetValue(
    int exerciseIndex,
    int setIndex,
    String key,
    String raw,
  ) {
    final parsed = key == 'kg' ? double.tryParse(raw) : int.tryParse(raw);
    if (parsed == null) return;
    sets[exerciseIndex][setIndex][key] = parsed;
    _persist();
  }

  void _addSet() {
    if (sets[i].length >= kSetsMax) return;
    final source =
        sets[i].isEmpty
              ? _newSet(exs[i], 0)
              : Map<String, dynamic>.from(sets[i].last)
          ..['ok'] = false;
    setState(() {
      sets[i].add(source);
      done[i] = false;
    });
    _persist();
  }

  void _navigateTo(int index) {
    if (index < 0 || index >= exs.length) return;
    setState(() {
      i = index;
      _persist();
    });
  }

  Future<bool> _confirmDialog({
    required String title,
    required String cancelLabel,
    required String confirmLabel,
    bool destructive = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(cancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(
                foregroundColor: destructive
                    ? Theme.of(dialogContext).colorScheme.error
                    : primaryOf(dialogContext),
              ),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _requestLeave() async {
    if (_askingLeave) return;
    _askingLeave = true;
    final leave = await _confirmDialog(
      title: 'Leave session?',
      cancelLabel: 'Stay',
      confirmLabel: 'Pause & exit',
    );
    _askingLeave = false;
    if (!leave || !mounted) return;
    await _releaseAndPersist();
    _popSafely();
  }

  Future<void> _pauseAndExit() async {
    await _releaseAndPersist();
    _popSafely();
  }

  Future<void> _discard() async {
    final discard = await _confirmDialog(
      title: "Discard this session? Your sets won't be saved.",
      cancelLabel: 'Keep session',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!discard || !mounted) return;
    _clearProgress();
    _popSafely();
  }

  int _volumeKgReps() {
    var volume = 0.0;
    for (var exerciseIndex = 0; exerciseIndex < sets.length; exerciseIndex++) {
      final exercise = exs[exerciseIndex] as Map;
      if (bodyweight[exerciseIndex] || _isTimeExercise(exercise)) continue;
      for (final set in sets[exerciseIndex]) {
        if (set['ok'] == true) {
          volume += (set['kg'] as num? ?? 0) * (set['rp'] as num? ?? 0);
        }
      }
    }
    return volume.round();
  }

  Future<void> _finish() async {
    for (var exerciseIndex = 0; exerciseIndex < sets.length; exerciseIndex++) {
      for (final set in sets[exerciseIndex]) {
        if (set['ok'] != true) continue;
        final error = _validateSet(set, exerciseIndex);
        if (error != null) {
          snack(context, error);
          return;
        }
      }
    }
    final incomplete = done.where((value) => !value).length;
    if (incomplete > 0) {
      final finishAnyway = await _confirmDialog(
        title:
            'Finish workout? $incomplete ${incomplete == 1 ? 'exercise' : 'exercises'} not done. Finish anyway?',
        cancelLabel: 'Keep going',
        confirmLabel: 'Finish',
      );
      if (!finishAnyway || !mounted) return;
    }
    final setTotal = _setCount;
    final setDone = _setsDone;
    final volume = _volumeKgReps();
    final history = <String, dynamic>{
      'n': '${widget.r['name'] ?? 'Workout'}',
      'd': today(),
      'min': secs < 60 ? 1 : (secs / 60).round(),
      'ex': _doneCount,
      'totalEx': exs.length,
      'sets': setDone,
      'kc': (secs / 60 * 7 + _doneCount * 20).round(),
    };
    store.hist.add(history);
    final lastWorkout = Map<String, dynamic>.from(
      store.d['lastWorkout'] is Map ? store.d['lastWorkout'] as Map : {},
    );
    final routineLog = Map<String, dynamic>.from(
      lastWorkout['$_rid'] is Map ? lastWorkout['$_rid'] as Map : {},
    );
    for (var exerciseIndex = 0; exerciseIndex < sets.length; exerciseIndex++) {
      routineLog['${exs[exerciseIndex]['n']}'] = [
        for (final set in sets[exerciseIndex])
          {'kg': set['kg'], 'rp': set['rp']},
      ];
    }
    lastWorkout['$_rid'] = routineLog;
    store.d['lastWorkout'] = lastWorkout;
    _finished = true;
    store.d.remove('activeW');
    store.save();
    await _wakeLock.disable();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Workout complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total time: ${_clock(secs)}'),
            Text('Sets completed: $setDone / $setTotal'),
            Text('Volume: $volume kg × reps'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(
              backgroundColor: primaryOf(dialogContext),
              foregroundColor: isDark(dialogContext) ? kInk : Colors.white,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) _popSafely();
  }

  @override
  Widget build(BuildContext context) {
    final nDone = _doneCount;
    final isTime = exs.isNotEmpty && _isTimeExercise(exs[i]);
    final isBodyweight = exs.isNotEmpty && !isTime && bodyweight[i];
    final allSetsDone =
        sets.isNotEmpty &&
        sets[i].isNotEmpty &&
        sets[i].every((set) => set['ok'] == true);
    final progress = _setCount == 0 ? 0.0 : _setsDone / _setCount;
    return PopScope<void>(
      canPop: _allowLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestLeave());
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kGapMd, kGapSm, kGapMd, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: _requestLeave,
                        focusColor: primaryOf(context).withValues(alpha: .18),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${_category.toUpperCase()} · LIVE SESSION',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: primaryOf(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Session options',
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      onSelected: (value) {
                        if (value == 'pause') unawaited(_pauseAndExit());
                        if (value == 'discard') unawaited(_discard());
                      },
                      itemBuilder: (menuContext) => [
                        const PopupMenuItem(
                          value: 'pause',
                          child: Text('Pause & exit'),
                        ),
                        PopupMenuItem(
                          value: 'discard',
                          child: Text(
                            'Discard session',
                            style: TextStyle(
                              color: Theme.of(menuContext).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      icon: const Icon(Icons.more_horiz),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(kGapLg, 0, kGapLg, kGapSm),
                child: Text(
                  '${widget.r['name'] ?? 'Workout'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _timerCard(nDone, progress),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    kGapLg,
                    kGapSm,
                    kGapLg,
                    20,
                  ),
                  children: [
                    if (_isEmptyRoutine)
                      card(
                        child: const Text(
                          'This routine has no exercises.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      )
                    else ...[
                      _exerciseCard(
                        index: i,
                        isTime: isTime,
                        isBodyweight: isBodyweight,
                        allSetsDone: allSetsDone,
                      ),
                      _sessionChecklist(nDone),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _bottomNavigation(),
      ),
    );
  }

  Widget _timerCard(int nDone, double progress) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kGapLg),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: kGapMd, vertical: kGapSm),
      decoration: BoxDecoration(
        color: isDark(context) ? const Color(0xFF1D3934) : kDk,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _clock(secs),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: paused ? 'Resume' : 'Pause',
                  onPressed: _togglePause,
                  color: Colors.white,
                  focusColor: kMint.withValues(alpha: .25),
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                ),
              ),
            ],
          ),
          Text(
            paused
                ? 'Paused'
                : exs.isEmpty
                ? 'No exercises'
                : 'Exercise ${i + 1} of ${exs.length} · $nDone done',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: kGapSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: const Color(0xFF8FF0D6),
              backgroundColor: Colors.white24,
            ),
          ),
          if (restLeft > 0) ...[
            const SizedBox(height: kGapSm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Rest ${_clock(restLeft)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: () => _changeRest(15),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('+15s'),
                  ),
                ),
                const SizedBox(width: kGapSm),
                SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: _skipRest,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Skip'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Widget _exerciseCard({
    required int index,
    required bool isTime,
    required bool isBodyweight,
    required bool allSetsDone,
  }) {
    final exercise = exs[index] as Map;
    final lastSets = _previousSets(exercise);
    final last = lastSets.isEmpty ? null : lastSets.first;
    final summaryUnit = isTime ? 'sec' : 'reps';
    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                exerciseIconFor(exercise['n'], exercise['m']),
                color: primaryOf(context),
                size: 23,
              ),
              const SizedBox(width: kGapSm),
              Expanded(
                child: Text(
                  '${exercise['n']}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: kGapXs),
          Text(
            '${sets[index].length} × ${exercise['r']} $summaryUnit · ${exercise['rest']} sec rest',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: kGapXs),
          Text(
            last == null
                ? 'Last time: No previous session'
                : bodyweight[index]
                ? 'Last time: Bodyweight × ${last['rp']} $summaryUnit'
                : 'Last time: ${last['kg']} kg × ${last['rp']} $summaryUnit',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (!isTime) ...[
            const SizedBox(height: kGapSm),
            Semantics(
              label: 'Bodyweight',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Bodyweight',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                value: bodyweight[index],
                onChanged: (value) => setState(() {
                  bodyweight[index] = value;
                  _persist();
                }),
              ),
            ),
          ],
          const SizedBox(height: kGapSm),
          _setHeader(isTime: isTime, isBodyweight: isBodyweight),
          for (var setIndex = 0; setIndex < sets[index].length; setIndex++)
            _setRow(
              exerciseIndex: index,
              setIndex: setIndex,
              isTime: isTime,
              isBodyweight: isBodyweight,
            ),
          const SizedBox(height: kGapSm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: sets[index].length >= kSetsMax ? null : _addSet,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: primaryOf(context),
                side: BorderSide(
                  color: primaryOf(context),
                  style: BorderStyle.solid,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: primaryOf(context)),
                ),
              ),
              child: const Text('+ Add set'),
            ),
          ),
          if (allSetsDone) ...[
            const SizedBox(height: kGapSm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(kGapSm),
              decoration: BoxDecoration(
                color: tintOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'All sets done ✓',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: primaryOf(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _setHeader({required bool isTime, required bool isBodyweight}) {
    final labels = isTime
        ? const ['SET', 'SEC']
        : isBodyweight
        ? const ['SET', 'REPS']
        : const ['SET', 'KG', 'REPS'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, kGapXs),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(labels.first, style: _setHeaderStyle(context)),
          ),
          for (final label in labels.skip(1))
            Expanded(
              child: Center(
                child: Text(label, style: _setHeaderStyle(context)),
              ),
            ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  TextStyle _setHeaderStyle(BuildContext context) => TextStyle(
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: .8,
  );

  Widget _setRow({
    required int exerciseIndex,
    required int setIndex,
    required bool isTime,
    required bool isBodyweight,
  }) {
    final set = sets[exerciseIndex][setIndex];
    final checked = set['ok'] == true;
    final background = checked
        ? (isDark(context) ? const Color(0xFF203D37) : const Color(0xFFE7F5F0))
        : Colors.transparent;
    return Container(
      margin: const EdgeInsets.only(bottom: kGapXs),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${setIndex + 1}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!isTime && !isBodyweight)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: SizedBox(
                  height: 48,
                  child: TextFormField(
                    key: ValueKey('kg$exerciseIndex$setIndex'),
                    initialValue: '${set['kg']}',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    decoration: _setInputDecoration(context),
                    onChanged: (value) =>
                        _changeSetValue(exerciseIndex, setIndex, 'kg', value),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: SizedBox(
                height: 48,
                child: TextFormField(
                  key: ValueKey('rp$exerciseIndex$setIndex'),
                  initialValue: '${set['rp']}',
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  decoration: _setInputDecoration(context),
                  onChanged: (value) =>
                      _changeSetValue(exerciseIndex, setIndex, 'rp', value),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: Semantics(
              button: true,
              label: checked
                  ? 'Uncheck set ${setIndex + 1}'
                  : 'Complete set ${setIndex + 1}',
              child: IconButton(
                tooltip: checked
                    ? 'Uncheck set ${setIndex + 1}'
                    : 'Complete set ${setIndex + 1}',
                onPressed: () => _toggleSet(setIndex),
                focusColor: primaryOf(context).withValues(alpha: .18),
                style: IconButton.styleFrom(
                  backgroundColor: checked ? primaryOf(context) : null,
                  foregroundColor: checked
                      ? (isDark(context) ? kInk : Colors.white)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  side: BorderSide(
                    color: checked
                        ? primaryOf(context)
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  shape: const CircleBorder(),
                ),
                icon: Icon(
                  checked ? Icons.check : Icons.circle_outlined,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _setInputDecoration(BuildContext context) => InputDecoration(
    filled: true,
    fillColor: Theme.of(context).colorScheme.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: primaryOf(context), width: 2),
    ),
  );

  Widget _sessionChecklist(int nDone) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      h3(
        'Session checklist',
        trailing: Text(
          '$nDone / ${exs.length} done',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ),
      for (var index = 0; index < exs.length; index++)
        Semantics(
          button: true,
          selected: index == i,
          label: '${exs[index]['n']}${index == i ? ', current exercise' : ''}',
          child: Material(
            color: index == i
                ? tintOf(context)
                : Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: index == i
                    ? primaryOf(context)
                    : Theme.of(context).colorScheme.outlineVariant,
                width: index == i ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              focusColor: primaryOf(context).withValues(alpha: .18),
              onTap: () => _navigateTo(index),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kGapSm),
                  child: Row(
                    children: [
                      Icon(
                        done[index]
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: done[index]
                            ? primaryOf(context)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: kGapSm),
                      Expanded(
                        child: Text(
                          '${exs[index]['n']}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: index == i || done[index]
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '${sets[index].length} × ${exs[index]['r']} ${_isTimeExercise(exs[index]) ? 'sec' : 'reps'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: kGapMd),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _finish,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: _doneCount == exs.length && exs.isNotEmpty
                ? primaryOf(context)
                : tintOf(context),
            foregroundColor: _doneCount == exs.length && exs.isNotEmpty
                ? (isDark(context) ? kInk : Colors.white)
                : primaryOf(context),
          ),
          child: const Text('Finish workout'),
        ),
      ),
    ],
  );

  Widget _bottomNavigation() => Container(
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
        padding: const EdgeInsets.fromLTRB(kGapLg, kGapMd, kGapLg, kGapSm),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: exs.isEmpty || i == 0
                    ? null
                    : () => _navigateTo(i - 1),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: primaryOf(context),
                  side: BorderSide(color: primaryOf(context)),
                ),
                child: const Text('‹ Prev'),
              ),
            ),
            const SizedBox(width: kGapSm),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: exs.isEmpty
                    ? null
                    : i == exs.length - 1
                    ? _finish
                    : () => _navigateTo(i + 1),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: primaryOf(context),
                  foregroundColor: isDark(context) ? kInk : Colors.white,
                ),
                child: Text(i == exs.length - 1 ? 'Finish ✓' : 'Next ›'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
