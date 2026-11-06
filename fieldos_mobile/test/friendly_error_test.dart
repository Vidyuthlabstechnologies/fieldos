import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart' as sb;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/services/bug_report_service.dart';

void main() {
  group('friendlyError never shows raw server or exception text', () {
    test('no connection, however it arrives', () {
      expect(friendlyError(const SocketException('Failed host lookup')), offlineMessage);
      expect(friendlyError(sb.AuthRetryableFetchException(message: 'ClientException with SocketException: x')),
          offlineMessage);
      expect(friendlyError(Exception('ClientException: Connection closed before full header was received')),
          offlineMessage);
    });

    test('the cloud failing (5xx) is not called "no internet", and its HTML body is not shown', () {
      final m = friendlyError(sb.AuthRetryableFetchException(message: '<html>502 Bad Gateway</html>', statusCode: '502'));
      expect(m, contains('not answering'));
      expect(m, isNot(contains('<html>')));
    });

    test('Supabase Auth codes become sentences', () {
      expect(friendlyError(const sb.AuthApiException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired')),
          contains('code is not right'));
      expect(friendlyError(const sb.AuthApiException('Email rate limit exceeded', statusCode: '429', code: 'over_email_send_rate_limit')),
          contains('Too many tries'));
      expect(friendlyError(const sb.AuthApiException('Invalid Refresh Token', statusCode: '400', code: 'refresh_token_not_found')),
          contains('Sign in again'));
      // A short message written for people still comes through.
      expect(friendlyError(const sb.AuthApiException('password is too short', statusCode: '422')), 'Password is too short.');
    });

    test('our RPC messages are reworded; raw SQL and RLS text never are', () {
      expect(friendlyError(const sb.PostgrestException(message: 'invalid join code', code: 'P0002')),
          contains('join code is not right'));
      final rls = friendlyError(const sb.PostgrestException(
          message: 'new row violates row-level security policy for table "projects"', code: '42501'));
      expect(rls, isNot(contains('row-level')));
      expect(rls, contains('role'));
      final sql = friendlyError(const sb.PostgrestException(message: 'column x does not exist', code: '42703'));
      expect(sql, startsWith('Something went wrong'));
    });

    test('anything unexpected is a plain sentence and is kept for the bug report', () {
      final before = RecentErrors.dump();
      final m = friendlyError(StateError('Bad state: no element'), StackTrace.current);
      expect(m, startsWith('Something went wrong'));
      expect(RecentErrors.dump(), isNot(before));
      expect(friendlyError(TimeoutException('x')), contains('took too long'));
    });
  });

  group('format helpers', () {
    test('rupees: Indian grouping, paise only when asked and present', () {
      expect(rupees(0), '₹0');
      expect(rupees(999), '₹999');
      expect(rupees(1234567), '₹12,34,567');
      expect(rupees(-25000), '-₹25,000');
      expect(rupees(45.5), '₹46');
      expect(rupees(45.5, paise: true), '₹45.50');
      expect(rupees(1200, paise: true), '₹1,200');
      expect(rupees(100000.05, paise: true), '₹1,00,000.05');
    });

    test('quantities lose their trailing .0', () {
      expect(fmtQty(50.0), '50');
      expect(fmtQty(12.5), '12.5');
      expect(fmtQty(0.125), '0.125');
    });

    test('hours on site and same-day checks', () {
      expect(fmtHours(const Duration(hours: 9, minutes: 5)), '9 h 05 min');
      expect(fmtHours(const Duration(minutes: 45)), '45 min');
      expect(isSameDay(DateTime(2026, 11, 6, 0, 1), DateTime(2026, 11, 6, 23, 59)), isTrue);
      expect(isSameDay(DateTime(2026, 11, 6, 23, 59), DateTime(2026, 11, 7)), isFalse);
    });
  });
}
