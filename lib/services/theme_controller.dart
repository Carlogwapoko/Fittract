import 'package:flutter/foundation.dart';

import '../store/store.dart';
import '../theme/app_palette.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this._store) {
    _store.addListener(_storeChanged);
    _readStore();
  }

  final Store _store;
  String _selectedPaletteId = AppPalette.teal.id;
  bool _darkMode = false;
  String? _previewOriginalId;

  String get selectedPaletteId => _selectedPaletteId;
  AppPalette get selectedPalette => AppPalette.byId(_selectedPaletteId);
  bool get darkMode => _darkMode;

  void previewPalette(String id) {
    if (!AppPalette.all.any((palette) => palette.id == id)) return;
    _previewOriginalId ??= _selectedPaletteId;
    if (_selectedPaletteId == id) return;
    _selectedPaletteId = id;
    notifyListeners();
  }

  void applyPalette(String id) {
    if (!AppPalette.all.any((palette) => palette.id == id)) return;
    _previewOriginalId = null;
    _selectedPaletteId = id;
    if (_store.d['palette'] == id) {
      notifyListeners();
      return;
    }
    _store.d['palette'] = id;
    _store.save();
  }

  void cancelPalettePreview() {
    final previous = _previewOriginalId;
    _previewOriginalId = null;
    if (previous == null || previous == _selectedPaletteId) return;
    _selectedPaletteId = previous;
    notifyListeners();
  }

  void resetToDefault() => previewPalette(AppPalette.teal.id);

  void setDarkMode(bool enabled) {
    if (_store.d['dark'] == enabled) return;
    _store.d['dark'] = enabled;
    _store.save();
  }

  void loadFromStore() {
    _readStore();
    notifyListeners();
  }

  void _storeChanged() {
    final oldId = _selectedPaletteId;
    final oldDark = _darkMode;
    _darkMode = _store.d['dark'] == true;
    if (_previewOriginalId == null) {
      _selectedPaletteId = _savedPalette().id;
    }
    if (oldId != _selectedPaletteId || oldDark != _darkMode) {
      notifyListeners();
    }
  }

  void _readStore() {
    _darkMode = _store.d['dark'] == true;
    _selectedPaletteId = _savedPalette().id;
  }

  AppPalette _savedPalette() {
    final id = _store.d['palette'];
    return AppPalette.byId(id is String ? id : null);
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    super.dispose();
  }
}

final themeController = ThemeController(store);
