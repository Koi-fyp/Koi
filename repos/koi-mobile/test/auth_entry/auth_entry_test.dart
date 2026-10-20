import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/account/account_auth_screen.dart';
import 'package:koi_mobile/account/account_gate_screens.dart';
import 'package:koi_mobile/account/account_widgets.dart' show KoiBackButton;
import 'package:koi_mobile/account/auth_entry_widgets.dart';
import 'package:koi_mobile/account/care_screen.dart';
import 'package:koi_mobile/app/root_router.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/chat/chat_screen.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/core/auth/auth_service.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/core/emotion.dart';
import 'package:koi_mobile/landing/landing_screen.dart';
import 'package:koi_mobile/safety_plan/safety_plan_models.dart';
import 'package:koi_mobile/safety_plan/safety_plan_providers.dart';
import 'package:koi_mobile/safety_plan/safety_plan_store.dart';
import 'package:koi_mobile/settings/settings_prefs.dart';
import 'package:koi_mobile/shell/app_shell.dart';
import 'package:koi_mobile/widgets/koi_loader.dart';

import '../support/mob1_fakes.dart';
import '../support/real_fonts.dart';

// AUTH-ENTRY: Sign in / Create account made visible (landing, anonymous
// Care tab, Settings card), friendly errors, reset, psychologist info.

const _anon = KoiUser(uid: 'a1', isAnonymous: true);

String en(CareText k) => CareStrings.en.t(k);

Finder _key(String k) => find.byKey(Key(k));

Finder _field(String k) =>
    find.descendant(of: _key(k), matching: find.byType(TextField));

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  List<Override> overrides, {
  double width = 360,
  double height = 800,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: RootRouter()),
    ),
  );
  await _settle(tester);
}

/// Scrolls [f] to the middle (clear of fixed navs), then taps it.
Future<void> _tap(WidgetTester tester, Finder f) async {
  Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await _settle(tester, 3);
  await tester.tap(f);
  await _settle(tester);
}

Finder _title(CareText k) => find.descendant(
  of: _key('account-title'),
  matching: find.text(en(k)),
  matchRoot: true,
);

/// The KOI Back button of the top page.
Future<void> _back(WidgetTester tester) async {
  await _tap(tester, find.byType(KoiBackButton).last);
}

Future<void> _openCare(WidgetTester tester) async {
  await tester.tap(_key('nav-tab-care'));
  await _settle(tester);
}

Future<void> _fill(
  WidgetTester tester, {
  required String email,
  required String password,
  String? confirm,
}) async {
  await tester.enterText(_field('account-email'), email);
  await tester.enterText(_field('account-password'), password);
  if (confirm != null) {
    await tester.enterText(_field('account-confirm'), confirm);
  }
}

Future<void> _submit(WidgetTester tester) =>
    _tap(tester, _key('account-submit'));

MessageRecord _msg(String id, String uid, String content) => MessageRecord(
  id: id,
  conversationId: uid,
  sender: 'user',
  content: content,
  timestamp: DateTime.utc(2026, 10, 20, 10),
  emotion: Emotion.neutral,
  emotionConfidence: 1,
  synced: false,
);

/// a1's anonymous history: one chat message, one check-in and a safety
/// plan, all encrypted with the anonymous secret.
Future<MemorySafetyPlanBox> _seedHistory(Mob1Harness h, String uid) async {
  final anon = await h.secrets.anonymousSecret(uid);
  await h.messages.put(
    _msg('m1', uid, await h.cipher.encrypt('my private words', anon, 's')),
  );
  await h.checkIns.put(
    '${uid}_2026-10-20_morning',
    jsonEncode({
      'id': '${uid}_2026-10-20_morning',
      'userId': uid,
      'kind': 'morning',
      'day': '2026-10-20',
      'timestamp': '2026-10-20T09:00:00.000',
      'synced': false,
      'payload': await h.cipher.encrypt('{"mood":3}', anon, 's'),
    }),
  );
  final plans = MemorySafetyPlanBox();
  await SafetyPlanRepository(
    box: plans,
    cipher: h.cipher,
    cryptoContext: (_) async => CryptoContext(secret: anon, saltB64: 's'),
  ).save(
    uid,
    SafetyPlan(
      items: {
        SafetyPlanSection.reasons: [
          SafetyPlanItem(id: 'r1', text: 'my private reason'),
        ],
      },
    ),
    DateTime.utc(2026, 10, 20),
  );
  return plans;
}

/// Records every HttpClient the app tries to create.
class _NoNetwork extends HttpOverrides {
  final List<String> created = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created.add('HttpClient');
    throw StateError('no network in this test');
  }
}

void main() {
  useRealFonts();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('AUTH-01..03 errors and strings', () {
    test('AUTH-01 every account error maps to a friendly line', () {
      const expected = {
        AccountAuthError.emailInUse: CareText.auErrEmailInUse,
        AccountAuthError.wrongCredentials: CareText.auErrWrong,
        AccountAuthError.accountNotFound: CareText.auErrNotFound,
        AccountAuthError.weakPassword: CareText.auErrWeak,
        AccountAuthError.invalidEmail: CareText.auErrInvalidEmail,
        AccountAuthError.network: CareText.auErrNetwork,
        AccountAuthError.tooManyRequests: CareText.auErrTooMany,
        AccountAuthError.requiresRecentLogin: CareText.auErrGeneric,
        AccountAuthError.notSupported: CareText.auErrNotAllowed,
        AccountAuthError.unknown: CareText.auErrGeneric,
      };
      expect(expected.keys.toSet(), AccountAuthError.values.toSet());
      for (final e in AccountAuthError.values) {
        expect(
          accountErrorKey(AccountAuthException(e)),
          expected[e],
          reason: e.name,
        );
      }
      expect(
        en(
          accountErrorKey(
            const AccountAuthException(AccountAuthError.notSupported),
          ),
        ),
        "Account sign-up isn't switched on yet. Please try again later.",
      );
      expect(
        accountErrorKey(
          const SaltFetchBlockedError(SaltBlockedReason.noNetwork),
        ),
        CareText.auErrSalt,
      );
      for (final raw in [
        Exception('[firebase_auth/operation-not-allowed] raw text'),
        StateError('No user'),
        'string error',
      ]) {
        final text = accountErrorText(raw);
        expect(text, en(CareText.auErrGeneric));
      }
      for (final e in AccountAuthError.values) {
        for (final s in [CareStrings.en, CareStrings.ur]) {
          final text = s.t(accountErrorKey(AccountAuthException(e)));
          for (final raw in ['firebase', 'auth/', 'Exception', e.name]) {
            expect(text.contains(raw), isFalse, reason: '$e: $text');
          }
        }
      }
    });

    test('AUTH-02 Firebase codes: not-found, not-allowed, wrong password', () {
      AccountAuthError of(String c) => AccountAuthError.fromFirebaseCode(c);
      expect(of('user-not-found'), AccountAuthError.accountNotFound);
      expect(of('wrong-password'), AccountAuthError.wrongCredentials);
      expect(of('invalid-credential'), AccountAuthError.wrongCredentials);
      expect(of('operation-not-allowed'), AccountAuthError.notSupported);
      expect(of('admin-restricted-operation'), AccountAuthError.notSupported);
      expect(of('email-already-in-use'), AccountAuthError.emailInUse);
      expect(of('weak-password'), AccountAuthError.weakPassword);
      expect(of('network-request-failed'), AccountAuthError.network);
      expect(of('something-new'), AccountAuthError.unknown);
    });

    test('AUTH-03 every AUTH text has English and Urdu', () {
      final keys = CareText.values.where((k) => k.name.startsWith('au'));
      expect(keys.length, greaterThanOrEqualTo(40));
      final arabicScript = RegExp(r'[؀-ۿ]');
      for (final k in keys) {
        final e = CareStrings.table(CareLang.en)[k];
        final u = CareStrings.table(CareLang.ur)[k];
        expect(e, isNotNull, reason: k.name);
        expect(e!.trim(), isNotEmpty, reason: k.name);
        expect(u, isNotNull, reason: k.name);
        expect(arabicScript.hasMatch(u!), isTrue, reason: k.name);
      }
      expect(en(CareText.auWhy), contains('connect with a psychologist'));
      expect(
        en(CareText.auPsychBody),
        'Psychologist accounts are created and verified on the KOI website.',
      );
    });
  });

  group('AUTH-04..06 landing (signed out)', () {
    testWidgets(
      'AUTH-04 Start Talking unchanged; Create account + Sign in below it',
      (tester) async {
        final h = Mob1Harness();
        await _pump(tester, h.overrides);
        expect(find.byType(LandingScreen), findsOneWidget);
        expect(find.text(LandingScreen.startLabel), findsOneWidget);
        expect(find.text('Anonymous sign-in · Local history'), findsOneWidget);
        expect(find.text('Continue without an account'), findsNothing);
        expect(find.text(en(CareText.auWhy)), findsOneWidget);
        final start = tester.getRect(_key('landing-start'));
        final create = tester.getRect(_key('landing-create-account'));
        final signIn = tester.getRect(_key('landing-sign-in'));
        final why = tester.getRect(_key('landing-account-why'));
        final psych = tester.getRect(_key('auth-psychologist'));
        expect(start.bottom, lessThanOrEqualTo(create.top));
        expect(create.bottom, lessThanOrEqualTo(signIn.top));
        expect(signIn.bottom, lessThanOrEqualTo(why.top));
        expect(why.bottom, lessThanOrEqualTo(psych.top));
        expect(create.width, signIn.width);
        expect(create.width, greaterThan(280), reason: 'full width');
        expect(tester.takeException(), isNull);
        // The no-account path is the same anonymous sign-in as before.
        await _tap(tester, _key('landing-start'));
        expect(h.auth.signInCalls, 1);
      },
    );

    testWidgets(
      'AUTH-05 landing buttons open the MOB-1 form (create / sign in)',
      (tester) async {
        final h = Mob1Harness();
        await _pump(tester, h.overrides);
        await _tap(tester, _key('landing-create-account'));
        expect(find.byType(AccountAuthScreen), findsOneWidget);
        expect(_title(CareText.auCreateTitle), findsOneWidget);
        expect(_key('account-confirm'), findsOneWidget);
        expect(_key('password-warning'), findsOneWidget);
        expect(_key('account-forgot'), findsNothing);
        await _back(tester);
        await _settle(tester);
        await _tap(tester, _key('landing-sign-in'));
        expect(_title(CareText.auSignInTitle), findsOneWidget);
        expect(_key('account-confirm'), findsNothing);
        expect(_key('account-forgot'), findsOneWidget);
        // Signed out → a new account (not a link).
        await _back(tester);
        await _settle(tester);
        await _tap(tester, _key('landing-create-account'));
        await _fill(
          tester,
          email: 'new@x.io',
          password: 'longpass1',
          confirm: 'longpass1',
        );
        await _submit(tester);
        expect(h.auth.user?.isAnonymous, isFalse);
        expect(h.auth.accounts['new@x.io']?.$1, startsWith('new-'));
      },
    );

    testWidgets(
      'AUTH-06 "I\'m a psychologist" shows information only (landing + form)',
      (tester) async {
        final h = Mob1Harness();
        await _pump(tester, h.overrides);
        await _tap(tester, _key('auth-psychologist'));
        final sheet = _key('psychologist-info');
        expect(sheet, findsOneWidget);
        expect(
          find.descendant(
            of: sheet,
            matching: find.text(en(CareText.auPsychBody)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sheet, matching: find.byType(TextField)),
          findsNothing,
          reason: 'no form, no role to pick',
        );
        await tester.tap(_key('psychologist-info-ok'));
        await _settle(tester);
        expect(sheet, findsNothing);
        expect(h.auth.user, isNull);
        expect(h.source.fetches, 0);
        // Also on the sign-in form.
        await _tap(tester, _key('landing-sign-in'));
        await _tap(tester, _key('auth-psychologist'));
        expect(_key('psychologist-info'), findsOneWidget);
        await tester.tap(_key('psychologist-info-ok'));
        await _settle(tester);
        expect(find.byType(AccountAuthScreen), findsOneWidget);
        expect(h.auth.user, isNull);
      },
    );
  });

  group('AUTH-07..10 anonymous user', () {
    testWidgets(
      'AUTH-07 Care tab = information page: no bell, no fetch, no network',
      (tester) async {
        final h = Mob1Harness(user: _anon);
        final net = _NoNetwork();
        final old = HttpOverrides.current;
        HttpOverrides.global = net;
        addTearDown(() => HttpOverrides.global = old);
        await _pump(tester, h.overrides);
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(_key('nav-bell'), findsNothing);
        net.created.clear(); // anything the shell itself did is not Care's
        await _openCare(tester);
        expect(_key('care-anonymous'), findsOneWidget);
        expect(find.byType(CareScreen), findsNothing);
        expect(find.text(en(CareText.auCareTitle)), findsOneWidget);
        expect(find.text(en(CareText.auCareWhy)), findsOneWidget);
        expect(_key('care-create-account'), findsOneWidget);
        expect(_key('care-sign-in'), findsOneWidget);
        expect(_key('care-experts'), findsNothing);
        expect(_key('care-notifications'), findsNothing);
        expect(_key('nav-bell'), findsNothing);
        await tester.drag(_key('care-anonymous'), const Offset(0, 300));
        await _settle(tester);
        expect(h.source.fetches, 0);
        expect(net.created, isEmpty);
      },
    );

    testWidgets(
      'AUTH-08 Care buttons: Create = link (upgrade), Sign in = switch',
      (tester) async {
        final h = Mob1Harness(user: _anon);
        await _pump(tester, h.overrides);
        await _openCare(tester);
        await _tap(tester, _key('care-create-account'));
        expect(find.text(en(CareText.auUpgradeIntro)), findsOneWidget);
        expect(_key('password-warning'), findsOneWidget);
        await _back(tester);
        await _settle(tester);
        await _tap(tester, _key('care-sign-in'));
        expect(find.text(en(CareText.auSignInSwitchNote)), findsOneWidget);
      },
    );

    testWidgets(
      'AUTH-09 create account from Care keeps the uid, chats, check-ins and '
      'safety plan (re-encrypted)',
      (tester) async {
        final h = Mob1Harness(user: _anon, caps: {'a1': generalCaps});
        final plans = await _seedHistory(h, 'a1');
        await _pump(tester, [
          ...h.overrides,
          safetyPlanBoxProvider.overrideWithValue(plans),
        ]);
        await _openCare(tester);
        await _tap(tester, _key('care-create-account'));
        await _fill(
          tester,
          email: 'me@x.io',
          password: 'longpass1',
          confirm: 'longpass1',
        );
        await _submit(tester);
        await _settle(tester, 20);
        expect(h.auth.user!.uid, 'a1', reason: 'same uid (link)');
        expect(h.auth.isLinked, isTrue);
        final row = (await h.messages.byConversation('a1')).single;
        expect(SecretCipher.secretOf(row.content), 'longpass1');
        expect(
          await h.cipher.decrypt(row.content, 'longpass1'),
          'my private words',
        );
        final checkIn = jsonDecode(h.checkIns.rows.values.single) as Map;
        expect(
          SecretCipher.secretOf(checkIn['payload'] as String),
          'longpass1',
        );
        final plan = jsonDecode(plans.rows['a1']!) as Map;
        expect(SecretCipher.secretOf(plan['payload'] as String), 'longpass1');
        expect(plans.rows.values.join().contains('my private reason'), isFalse);
        expect(find.byType(AppShell), findsOneWidget);
      },
    );

    testWidgets(
      'AUTH-10 sign in to another account: claim only offered, no leak',
      (tester) async {
        final h = Mob1Harness(user: _anon, caps: {'b1': generalCaps});
        h.auth.accounts['b@x.io'] = ('b1', 'pwB12345');
        final plans = await _seedHistory(h, 'a1');
        await _pump(tester, [
          ...h.overrides,
          safetyPlanBoxProvider.overrideWithValue(plans),
        ]);
        await _openCare(tester);
        await _tap(tester, _key('care-sign-in'));
        await _fill(tester, email: 'b@x.io', password: 'pwB12345');
        await _submit(tester);
        await _settle(tester, 20);
        expect(h.auth.user!.uid, 'b1');
        expect(find.byType(ClaimScreen), findsOneWidget);
        expect(await h.messages.byConversation('b1'), isEmpty);
        expect(plans.rows['b1'], isNull);
        expect(find.text('my private words'), findsNothing);
        await _tap(tester, _key('claim-leave'));
        await _settle(tester, 20);
        expect(find.byType(AppShell), findsOneWidget);
        expect(find.text('my private words'), findsNothing);
        expect(await h.messages.byConversation('b1'), isEmpty);
        expect(plans.rows['b1'], isNull);
        expect(plans.rows['a1'], isNotNull, reason: 'kept hidden on device');
      },
    );
  });

  group('AUTH-11..15 the form', () {
    Future<Mob1Harness> openForm(WidgetTester tester, String button) async {
      final h = Mob1Harness(user: _anon);
      await _pump(tester, h.overrides);
      await _openCare(tester);
      await _tap(tester, _key(button));
      return h;
    }

    testWidgets('AUTH-11 inline checks: empty, bad email, < 8, mismatch', (
      tester,
    ) async {
      final h = await openForm(tester, 'care-create-account');
      await _submit(tester);
      expect(
        find.descendant(
          of: _key('account-email-error'),
          matching: find.text(en(CareText.auEnterEmail)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('account-password-error'),
          matching: find.text(en(CareText.auEnterPassword)),
        ),
        findsOneWidget,
      );
      await _fill(tester, email: 'nope', password: 'short7c', confirm: 'x');
      await _submit(tester);
      expect(find.text(en(CareText.auErrInvalidEmail)), findsOneWidget);
      expect(find.text(en(CareText.auPasswordShort)), findsOneWidget);
      await _fill(
        tester,
        email: 'me@x.io',
        password: 'longpass1',
        confirm: 'longpass2',
      );
      await _submit(tester);
      expect(
        find.descendant(
          of: _key('account-confirm-error'),
          matching: find.text(en(CareText.auMismatch)),
        ),
        findsOneWidget,
      );
      expect(h.auth.user!.isAnonymous, isTrue, reason: 'nothing was sent');
      expect(h.auth.accounts, isEmpty);
      // Sign-in: an older 6-character password is not blocked here.
      await _back(tester);
      await _settle(tester);
      h.auth.accounts['old@x.io'] = ('o1', 'six666');
      await _tap(tester, _key('care-sign-in'));
      await _fill(tester, email: 'old@x.io', password: 'six666');
      await _submit(tester);
      await _settle(tester, 20);
      expect(h.auth.user!.uid, 'o1');
    });

    testWidgets('AUTH-12 every sign-in / create error shows a friendly line', (
      tester,
    ) async {
      final h = await openForm(tester, 'care-sign-in');
      const signInErrors = {
        AccountAuthError.wrongCredentials: CareText.auErrWrong,
        AccountAuthError.accountNotFound: CareText.auErrNotFound,
        AccountAuthError.network: CareText.auErrNetwork,
        AccountAuthError.tooManyRequests: CareText.auErrTooMany,
        AccountAuthError.notSupported: CareText.auErrNotAllowed,
        AccountAuthError.unknown: CareText.auErrGeneric,
      };
      for (final e in signInErrors.entries) {
        h.auth.failNext = e.key;
        await _fill(tester, email: 'b@x.io', password: 'whatever1');
        await _submit(tester);
        expect(
          find.descendant(
            of: _key('account-error'),
            matching: find.text(en(e.value)),
          ),
          findsOneWidget,
          reason: e.key.name,
        );
        expect(
          _key('account-create-instead'),
          e.key == AccountAuthError.accountNotFound
              ? findsOneWidget
              : findsNothing,
          reason: e.key.name,
        );
        expect(find.textContaining('AccountAuth'), findsNothing);
        expect(find.textContaining('firebase'), findsNothing);
      }
      expect(h.auth.user!.isAnonymous, isTrue);

      await _back(tester);
      await _settle(tester);
      await _tap(tester, _key('care-create-account'));
      const createErrors = {
        AccountAuthError.emailInUse: CareText.auErrEmailInUse,
        AccountAuthError.weakPassword: CareText.auErrWeak,
        AccountAuthError.invalidEmail: CareText.auErrInvalidEmail,
        AccountAuthError.notSupported: CareText.auErrNotAllowed,
        AccountAuthError.network: CareText.auErrNetwork,
      };
      for (final e in createErrors.entries) {
        h.auth.failNext = e.key;
        await _fill(
          tester,
          email: 'me@x.io',
          password: 'longpass1',
          confirm: 'longpass1',
        );
        await _submit(tester);
        expect(
          find.descendant(
            of: _key('account-error'),
            matching: find.text(en(e.value)),
          ),
          findsOneWidget,
          reason: e.key.name,
        );
        expect(
          _key('account-sign-in-instead'),
          e.key == AccountAuthError.emailInUse ? findsOneWidget : findsNothing,
          reason: e.key.name,
        );
      }
      expect(h.auth.user!.isAnonymous, isTrue);
      expect(h.auth.user!.uid, 'a1');
      // "Sign in instead" switches the same form.
      h.auth.failNext = AccountAuthError.emailInUse;
      await _submit(tester);
      await _tap(tester, _key('account-sign-in-instead'));
      expect(_title(CareText.auSignInTitle), findsOneWidget);
    });

    testWidgets('AUTH-13 KoiLoader while the account call runs', (
      tester,
    ) async {
      final h = await openForm(tester, 'care-sign-in');
      h.auth.accounts['b@x.io'] = ('b1', 'pwB12345');
      h.auth.callGate = Completer<void>();
      await _fill(tester, email: 'b@x.io', password: 'pwB12345');
      await _submit(tester);
      expect(find.byType(KoiLoadingPage), findsOneWidget);
      expect(find.text(en(CareText.auBusySignIn)), findsOneWidget);
      expect(_key('account-submit'), findsNothing);
      h.auth.callGate!.complete();
      h.auth.callGate = null;
      await _settle(tester, 20);
      expect(h.auth.user!.uid, 'b1');
    });

    testWidgets('AUTH-14 show / hide password (both fields), 48dp, labelled', (
      tester,
    ) async {
      await openForm(tester, 'care-create-account');
      bool obscured(String k) =>
          tester.widget<TextField>(_field(k)).obscureText;
      expect(obscured('account-password'), isTrue);
      expect(obscured('account-confirm'), isTrue);
      expect(
        find.bySemanticsLabel(en(CareText.auShowPassword)),
        findsOneWidget,
      );
      expect(
        tester.getSize(_key('account-show-password')).height,
        greaterThanOrEqualTo(48),
      );
      await _tap(tester, _key('account-show-password'));
      expect(obscured('account-password'), isFalse);
      expect(obscured('account-confirm'), isFalse);
      expect(
        find.bySemanticsLabel(en(CareText.auHidePassword)),
        findsOneWidget,
      );
      await _tap(tester, _key('account-show-password'));
      expect(obscured('account-password'), isTrue);
    });

    testWidgets(
      'AUTH-15 Forgot password: warns first, neutral result, no enumeration',
      (tester) async {
        final h = await openForm(tester, 'care-sign-in');
        await _tap(tester, _key('account-forgot'));
        expect(find.text(en(CareText.auResetNeedEmail)), findsOneWidget);
        expect(_key('reset-dialog'), findsNothing);
        expect(h.auth.resetEmails, isEmpty);

        await tester.enterText(_field('account-email'), 'me@x.io');
        await _tap(tester, _key('account-forgot'));
        expect(_key('reset-dialog'), findsOneWidget);
        expect(find.text(en(CareText.auResetBody)), findsOneWidget);
        expect(find.text(en(CareText.auPasswordWarning)), findsOneWidget);
        await _tap(tester, _key('reset-cancel'));
        expect(h.auth.resetEmails, isEmpty);

        await _tap(tester, _key('account-forgot'));
        await _tap(tester, _key('reset-confirm'));
        expect(h.auth.resetEmails, ['me@x.io']);
        expect(_key('account-reset-sent'), findsOneWidget);
        expect(find.text(en(CareText.auResetSent)), findsOneWidget);

        // An unknown email looks exactly the same.
        h.auth.failNext = AccountAuthError.accountNotFound;
        await _tap(tester, _key('account-forgot'));
        await _tap(tester, _key('reset-confirm'));
        expect(_key('account-reset-sent'), findsOneWidget);
        expect(find.text(en(CareText.auErrNotFound)), findsNothing);

        h.auth.failNext = AccountAuthError.network;
        await _tap(tester, _key('account-forgot'));
        await _tap(tester, _key('reset-confirm'));
        expect(_key('account-reset-sent'), findsNothing);
        expect(find.text(en(CareText.auErrNetwork)), findsOneWidget);
        expect(h.auth.user!.isAnonymous, isTrue, reason: 'nobody signed in');
      },
    );
  });

  group('AUTH-16..18 Settings card, unavailable backend', () {
    testWidgets(
      'AUTH-16 Settings → Account card: two buttons, dismiss sticks',
      (tester) async {
        final h = Mob1Harness(user: _anon);
        await _pump(tester, h.overrides);
        await tester.tap(_key('nav-tab-settings'));
        await _settle(tester);
        final card = _key('account-entry-card');
        expect(card, findsOneWidget);
        expect(
          tester.getRect(card).bottom,
          lessThanOrEqualTo(tester.getRect(_key('row-create-account')).top),
          reason: 'at the top of the Account section',
        );
        expect(_key('settings-create-account'), findsOneWidget);
        expect(_key('settings-sign-in'), findsOneWidget);
        expect(find.byTooltip(en(CareText.auDismiss)), findsOneWidget);
        await _tap(tester, _key('settings-create-account'));
        expect(find.text(en(CareText.auUpgradeIntro)), findsOneWidget);
        await _back(tester);
        await _settle(tester);
        await _tap(tester, _key('account-entry-dismiss'));
        expect(card, findsNothing);
        expect(h.prefs.values['koi_auth_card_dismissed_a1'], 'true');
        // The existing rows stay.
        expect(_key('row-create-account'), findsOneWidget);
        expect(_key('row-sign-in'), findsOneWidget);
        // Still dismissed after a restart.
        // (A fresh harness with the same device prefs: an auth fake cannot
        // be reused once its scope is disposed.)
        await tester.pumpWidget(const SizedBox());
        final again = Mob1Harness(user: _anon);
        again.prefs.values.addAll(h.prefs.values);
        await _pump(tester, again.overrides);
        await tester.tap(_key('nav-tab-settings'));
        await _settle(tester);
        expect(card, findsNothing);
      },
    );

    testWidgets('AUTH-16b registered users get no card', (tester) async {
      final h = Mob1Harness(
        user: AccountFakeAuth.registered('g1', 'g@x'),
        caps: {'g1': generalCaps},
      );
      await h.secrets.setLinkedSecret('g1', 'pw');
      await _pump(tester, h.overrides);
      await tester.tap(_key('nav-tab-settings'));
      await _settle(tester);
      expect(_key('account-entry-card'), findsNothing);
    });

    testWidgets(
      'AUTH-17 registered, backend unavailable: chat works, Care = "not '
      'available yet" + Retry',
      (tester) async {
        final h = Mob1Harness(user: AccountFakeAuth.registered('g1', 'g@x'));
        h.source.error = StateError('backend down');
        await h.secrets.setLinkedSecret('g1', 'pw');
        await _pump(tester, h.overrides);
        expect(find.byType(AppShell), findsOneWidget);
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(_key('nav-bell'), findsNothing);
        await _openCare(tester);
        expect(_key('care-unavailable'), findsOneWidget);
        expect(find.text(en(CareText.notAvailableYet)), findsOneWidget);
        expect(find.byType(CareScreen), findsNothing);
        final before = h.source.fetches;
        h.source.error = null;
        h.source.byUid['g1'] = generalCaps;
        await _tap(tester, _key('notice-action'));
        await _settle(tester, 20);
        expect(h.source.fetches, before + 1);
        expect(find.byType(AppShell), findsOneWidget);
        await _openCare(tester);
        expect(find.byType(CareScreen), findsOneWidget);
      },
    );

    testWidgets(
      'AUTH-18 sign in from the landing with the backend down: normal user, '
      'full KOI chat',
      (tester) async {
        final h = Mob1Harness();
        h.auth.accounts['g@x.io'] = ('g1', 'pwG12345');
        h.source.error = StateError('backend down');
        await _pump(tester, h.overrides);
        await _tap(tester, _key('landing-sign-in'));
        await _fill(tester, email: 'g@x.io', password: 'pwG12345');
        await _submit(tester);
        await _settle(tester, 20);
        expect(h.auth.user!.uid, 'g1');
        expect(h.source.fetches, greaterThanOrEqualTo(1));
        expect(find.byType(ChatScreen), findsOneWidget);
        await _openCare(tester);
        expect(_key('care-unavailable'), findsOneWidget);
      },
    );
  });

  group('AUTH-19..21 layout, Urdu, accessibility', () {
    for (final width in [360.0, 320.0]) {
      for (final urdu in [false, true]) {
        final lang = urdu ? 'ur' : 'en';
        testWidgets(
          'AUTH-19 ${width.toInt()}dp $lang: no overflow (landing, Care, '
          'card, forms)',
          (tester) async {
            if (!urdu) {
              final signedOut = Mob1Harness();
              await _pump(tester, signedOut.overrides, width: width);
              Scrollable.ensureVisible(
                tester.element(_key('auth-psychologist')),
                alignment: 0.5,
              );
              await _settle(tester, 3);
              final e = tester.takeException();
              if (width >= 360) {
                expect(e, isNull);
              } else {
                // Known, pre-existing: the web-parity footer row
                // (koi_footer.dart) overflows at 320dp at 1add861 too.
                // The new account block itself must fit.
                expect(e?.toString() ?? '', isNot(contains('bottom')));
              }
              for (final k in [
                'landing-create-account',
                'landing-sign-in',
                'landing-account-why',
                'auth-psychologist',
              ]) {
                final r = tester.getRect(_key(k));
                expect(r.left, greaterThanOrEqualTo(0), reason: k);
                expect(r.right, lessThanOrEqualTo(width), reason: k);
              }
              await tester.pumpWidget(const SizedBox());
            }
            final h = Mob1Harness(user: _anon);
            if (urdu) {
              h.settings.values['a1'] = const SettingsPrefs(language: 'ur');
            }
            await _pump(tester, h.overrides, width: width, height: 640);
            await _openCare(tester);
            expect(tester.takeException(), isNull);
            await _tap(tester, _key('care-create-account'));
            Scrollable.ensureVisible(
              tester.element(_key('auth-psychologist')),
              alignment: 0.5,
            );
            await _settle(tester, 3);
            expect(tester.takeException(), isNull);
            await _back(tester);
            await _settle(tester);
            await _tap(tester, _key('care-sign-in'));
            expect(tester.takeException(), isNull);
            await _back(tester);
            await _settle(tester);
            await tester.tap(_key('nav-tab-settings'));
            await _settle(tester);
            expect(_key('account-entry-card'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('AUTH-20 Urdu: RTL pages, email / password typed LTR', (
      tester,
    ) async {
      final h = Mob1Harness(user: _anon);
      h.settings.values['a1'] = const SettingsPrefs(language: 'ur');
      await _pump(tester, h.overrides);
      await _openCare(tester);
      final title = find.text(CareStrings.ur.t(CareText.auCareTitle));
      expect(title, findsOneWidget);
      expect(Directionality.of(tester.element(title)), TextDirection.rtl);
      await _tap(tester, _key('care-create-account'));
      final formTitle = find.text(CareStrings.ur.t(CareText.auCreateTitle));
      expect(formTitle, findsOneWidget);
      expect(Directionality.of(tester.element(formTitle)), TextDirection.rtl);
      for (final k in [
        'account-email',
        'account-password',
        'account-confirm',
      ]) {
        expect(
          tester.widget<TextField>(_field(k)).textDirection,
          TextDirection.ltr,
          reason: k,
        );
      }
      await _submit(tester);
      expect(
        find.text(CareStrings.ur.t(CareText.auEnterEmail)),
        findsOneWidget,
      );
    });

    testWidgets('AUTH-21 48dp targets and labels on every new control', (
      tester,
    ) async {
      final h = Mob1Harness(user: _anon);
      await _pump(tester, h.overrides);
      await _openCare(tester);
      for (final k in ['care-create-account', 'care-sign-in']) {
        expect(
          tester.getSize(_key(k)).height,
          greaterThanOrEqualTo(48),
          reason: k,
        );
      }
      expect(find.bySemanticsLabel(en(CareText.auCreateButton)), findsWidgets);
      await _tap(tester, _key('care-sign-in'));
      for (final k in [
        'account-submit',
        'account-show-password',
        'account-forgot',
        'auth-psychologist',
      ]) {
        final size = tester.getSize(_key(k));
        expect(size.height, greaterThanOrEqualTo(48), reason: k);
        expect(size.width, greaterThanOrEqualTo(48), reason: k);
      }
      expect(find.bySemanticsLabel(en(CareText.auForgot)), findsOneWidget);
      expect(find.bySemanticsLabel(en(CareText.auPsychLink)), findsOneWidget);
      await _back(tester);
      await _settle(tester);
      await tester.tap(_key('nav-tab-settings'));
      await _settle(tester);
      final dismiss = tester.getSize(_key('account-entry-dismiss'));
      expect(dismiss.height, greaterThanOrEqualTo(48));
      expect(dismiss.width, greaterThanOrEqualTo(48));
    });
  });

  testWidgets(
    'AUTH-22 anonymous path unchanged: chat, progress, settings rows',
    (tester) async {
      final h = Mob1Harness(user: _anon);
      await _pump(tester, h.overrides);
      expect(find.byType(ChatScreen), findsOneWidget);
      for (final t in ['chat', 'progress', 'care', 'settings']) {
        expect(_key('nav-tab-$t'), findsOneWidget, reason: t);
      }
      expect(h.source.fetches, 0);
      expect(h.auth.user!.isAnonymous, isTrue);
      await tester.tap(_key('nav-tab-settings'));
      await _settle(tester);
      expect(_key('row-create-account'), findsOneWidget);
      expect(_key('row-sign-in'), findsOneWidget);
      expect(_key('row-sign-out'), findsNothing);
      await tester.tap(_key('nav-tab-chat'));
      await _settle(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(h.auth.signInCalls, 0, reason: 'no new anonymous sign-in');
      expect(find.byType(AccountEntryCard), findsNothing);
    },
  );
}
