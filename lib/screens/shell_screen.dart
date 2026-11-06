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
    _dayWatch = Timer.periodic(const Duration(minutes: 1), (_) => store.roll());
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
      bottomNavigationBar: _TodayNavigationBar(
        selectedIndex: i,
        onSelected: (n) => setState(() => i = n),
      ),
    );
  }
}

class _TodayNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _TodayNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  static const _items = [
    (Icons.home, 'Today'),
    (Icons.fitness_center, 'Routines'),
    (Icons.calendar_month, 'Schedule'),
    (Icons.show_chart, 'Progress'),
    (Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final colors = Theme.of(context).colorScheme;
    final selectedColor = colors.primary;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .24 : .08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                Expanded(
                  child: _NavigationDestination(
                    selected: selectedIndex == index,
                    icon: _items[index].$1,
                    label: _items[index].$2,
                    selectedColor: selectedColor,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationDestination extends StatefulWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final Color selectedColor;
  final VoidCallback onTap;

  const _NavigationDestination({
    required this.selected,
    required this.icon,
    required this.label,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  State<_NavigationDestination> createState() => _NavigationDestinationState();
}

class _NavigationDestinationState extends State<_NavigationDestination> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = widget.selected ? widget.selectedColor : muted;

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
        scale: _pressed ? .96 : (_hovered ? 1.025 : 1),
        duration: const Duration(milliseconds: 120),
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: widget.label,
          child: InkWell(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: () {
              setState(() => _pressed = false);
              widget.onTap();
            },
            child: SizedBox(
              height: 72,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: widget.selected ? 52 : 44,
                    height: 30,
                    decoration: BoxDecoration(
                      color: widget.selected
                          ? tintOf(context)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: _hovered
                          ? [
                              BoxShadow(
                                color: widget.selectedColor.withValues(
                                  alpha: .2,
                                ),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(widget.icon, size: 21, color: color),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: widget.selected
                          ? FontWeight.w700
                          : FontWeight.w500,
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
}
