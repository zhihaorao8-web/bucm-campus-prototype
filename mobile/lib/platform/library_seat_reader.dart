import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/network_policy.dart';
import '../domain/library_seats.dart';
import '../domain/schedule.dart';

enum LibraryReadFailure { login, unavailable }

enum LibraryWriteStatus {
  ok,
  rejected,
  login,
  webRequired,
  precheckFailed,
  uncertain,
}

class LibraryWriteResult {
  const LibraryWriteResult(
    this.status, {
    this.bookingId = '',
    this.message = '',
    this.reason = '',
  });

  final LibraryWriteStatus status;
  final String bookingId;
  final String message;
  final String reason;
}

class LibrarySeatReader {
  HeadlessInAppWebView? _view;
  Future<InAppWebViewController?>? _opening;
  static const _document = '$_origin$_path';
  static const _origin = LibrarySeatPolicy.origin;
  static const _path = LibrarySeatPolicy.document;

  Future<InAppWebViewController?> _open() async {
    final ready = Completer<InAppWebViewController?>();
    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_document)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        allowContentAccess: false,
        allowFileAccess: false,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: true,
        thirdPartyCookiesEnabled: false,
        isInspectable: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      ),
      shouldOverrideUrlLoading: (_, request) async =>
          request.request.url?.toString() == _document
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
      onCreateWindow: (_, _) async => false,
      onLoadStop: (web, url) {
        if (!ready.isCompleted) {
          ready.complete(url?.toString() == _document ? web : null);
        }
      },
      onReceivedError: (_, request, _) {
        if (request.isForMainFrame == true && !ready.isCompleted) {
          ready.complete(null);
        }
      },
      onReceivedHttpError: (_, request, _) {
        if (request.isForMainFrame == true && !ready.isCompleted) {
          ready.complete(null);
        }
      },
      onReceivedServerTrustAuthRequest: (_, _) async =>
          ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.CANCEL),
    );
    _view = view;
    await view.run();
    if (!identical(_view, view)) {
      await view.dispose();
      return null;
    }
    final web = await ready.future.timeout(LibrarySeatPolicy.timeout);
    return identical(_view, view) ? web : null;
  }

  Future<void> reset() async {
    final view = _view;
    _view = null;
    _opening = null;
    await view?.dispose();
  }

  Future<Map<String, dynamic>> _read(Map<String, Object> job) async {
    final opening = _opening ??= _open();
    final web = await opening.catchError((Object _) => null);
    if (web == null || !identical(_opening, opening)) {
      if (identical(_opening, opening)) await reset();
      throw LibraryReadFailure.unavailable;
    }
    try {
      final src = await rootBundle.loadString(LibrarySeatPolicy.readAsset);
      if (!identical(_opening, opening)) throw LibraryReadFailure.unavailable;
      final response = await web
          .callAsyncJavaScript(
            functionBody: _scriptWithCommand(src, job),
          )
          .timeout(LibrarySeatPolicy.timeout + const Duration(seconds: 2));
      final value = response?.value;
      if (!identical(_opening, opening) ||
          response?.error != null ||
          value is! String ||
          value.length > LibrarySeatPolicy.maxBodyBytes) {
        throw LibraryReadFailure.unavailable;
      }
      final payload = jsonDecode(value) as Map<String, dynamic>;
      switch (payload['status']) {
        case 'ok':
          return payload;
        case 'login':
          throw LibraryReadFailure.login;
        default:
          throw LibraryReadFailure.unavailable;
      }
    } on LibraryReadFailure catch (failure) {
      if (failure != LibraryReadFailure.login && identical(_opening, opening)) {
        await reset();
      }
      rethrow;
    } catch (_) {
      if (identical(_opening, opening)) await reset();
      throw LibraryReadFailure.unavailable;
    }
  }

  String _scriptWithCommand(String src, Map<String, Object> job) => src
      .replaceFirst('__LIBRARY_SEAT_COMMAND__', jsonEncode(job))
      .replaceFirst(
        '__LIBRARY_SEAT_CONFIG__',
        jsonEncode({
          'origin': _origin,
          'document': _path,
          'bookingPageSize': LibrarySeatPolicy.bookingPageSize,
          'bookingStatusFilter': LibrarySeatPolicy.bookingStatusFilter,
          'timeout': LibrarySeatPolicy.timeout.inMilliseconds,
          'maxRows': LibrarySeatPolicy.maxRows,
          'maxBodyBytes': LibrarySeatPolicy.maxBodyBytes,
        }),
      );

  Future<LibraryWriteResult> reserve({
    required String seatId,
    required DateTime date,
    required int startMinutes,
    required int endMinutes,
  }) async {
    final opening = _opening ??= _open();
    final web = await opening.catchError((Object _) => null);
    if (web == null || !identical(_opening, opening)) {
      if (identical(_opening, opening)) await reset();
      return const LibraryWriteResult(LibraryWriteStatus.precheckFailed);
    }
    var invoked = false;
    try {
      final src = await rootBundle.loadString(LibrarySeatPolicy.writeAsset);
      if (!identical(_opening, opening)) {
        return const LibraryWriteResult(LibraryWriteStatus.precheckFailed);
      }
      final body = _scriptWithCommand(src, {
        'action': 'reserve',
        'seat': seatId,
        'date': isoDate(date),
        'start': formatClockMinutes(startMinutes),
        'end': formatClockMinutes(endMinutes),
      });
      invoked = true;
      final response = await web
          .callAsyncJavaScript(functionBody: body)
          .timeout(LibrarySeatPolicy.timeout + const Duration(seconds: 2));
      final value = response?.value;
      if (!identical(_opening, opening) ||
          response?.error != null ||
          value is! String ||
          value.length > LibrarySeatPolicy.maxBodyBytes) {
        if (identical(_opening, opening)) await reset();
        return const LibraryWriteResult(LibraryWriteStatus.uncertain);
      }
      final payload = jsonDecode(value) as Map<String, dynamic>;
      String field(String key) => payload[key] is String ? payload[key] as String : '';
      switch (payload['status']) {
        case 'ok':
          return LibraryWriteResult(
            LibraryWriteStatus.ok,
            bookingId: field('bookingId'),
            message: field('message'),
          );
        case 'rejected':
          return LibraryWriteResult(
            LibraryWriteStatus.rejected,
            message: field('message'),
          );
        case 'login':
          return const LibraryWriteResult(LibraryWriteStatus.login);
        case 'web_required':
          return LibraryWriteResult(
            LibraryWriteStatus.webRequired,
            reason: field('reason'),
          );
        case 'precheck_error':
          return const LibraryWriteResult(LibraryWriteStatus.precheckFailed);
        default:
          if (identical(_opening, opening)) await reset();
          return const LibraryWriteResult(LibraryWriteStatus.uncertain);
      }
    } catch (_) {
      if (identical(_opening, opening)) await reset();
      return LibraryWriteResult(
        invoked ? LibraryWriteStatus.uncertain : LibraryWriteStatus.precheckFailed,
      );
    }
  }

  Future<List<LibraryArea>> areas() async => _rows(
    await _read({'action': 'areas'}),
    LibraryArea.fromJson,
    (area) => area.id,
  );

  Future<List<LibrarySeat>> seats(String area, DateTime date) async => _rows(
    await _read({'action': 'seats', 'area': area, 'date': isoDate(date)}),
    LibrarySeat.fromJson,
    (seat) => seat.id,
  );

  Future<LibraryBookingPage> bookings(
    DateTime begin,
    DateTime end,
    int page,
  ) async {
    final payload = await _read({
      'action': 'bookings',
      'begin': isoDate(begin),
      'end': isoDate(end),
      'page': page,
    });
    final count = payload['count'];
    if (count is! int) throw LibraryReadFailure.unavailable;
    return LibraryBookingPage(
      _rows(payload, LibraryBooking.fromJson, (booking) => booking.id),
      count > page * LibrarySeatPolicy.bookingPageSize,
      page: page,
      totalCount: count,
    );
  }

  List<T> _rows<T>(
    Map<String, dynamic> payload,
    T Function(Map<String, dynamic>) parse,
    String Function(T) id,
  ) {
    try {
      final rows = (payload['rows'] as List)
          .cast<Map<String, dynamic>>()
          .map(parse)
          .toList();
      if (rows.length > LibrarySeatPolicy.maxRows ||
          rows.map(id).toSet().length != rows.length) {
        throw LibraryReadFailure.unavailable;
      }
      return List.unmodifiable(rows);
    } catch (_) {
      throw LibraryReadFailure.unavailable;
    }
  }
}
