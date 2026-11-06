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
  });

  test('choosing a palette updates the controller and persists', () async {
    controller.applyPalette('ocean');
    await Future<void>.delayed(Duration.zero);

    expect(controller.selectedPaletteId, 'ocean');
    expect(testStore.d['palette'], 'ocean');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('ft'), contains('"palette":"ocean"'));
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
    testStore.d['palette'] = 'forest';
    testStore.save();
    await Future<void>.delayed(Duration.zero);

    final reloadedStore = Store();
    await reloadedStore.init();
    final reloadedController = ThemeController(reloadedStore);
    addTearDown(reloadedController.dispose);
    addTearDown(reloadedStore.dispose);

    expect(reloadedController.selectedPaletteId, 'forest');
  });

  test('reset returns the palette to Teal', () {
    controller.previewPalette('rose');
    controller.resetToDefault();

    expect(controller.selectedPaletteId, AppPalette.teal.id);
    controller.applyPalette(AppPalette.teal.id);
    expect(testStore.d['palette'], AppPalette.teal.id);
  });
}
