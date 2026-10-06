import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Port of `src/context/HotelContext.tsx`.
///
/// Laundry records carry a `client_name` rather than a dedicated hotel field,
/// so the hotel list is derived from the distinct client names across gate
/// passes, deliveries, bills and quotations. "All Hotels" (`''`) is admin-only;
/// a non-admin is always pinned to one hotel.
class HotelScope extends ChangeNotifier {
  HotelScope();

  static const _prefix = 'll_hotel_';

  final List<String> _hotels = [];
  String _selected = '';
  String? _userId;
  bool _restored = false;
  bool _isAdmin = false;

  /// Distinct client names, sorted. Populated by the app shell once the first
  /// operations payloads land.
  List<String> get hotels => List.unmodifiable(_hotels);

  String get selectedHotel => _selected;

  /// `true` when the admin is deliberately looking at every hotel at once.
  bool get showAllHotels => _isAdmin && _selected.isEmpty;

  bool get isAdmin => _isAdmin;
  bool get restored => _restored;

  /// The query parameter every operations list should send. `null` means
  /// "do not filter", which is what the admin's All Hotels view relies on.
  String? get queryParam => _selected.isEmpty ? null : _selected;

  String get storageKey => '$_prefix${_userId ?? ''}';

  /// Called on sign-in and whenever the user record changes.
  Future<void> bindUser(String? userId, bool isAdmin) async {
    if (_userId == userId && _isAdmin == isAdmin) return;
    _userId = userId;
    _isAdmin = isAdmin;
    final prefs = await SharedPreferences.getInstance();
    _selected = prefs.getString(storageKey) ?? '';
    _restored = true;
    _reconcile();
    notifyListeners();
  }

  /// Replaces the derived hotel list, then repairs the selection if the chosen
  /// hotel is no longer reachable.
  void setHotels(Iterable<String> names) {
    final set = <String>{};
    for (final n in names) {
      final trimmed = n.trim();
      if (trimmed.isNotEmpty) set.add(trimmed);
    }
    final sorted = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (_listEquals(_hotels, sorted)) return;
    _hotels
      ..clear()
      ..addAll(sorted);
    _reconcile();
    notifyListeners();
  }

  void _reconcile() {
    if (_hotels.isEmpty) return;
    if (_selected.isNotEmpty && _hotels.contains(_selected)) {
      if (_isAdmin) return;
      return;
    }
    if (!_isAdmin && _hotels.isNotEmpty) {
      _selected = _hotels.first;
    } else {
      _selected = '';
    }
    _persist();
  }

  Future<void> setSelectedHotel(String name) async {
    if (_selected == name) return;
    // A non-admin cannot widen the scope past their own hotel.
    if (!_isAdmin && name.isNotEmpty && !_hotels.contains(name)) return;
    _selected = name;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, _selected);
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
