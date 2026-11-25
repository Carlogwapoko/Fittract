import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittract/widgets/responsive_app_frame.dart';

void main() {
  testWidgets('keeps content full-width on a phone-sized viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            ResponsiveAppFrame(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: SizedBox.expand(
            key: const ValueKey('responsive-content'),
            child: const ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('responsive-content'))).width,
      360,
    );
  });

  testWidgets('centers content within a readable tablet width', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            ResponsiveAppFrame(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: SizedBox.expand(
            key: const ValueKey('responsive-content'),
            child: const ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );

    final content = tester.getRect(
      find.byKey(const ValueKey('responsive-content')),
    );
    expect(content.width, appContentMaxWidth);
    expect(content.center.dx, 600);
  });
}
