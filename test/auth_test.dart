import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_kb/app.dart';
import 'package:northstar_kb/data/auth_flow.dart';
import 'package:northstar_kb/data/connection.dart';
import 'package:northstar_kb/data/knowledge_repository.dart';
import 'package:northstar_kb/data/session.dart';
import 'package:northstar_kb/data/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_liferay.dart';

void main() {
  late FakeLiferay liferay;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    liferay = FakeLiferay();
  });

  Future<Set<String>> cacheKeys() async =>
      (await SharedPreferences.getInstance())
          .getKeys()
          .where((k) => k.startsWith('kb.'))
          .toSet();

  group('PKCE', () {
    test('S256 challenge matches RFC 7636 appendix B', () {
      expect(
        AuthFlow.codeChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('verifier: 64 unreserved characters, random', () {
      final a = AuthFlow.randomString(64), b = AuthFlow.randomString(64);
      expect(a, hasLength(64));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(a), isTrue);
      expect(a, isNot(b));
    });
  });

  test('session identity comes from the JWT access token', () {
    const jwt =
        'eyJhbGciOiJub25lIn0.eyJzdWIiOiI0MiIsInVzZXJuYW1lIjoiZm9vIn0.sig';
    final s = Session.fromTokenResponse({
      'access_token': jwt,
      'refresh_token': 'r',
      'expires_in': 600,
    });
    expect(s.userId, '42');
    expect(s.userName, 'foo');
    expect(s.isExpired, isFalse);
    expect(jwtClaims('not-a-jwt'), isEmpty);
  });

  test('nobody signed in: nothing loaded, no call to Liferay', () async {
    final r = liferay.userRepository();
    expect(r.requiresSignIn, isTrue);
    expect(r.ownerKey, isNull);
    expect(await r.sync(), isNull);
    expect(r.state, SyncState.signedOut);
    expect(liferay.requests, isEmpty);
  });

  test(
    'sign-in exchanges the code (PKCE) and loads the user content',
    () async {
      final r = liferay.userRepository();
      await r.signIn();
      expect(r.session!.userName, 'alice');
      expect(r.requiresSignIn, isFalse);
      expect(r.totalCount, 3);
      expect(liferay.requests.first, contains('/o/oauth2/token'));
    },
  );

  test('offline copies are separated by user (permissions)', () async {
    // Alice may see the known issues.
    final alice = liferay.userRepository();
    await alice.signIn();
    expect(alice.byErc('KI-NX400-004'), isNotNull);
    final aliceKeys = await cacheKeys();
    expect(aliceKeys, isNotEmpty);

    // Bob may not. Same device, Alice's session simply lost (not signed out).
    final bob = liferay.userRepository(code: 'code-bob');
    await bob.signIn();
    expect(bob.session!.userName, 'bob');
    expect(
      bob.byErc('KI-NX400-004'),
      isNull,
      reason: 'never served from Alice\'s cache',
    );
    expect(bob.totalCount, 2);
    expect(bob.ownerKey, isNot(alice.ownerKey));
    // Different namespaces, Alice's copy is untouched.
    expect((await cacheKeys()).containsAll(aliceKeys), isTrue);

    // Signing out deletes the user's own offline copy only.
    await bob.signOut();
    expect(bob.totalCount, 0);
    expect(bob.state, SyncState.signedOut);
    expect(await cacheKeys(), aliceKeys);
  });

  test('expired access token is refreshed with the refresh token', () async {
    liferay.userTokenSeconds = 0; // every access token is already expired
    final r = liferay.userRepository();
    await r.signIn();
    expect(r.totalCount, 3);
    expect(liferay.refreshCount, greaterThan(0));
    expect(r.session, isNotNull);
  });

  test(
    'revoked session: content hidden, back after signing in again',
    () async {
      final r = liferay.userRepository();
      await r.signIn();
      liferay
        ..userTokenSeconds = 0
        ..revokedRefresh = true;
      await r.signIn(); // new short-lived token
      liferay.revokedRefresh = true;
      await r.sync();
      expect(r.state, SyncState.signedOut);
      expect(r.requiresSignIn, isTrue);
      expect(r.totalCount, 0, reason: 'no content shown without a session');
      expect(
        await cacheKeys(),
        isNotEmpty,
        reason: 'offline copy kept on disk',
      );

      liferay
        ..revokedRefresh = false
        ..userTokenSeconds = 600;
      await r.signIn();
      expect(r.totalCount, 3);
    },
  );

  test('stored session is bound to its connection', () async {
    final conn = Connection(
      liferayUrl: 'https://liferay.test',
      clientId: 'public-client',
    );
    final session = Session(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      userId: '101',
      userName: 'alice',
    );
    await SessionStore.save(
      conn.copyWith(serviceClientId: 'svc', serviceClientSecret: 'TOP-SECRET'),
      session,
    );
    final stored = (await SharedPreferences.getInstance()).getString(
      'auth.session',
    )!;
    expect(
      stored,
      isNot(contains('TOP-SECRET')),
      reason: 'no client secret stored with the session',
    );
    expect((await SessionStore.load(conn))!.userName, 'alice');
    expect(await SessionStore.load(conn.copyWith(clientId: 'other')), isNull);
    expect(await SessionStore.load(conn.copyWith(spaceErc: 'OTHER')), isNull);
    await SessionStore.save(conn, null);
    expect(await SessionStore.load(conn), isNull);
  });

  testWidgets('login gate: deep links lead to the login page first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2400);
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/entry/KB-NX400-014';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final r = liferay.userRepository();
    await tester.pumpWidget(KnowledgeApp(repository: r));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Liferay'), findsOneWidget);
    expect(find.text('OCPP Connection Failure (E217)'), findsNothing);

    await tester.tap(find.text('Sign in with Liferay'));
    await tester.pumpAndSettle();
    expect(find.text('Northstar Enterprise Knowledge'), findsOneWidget);
    expect(find.textContaining('3 contents'), findsOneWidget);

    // Visible on the home page: who is signed in, and a Sign out button.
    expect(find.text('Signed in as alice'), findsOneWidget);

    // Also in the connection settings.
    await tester.tap(find.byTooltip('Account: alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liferay connection'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as alice'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Sign out asks for confirmation (cancel keeps the session)...
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(r.session, isNotNull);

    // ...then signs out, deletes the offline copy, back to the login page.
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Liferay'), findsOneWidget);
    expect(r.session, isNull);
    expect(await cacheKeys(), isEmpty);
  });
}
