import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/library_seats.dart';
import '../platform/library_seat_reader.dart';

enum LibrarySubmissionKind {
  confirmed,
  submittedUnverified,
  availabilityChanged,
  rejected,
  webRequired,
  precheckFailed,
  authInterrupted,
  uncertain,
}

class LibrarySubmissionState {
  const LibrarySubmissionState({
    required this.kind,
    required this.request,
    this.booking,
    this.bookingId = '',
    this.message = '',
    this.reason = '',
  });

  final LibrarySubmissionKind kind;
  final LibraryBookingRequest request;
  final LibraryBooking? booking;
  final String bookingId;
  final String message;
  final String reason;
}

class LibrarySeatQueries extends ChangeNotifier {
  LibrarySeatQueries(this._reader);

  final LibrarySeatReader _reader;
  int _revision = 0;
  bool _disposed = false;
  bool loading = false,
      submitting = false,
      needsLogin = false,
      failed = false,
      sessionCleared = false;
  List<LibraryArea>? areas;
  List<LibrarySeat>? seats;
  LibraryBookingPage? bookings;
  LibrarySubmissionState? submission;

  void _handleError(Object error) {
    needsLogin = error == LibraryReadFailure.login;
    failed = !needsLogin;
    if (needsLogin) {
      areas = null;
      seats = null;
      bookings = null;
    }
  }

  void clearSubmission() {
    if (submission == null || _disposed) return;
    submission = null;
    notifyListeners();
  }

  Future<void> _run<T>(
    Future<T> Function() read,
    void Function(T) accept,
  ) async {
    if (_disposed || submitting) return;
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
    if (_disposed || submitting) return null;
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
    if (_disposed || submitting) return Future<void>.value();
    seats = null;
    return _run(() => _reader.seats(area, date), (value) => seats = value);
  }

  Future<void> loadBookings(DateTime begin, DateTime end, int page) {
    if (_disposed || submitting) return Future<void>.value();
    bookings = null;
    return _run(
      () => _reader.bookings(begin, end, page),
      (value) => bookings = value,
    );
  }

  Future<void> _bestEffortRefreshSeats(
    LibraryBookingRequest request,
    int revision,
  ) async {
    try {
      final refreshed = await _reader.seats(request.areaId, request.date);
      if (revision == _revision && !_disposed) seats = refreshed;
    } catch (_) {}
  }

  Future<LibrarySubmissionState?> submitReservation(
    LibraryBookingRequest request,
  ) async {
    if (_disposed || submitting) return null;
    final revision = ++_revision;
    sessionCleared = false;
    loading = false;
    submitting = true;
    failed = false;
    needsLogin = false;
    submission = null;
    if (!_disposed) notifyListeners();
    try {
      List<LibrarySeat> latestSeats;
      try {
        latestSeats = await _reader.seats(request.areaId, request.date);
      } catch (error) {
        if (revision != _revision || _disposed) return null;
        if (error == LibraryReadFailure.login) {
          _handleError(LibraryReadFailure.login);
          submission = LibrarySubmissionState(
            kind: LibrarySubmissionKind.authInterrupted,
            request: request,
          );
        } else {
          submission = LibrarySubmissionState(
            kind: LibrarySubmissionKind.precheckFailed,
            request: request,
          );
        }
        return submission;
      }
      if (revision != _revision || _disposed) return null;
      seats = latestSeats;
      final target = latestSeats
          .where((seat) => seat.id == request.seatId)
          .firstOrNull;
      if (target == null ||
          target.statusOn(
                request.date,
                request.startMinutes,
                request.endMinutes,
              ) !=
              LibrarySeatStatus.available) {
        submission = LibrarySubmissionState(
          kind: LibrarySubmissionKind.availabilityChanged,
          request: request,
        );
        return submission;
      }

      LibraryWriteResult write;
      try {
        write = await _reader.reserve(
          seatId: request.seatId,
          date: request.date,
          startMinutes: request.startMinutes,
          endMinutes: request.endMinutes,
        );
      } catch (_) {
        if (revision != _revision || _disposed) return null;
        submission = LibrarySubmissionState(
          kind: LibrarySubmissionKind.uncertain,
          request: request,
        );
        return submission;
      }
      if (revision != _revision || _disposed) return null;

      switch (write.status) {
        case LibraryWriteStatus.ok:
          try {
            final page = await _reader.bookings(
              request.weekBegin,
              request.weekEnd,
              1,
            );
            if (revision != _revision || _disposed) return null;
            bookings = page;
            final matched = page.rows
                .where(
                  (row) =>
                      request.matchesBooking(row, bookingId: write.bookingId),
                )
                .firstOrNull;
            if (matched != null) {
              submission = LibrarySubmissionState(
                kind: LibrarySubmissionKind.confirmed,
                request: request,
                booking: matched,
                bookingId: write.bookingId,
                message: write.message,
              );
              await _bestEffortRefreshSeats(request, revision);
            } else {
              submission = LibrarySubmissionState(
                kind: LibrarySubmissionKind.submittedUnverified,
                request: request,
                bookingId: write.bookingId,
                message: write.message,
              );
            }
          } catch (error) {
            if (revision != _revision || _disposed) return null;
            if (error == LibraryReadFailure.login) {
              _handleError(LibraryReadFailure.login);
            }
            submission = LibrarySubmissionState(
              kind: LibrarySubmissionKind.submittedUnverified,
              request: request,
              bookingId: write.bookingId,
              message: write.message,
            );
          }
        case LibraryWriteStatus.rejected:
          submission = LibrarySubmissionState(
            kind: LibrarySubmissionKind.rejected,
            request: request,
            message: write.message,
          );
          await _bestEffortRefreshSeats(request, revision);
        case LibraryWriteStatus.webRequired:
          submission = LibrarySubmissionState(
            kind: LibrarySubmissionKind.webRequired,
            request: request,
            reason: write.reason,
          );
        case LibraryWriteStatus.precheckFailed:
          submission = LibrarySubmissionState(
            kind: LibrarySubmissionKind.precheckFailed,
            request: request,
          );
        case LibraryWriteStatus.login:
          _handleError(LibraryReadFailure.login);
          submission = LibrarySubmissionState(
            kind: LibrarySubmissionKind.authInterrupted,
            request: request,
          );
        case LibraryWriteStatus.uncertain:
          submission = LibrarySubmissionState(
            kind: LibrarySubmissionKind.uncertain,
            request: request,
          );
      }
      return submission;
    } finally {
      if (revision == _revision) {
        submitting = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> clearSession() async {
    _revision++;
    areas = null;
    seats = null;
    bookings = null;
    submission = null;
    loading = false;
    submitting = false;
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
