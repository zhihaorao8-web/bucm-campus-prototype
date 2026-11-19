import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/library_seats.dart';
import '../platform/library_seat_reader.dart';

class LibrarySeatQueries extends ChangeNotifier {
  LibrarySeatQueries(this._reader);

  final LibrarySeatReader _reader;
  int _revision = 0;
  bool _disposed = false;
  bool loading = false,
      needsLogin = false,
      failed = false,
      sessionCleared = false;
  List<LibraryArea>? areas;
  List<LibrarySeat>? seats;
  LibraryBookingPage? bookings;

  void _handleError(Object error) {
    needsLogin = error == LibraryReadFailure.login;
    failed = !needsLogin;
    if (needsLogin) {
      areas = null;
      seats = null;
      bookings = null;
    }
  }

  Future<void> _run<T>(
    Future<T> Function() read,
    void Function(T) accept,
  ) async {
    final revision = ++_revision;
    sessionCleared = false;
    loading = true;
    failed = false;
    needsLogin = false;
    if (!_disposed) notifyListeners();
    try {
      final result = await read();
      if (revision == _revision) accept(result);
    } catch (error) {
      if (revision != _revision) return;
      _handleError(error);
    } finally {
      if (revision == _revision) {
        loading = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<LibraryArea?> loadAreaSeats({
    String? preferredAreaId,
    required DateTime date,
  }) async {
    final revision = ++_revision;
    sessionCleared = false;
    loading = true;
    failed = false;
    needsLogin = false;
    seats = null;
    if (!_disposed) notifyListeners();
    try {
      var areaList = areas;
      if (areaList == null) {
        final loadedAreas = await _reader.areas();
        if (revision != _revision) return null;
        areaList = loadedAreas;
        areas = areaList;
      }
      if (areaList.isEmpty) return null;
      final selectedArea = preferredAreaId == null
          ? areaList.first
          : areaList.firstWhere(
              (a) => a.id == preferredAreaId,
              orElse: () => areaList!.first,
            );
      final loadedSeats = await _reader.seats(selectedArea.id, date);
      if (revision != _revision) return null;
      seats = loadedSeats;
      return selectedArea;
    } catch (error) {
      if (revision != _revision) return null;
      _handleError(error);
      return null;
    } finally {
      if (revision == _revision) {
        loading = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> loadAreas() => _run(_reader.areas, (value) => areas = value);

  Future<void> loadSeats(String area, DateTime date) {
    seats = null;
    return _run(() => _reader.seats(area, date), (value) => seats = value);
  }

  Future<void> loadBookings(DateTime begin, DateTime end, int page) {
    bookings = null;
    return _run(
      () => _reader.bookings(begin, end, page),
      (value) => bookings = value,
    );
  }

  Future<void> clearSession() async {
    _revision++;
    areas = null;
    seats = null;
    bookings = null;
    loading = false;
    failed = false;
    needsLogin = false;
    sessionCleared = true;
    if (!_disposed) notifyListeners();
    await _reader.reset();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(clearSession());
    super.dispose();
  }
}
