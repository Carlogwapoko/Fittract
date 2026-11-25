import 'package:flutter/material.dart';

const double appContentMaxWidth = 760;

class ResponsiveAppFrame extends StatelessWidget {
  const ResponsiveAppFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final availableWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : media.size.width;
      final width = availableWidth.clamp(0.0, appContentMaxWidth);
      final height = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : media.size.height;

      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: appContentMaxWidth),
            child: SizedBox(
              width: width,
              height: height,
              child: MediaQuery(
                data: media.copyWith(size: Size(width, height)),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}
