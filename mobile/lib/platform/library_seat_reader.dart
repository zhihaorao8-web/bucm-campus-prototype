import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/network_policy.dart';
import '../domain/library_seats.dart';
import '../domain/schedule.dart';
import 'campus_login_navigation.dart';
import 'library_seat_navigation.dart';
import 'school_adapter.dart';

enum LibraryReadFailure { login, unavailable }

enum LibraryWriteStatus {
  ok,
  rejected,
  login,
  webRequired,
  notEligible,
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
  HeadlessInAppWebView? _reuseView;
  Completer<bool>? _reuseDone;
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

  Future<bool> tryReuseCampusSession() async {
    await reset();
    final revision = SchoolAdapter.sessionChanges.value;
    final done = Completer<bool>();
    Timer? poll;
    var document = 0;
    HeadlessInAppWebView? view;

    void finish(bool value) {
      poll?.cancel();
      if (!done.isCompleted) done.complete(value);
    }

    void sessionChanged() {
      if (identical(_reuseDone, done)) finish(false);
    }

    Future<void> inspectSeatMenu(
      InAppWebViewController web,
      HeadlessInAppWebView owner,
      int doc,
    ) async {
      if (!identical(_reuseView, owner) ||
          done.isCompleted ||
          doc != document ||
          revision != SchoolAdapter.sessionChanges.value) {
        return;
      }
      var ready = false;
      try {
        final response = await web
            .callAsyncJavaScript(
              functionBody: CampusLoginTarget.library.readinessScript,
            )
            .timeout(CampusLoginPolicy.asyncReadinessTimeout);
        ready = response?.error == null && response?.value == true;
      } catch (_) {
        ready = false;
      }
      if (!identical(_reuseView, owner) ||
          done.isCompleted ||
          doc != document ||
          revision != SchoolAdapter.sessionChanges.value) {
        return;
      }
      if (ready) {
        finish(true);
        return;
      }
      poll?.cancel();
      poll = Timer(
        const Duration(milliseconds: 500),
        () => unawaited(inspectSeatMenu(web, owner, doc)),
      );
    }

    void handleLoaded(
      InAppWebViewController web,
      WebUri? url,
      HeadlessInAppWebView owner,
    ) {
      if (!identical(_reuseView, owner) || done.isCompleted) return;
      final address = url?.toString();
      // Only treat committed CAS form documents as unauthenticated, never 302 redirects.
      if (campusCasForm(address)) {
        finish(false);
        return;
      }
      if (librarySeatPage(address)) {
        final doc = ++document;
        unawaited(inspectSeatMenu(web, owner, doc));
      }
    }

    SchoolAdapter.sessionChanges.addListener(sessionChanged);
    _reuseDone = done;
    try {
      view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(SchoolEndpoints.librarySeatHome),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          useShouldOverrideUrlLoading: true,
          supportMultipleWindows: true,
          allowFileAccess: false,
          allowContentAccess: false,
          thirdPartyCookiesEnabled: false,
          cacheEnabled: false,
          saveFormData: false,
          isInspectable: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
        ),
        shouldOverrideUrlLoading: (_, action) async {
          if (librarySeatNavigation(action.request.url?.toString())) {
            return NavigationActionPolicy.ALLOW;
          }
          if (action.isForMainFrame) finish(false);
          return NavigationActionPolicy.CANCEL;
        },
        onCreateWindow: (_, _) async => false,
        onReceivedServerTrustAuthRequest: (_, _) async {
          finish(false);
          return ServerTrustAuthResponse(
            action: ServerTrustAuthResponseAction.CANCEL,
          );
        },
        onPermissionRequest: (_, request) async => PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.DENY,
        ),
        onLoadStart: (_, url) {
          if (!librarySeatNavigation(url?.toString())) {
            finish(false);
            return;
          }
          document++;
          poll?.cancel();
        },
        onPageCommitVisible: (web, url) => handleLoaded(web, url, view!),
        onLoadStop: (web, url) => handleLoaded(web, url, view!),
        onReceivedError: (_, request, _) {
          if (request.isForMainFrame == true) finish(false);
        },
        onReceivedHttpError: (_, request, _) {
          if (request.isForMainFrame == true) finish(false);
        },
      );
      _reuseView = view;
      if (revision != SchoolAdapter.sessionChanges.value) return false;
      await view.run();
      if (!identical(_reuseView, view) ||
          revision != SchoolAdapter.sessionChanges.value) {
        return false;
      }
      return await done.future.timeout(
        LibrarySeatPolicy.sessionReuseTimeout,
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    } finally {
      SchoolAdapter.sessionChanges.removeListener(sessionChanged);
      poll?.cancel();
      if (!done.isCompleted) done.complete(false);
      if (identical(_reuseDone, done)) _reuseDone = null;
      if (identical(_reuseView, view)) _reuseView = null;
      try {
        await view?.dispose();
      } catch (_) {}
    }
  }

  Future<void> reset() async {
    final view = _view;
    final reuseView = _reuseView;
    final reuseDone = _reuseDone;
    _view = null;
    _opening = null;
    _reuseView = null;
    _reuseDone = null;
    if (reuseDone != null && !reuseDone.isCompleted) {
      reuseDone.complete(false);
    }
    await Future.wait<void>([
      if (view != null) view.dispose(),
      if (reuseView != null) reuseView.dispose(),
    ]);
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
  }) => _write({
    'action': 'reserve',
    'seat': seatId,
    'date': isoDate(date),
    'start': formatClockMinutes(startMinutes),
    'end': formatClockMinutes(endMinutes),
  });

  Future<LibraryWriteResult> cancelBooking(
    LibraryBooking booking,
    DateTime begin,
    DateTime end,
    int page,
  ) => _write({
    'action': 'cancel',
    'bookingId': booking.id,
    'seatLabel': booking.seat,
    'beginAt': booking.begin,
    'endAt': booking.end,
    'begin': isoDate(begin),
    'end': isoDate(end),
    'page': page,
  });

  Future<LibraryWriteResult> _write(Map<String, Object> command) async {
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
      final body = _scriptWithCommand(src, command);
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
        case 'not_eligible':
          return const LibraryWriteResult(LibraryWriteStatus.notEligible);
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
