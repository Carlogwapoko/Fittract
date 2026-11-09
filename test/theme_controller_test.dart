import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fittract/services/theme_controller.dart';
import 'package:fittract/store/store.dart';
import 'package:fittract/theme/app_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Store testStore;
  late ThemeController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testStore = Store();
    await testStore.init();
    controller = ThemeController(testStore);
  });

  tearDown(() {
    controller.dispose();
    testStore.dispose();
  });

  test('Teal is the default palette', () {
    expect(controller.selectedPaletteId, AppPalette.teal.id);
    expect(AppPalette.all.map((palette) => palette.name), [
      'Teal',
      'Soft sand',
      'Sage mist',
      'Color-blind safe',
      'High contrast',
      'Graphite (gray)',
    ]);
  });

  test('choosing a palette updates the controller and persists', () async {
    controller.applyPalette('sage_mist');
    await Future<void>.delayed(Duration.zero);

    expect(controller.selectedPaletteId, 'sage_mist');
    expect(testStore.d['palette'], 'sage_mist');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('ft_palette'), 'sage_mist');
    expect(preferences.getString('ft'), contains('"palette":"sage_mist"'));
  });

  test('the saved palette is loaded on startup', () async {
    expect(
      await testStore.register(
        name: 'Palette tester',
        email: 'palette@example.com',
        password: 'password1',
      ),
      AuthResult.success,
    );
    expect(
      await testStore.login(
        email: 'palette@example.com',
        password: 'password1',
      ),
      AuthResult.success,
    );
    testStore.d['palette'] = 'graphite';
    testStore.save();
    await Future<void>.delayed(Duration.zero);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('ft_palette', 'graphite');

    final reloadedStore = Store();
    await reloadedStore.init();
    final reloadedController = ThemeController(reloadedStore);
    addTearDown(reloadedController.dispose);
    addTearDown(reloadedStore.dispose);

    expect(reloadedController.selectedPaletteId, 'graphite');
  });

  test('reset returns the palette to Teal', () {
    controller.previewPalette('soft_sand');
    controller.resetToDefault();

    expect(controller.selectedPaletteId, AppPalette.teal.id);
    controller.applyPalette(AppPalette.teal.id);
    expect(testStore.d['palette'], AppPalette.teal.id);
  });

  test('dark mode and palette persist independently', () async {
    controller.applyPalette('graphite');
    controller.setDarkMode(true);
    await Future<void>.delayed(Duration.zero);

    expect(controller.selectedPaletteId, 'graphite');
    expect(controller.darkMode, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('ft_dark_mode'), isTrue);
    expect(preferences.getString('ft_palette'), 'graphite');

    controller.setDarkMode(false);
    expect(controller.selectedPaletteId, 'graphite');
    expect(controller.darkMode, isFalse);
  });

  test('unknown saved palette falls back to Teal', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('ft_palette', 'unknown_palette');

    final reloadedStore = Store();
    await reloadedStore.init();
    final reloadedController = ThemeController(reloadedStore);
    addTearDown(reloadedController.dispose);
    addTearDown(reloadedStore.dispose);

    expect(reloadedController.selectedPaletteId, AppPalette.teal.id);
    expect(reloadedStore.d['palette'], AppPalette.teal.id);
    expect(preferences.getString('ft_palette'), AppPalette.teal.id);
  });
}
