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
    if (_store.d['dark'] == enabled && _darkMode == enabled) return;
    _store.d['dark'] = enabled;
    _darkMode = enabled;
    _store.save();
  }

  void loadFromStore() {
    _readStore();
    notifyListeners();
  }

  void _storeChanged() {
    final oldId = _selectedPaletteId;
    final oldDark = _darkMode;
    _darkMode = _savedDarkMode();
    if (_previewOriginalId == null) {
      _selectedPaletteId = _savedPalette().id;
    }
    if (oldId != _selectedPaletteId || oldDark != _darkMode) {
      notifyListeners();
    }
  }

  void _readStore() {
    _darkMode = _savedDarkMode();
    _selectedPaletteId = _savedPalette().id;
  }

  bool _savedDarkMode() {
    return _store.d['dark'] == true;
  }

  AppPalette _savedPalette() {
    final id = _store.d['palette'];
    final palette = AppPalette.byId(id is String ? id : null);
    if (id is String && id != palette.id) {
      final updateStore = _store.d['palette'] != palette.id;
      _store.d['palette'] = palette.id;
      if (updateStore) _store.save();
    }
    return palette;
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    super.dispose();
  }
}

final themeController = ThemeController(store);
