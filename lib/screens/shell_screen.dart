import 'dart:async';

import 'package:flutter/material.dart';

import '../store/store.dart';
import 'today_tab.dart';
import 'routines_tab.dart';
import 'schedule_tab.dart';
import 'progress_tab.dart';
import 'profile_tab.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int i = 0;
  Timer? _dayWatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Detect midnight rollover while the app stays open. roll() is guarded
    // by a per-date check, so this poll is a cheap no-op until the date
    // actually changes.
    _dayWatch = Timer.periodic(
      const Duration(minutes: 1),
      (_) => store.roll(),
    );
  }

  @override
  void dispose() {
    _dayWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) store.roll();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      TodayTab(goTo: (n) => setState(() => i = n)),
      const RoutinesTab(),
      const ScheduleTab(),
      const ProgressTab(),
      const ProfileTab(),
    ];
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          for (var index = 0; index < tabs.length; index++)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: index != i,
                child: ExcludeSemantics(
                  excluding: index != i,
                  child: AnimatedSlide(
                    offset: index == i
                        ? Offset.zero
                        : Offset(index < i ? -.035 : .035, 0),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOutCubic,
                    child: AnimatedOpacity(
                      opacity: index == i ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: TickerMode(
                        enabled: index == i,
                        child: tabs[index],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (n) => setState(() => i = n),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center),
            label: 'Routines',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
