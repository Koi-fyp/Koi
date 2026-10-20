import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextDirection;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_flutter_lib/services/crypto_service.dart';
import 'package:koi_mobile/account/account_migration.dart';
import 'package:koi_mobile/care/care_strings.dart';
import 'package:koi_mobile/chat/conversation_service.dart';
import 'package:koi_mobile/chat/message_record.dart';
import 'package:koi_mobile/checkins/checkin_store.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/core/key_value_store.dart';
import 'package:koi_mobile/core/sync_queue.dart';
import 'package:koi_mobile/safety_plan/safety_plan_models.dart';
import 'package:koi_mobile/safety_plan/safety_plan_providers.dart';
import 'package:koi_mobile/safety_plan/safety_plan_store.dart';
import 'package:koi_mobile/safety_plan/text_direction.dart';

import '../support/chat_fakes.dart';
import '../support/mob1_fakes.dart';

class _AckAll implements MigrationUploader {
  final uploads = <SyncItem>[];
  @override
  Future<bool> writeNow(SyncItem item) async {
    uploads.add(item);
    return true;
  }

  @override
  Future<int> removeWhere(bool Function(SyncItem item) test) async => 0;
}

const _secretWords = ['Long walk by the canal', '0321 7654321', 'My sister'];

SafetyPlan _plan() => SafetyPlan(
  items: {
    SafetyPlanSection.copingAlone: [
      const SafetyPlanItem(id: 'a', text: 'Long walk by the canal'),
    ],
    SafetyPlanSection.peopleToAsk: [
      const SafetyPlanItem(id: 'b', text: 'My sister', phone: '0321 7654321'),
    ],
  },
);

SafetyPlanRepository _repo(
  SafetyPlanBox box, {
  MessageCipher? cipher,
  CryptoContextGetter? ctx,
}) => SafetyPlanRepository(
  box: box,
  cipher: cipher ?? SecretCipher(),
  cryptoContext:
      ctx ?? (uid) async => CryptoContext(secret: 'sec-$uid', saltB64: 's'),
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final now = DateTime(2026, 10, 20, 9);

  group('SAFE-01 limits: 10 items, 300 characters, phone characters', () {
    test('text is trimmed and cut at 300; blank text is not an item', () {
      final long = 'x' * 400;
      expect(SafetyPlanItem.clean(id: '1', text: '  hi  ')!.text, 'hi');
      expect(SafetyPlanItem.clean(id: '1', text: long)!.text.length, 300);
      expect(SafetyPlanItem.clean(id: '1', text: '   '), isNull);
    });
    test('phone: digits, spaces, + - ( ) only, max 20, needs a digit', () {
      String? p(String v) =>
          SafetyPlanItem.clean(id: '1', text: 't', phone: v)?.phone;
      expect(p('+92 (300) 123-4567'), '+92 (300) 123-4567');
      expect(p('call me'), isNull);
      expect(p('---'), isNull);
      expect(p('1' * 21), isNull);
      expect(p('  '), isNull);
    });
    test('at most 10 items per section; phones only where they belong', () {
      final many = [
        for (var i = 0; i < 14; i++) SafetyPlanItem(id: '$i', text: 't$i'),
      ];
      final plan = SafetyPlan(
        items: {
          SafetyPlanSection.reasons: many,
          SafetyPlanSection.warningSigns: [
            const SafetyPlanItem(id: 'w', text: 'w', phone: '123'),
          ],
        },
      );
      expect(plan[SafetyPlanSection.reasons], hasLength(10));
      expect(plan[SafetyPlanSection.warningSigns].single.phone, isNull);
      expect(SafetyPlan.maxItems, 10);
      expect(SafetyPlanItem.maxText, 300);
    });
  });

  test('SAFE-02 payload round trip keeps order, text and phones', () {
    final back = SafetyPlan.fromPayload(
      (jsonDecode(jsonEncode(_plan().toPayload())) as Map)
          .cast<String, Object?>(),
    );
    expect(back.items, _plan().items);
    expect(back[SafetyPlanSection.professionals], isEmpty);
    expect(back.isEmpty, isFalse);
    expect(SafetyPlan.empty.isEmpty, isTrue);
  });

  group('SAFE-03 encrypted at rest with the existing CSE (real cipher)', () {
    test('the stored row holds no plaintext and decrypts back', () async {
      final box = MemorySafetyPlanBox();
      final repo = _repo(
        box,
        cipher: KoiMessageCipher(KoiCryptoService()),
        ctx: (_) async => testCryptoContext,
      );
      await repo.save('u1', _plan(), now);
      final raw = box.rows['u1']!;
      for (final w in _secretWords) {
        expect(raw.contains(w), isFalse, reason: w);
      }
      final row = jsonDecode(raw) as Map;
      expect(
        row.keys,
        unorderedEquals(['id', 'userId', 'updatedAt', 'payload']),
      );
      expect((row['payload'] as String).startsWith('v1:'), isTrue);
      expect((await repo.load('u1'))!.items, _plan().items);
    });
    test('an empty plan removes the row (never an empty plan)', () async {
      final box = MemorySafetyPlanBox();
      final repo = _repo(box);
      await repo.save('u1', _plan(), now);
      await repo.save('u1', SafetyPlan.empty, now);
      expect(box.rows, isEmpty);
      expect(await repo.load('u1'), isNull);
    });
  });

  test(
    'SAFE-04 a row the key cannot open is "no plan", never garbage',
    () async {
      final box = MemorySafetyPlanBox();
      await _repo(box).save('u1', _plan(), now);
      final wrongKey = _repo(
        box,
        ctx: (_) async => const CryptoContext(secret: 'other', saltB64: 's'),
      );
      expect(await wrongKey.load('u1'), isNull);
      await box.put('u1', 'not json');
      expect(await _repo(box).load('u1'), isNull);
      final c = SafetyPlanController('u1', wrongKey, () => now);
      await Future<void>.delayed(Duration.zero);
      expect(c.plan, isNull);
      expect(c.hasPlan, isFalse);
    },
  );

  group('SAFE-05 per uid: no leak between accounts', () {
    test('B never reads A\'s row, even with the same box', () async {
      final box = MemorySafetyPlanBox();
      await _repo(box).save('a', _plan(), now);
      expect(await _repo(box).load('b'), isNull);
      // A row under b's key that claims to be a's is ignored too.
      await box.put('b', box.rows['a']!);
      expect(await _repo(box).load('b'), isNull);
      expect((await _repo(box).load('a'))!.items, _plan().items);
    });
  });

  group('SAFE-07 / SAFE-08 account linking keeps the plan (CseMigration)', () {
    CseMigration migration(
      SafetyPlanBox plans,
      SecretCipher cipher,
      KeyValueStore prefs,
    ) => CseMigration(
      messages: MemoryMessageStore(),
      checkIns: MemoryCheckInBox(),
      safetyPlans: plans,
      cipher: cipher,
      uploader: _AckAll(),
      markers: prefs,
    );

    test('SAFE-07 link: re-encrypted with the password; rerun is a no-op; '
        'never uploaded', () async {
      final cipher = SecretCipher();
      final box = MemorySafetyPlanBox();
      final uploader = _AckAll();
      await _repo(
        box,
        cipher: cipher,
        ctx: (_) async => const CryptoContext(secret: 'ANON', saltB64: 's'),
      ).save('a1', _plan(), now);
      final m = CseMigration(
        messages: MemoryMessageStore(),
        checkIns: MemoryCheckInBox(),
        safetyPlans: box,
        cipher: cipher,
        uploader: uploader,
        markers: MemoryKeyValueStore(),
      );
      const to = CryptoContext(secret: 'pw', saltB64: 'salt-a1');
      final r = await m.runLink(uid: 'a1', fromSecret: 'ANON', to: to);
      expect(r.reencrypted, 1);
      final payload = (jsonDecode(box.rows['a1']!) as Map)['payload'] as String;
      expect(SecretCipher.secretOf(payload), 'pw');
      final after = _repo(box, cipher: cipher, ctx: (_) async => to);
      expect((await after.load('a1'))!.items, _plan().items);
      expect(uploader.uploads, isEmpty, reason: 'the plan is never uploaded');

      // Interrupted run resumed: already re-encrypted, nothing encrypted again.
      final again = await migration(
        box,
        cipher,
        MemoryKeyValueStore(),
      ).runLink(uid: 'a1', fromSecret: 'ANON', to: to);
      expect(again.reencrypted, 0);
      expect(again.alreadyDone, 1);
    });

    test('SAFE-08 claim: copied to the account; the account\'s own plan '
        'wins', () async {
      final cipher = SecretCipher();
      final box = MemorySafetyPlanBox();
      await _repo(
        box,
        cipher: cipher,
        ctx: (_) async => const CryptoContext(secret: 'ANON', saltB64: 's'),
      ).save('anon', _plan(), now);
      final prefs = MemoryKeyValueStore();
      final m = migration(box, cipher, prefs);
      await m.offerClaim(source: 'anon', target: 'acct');
      const to = CryptoContext(secret: 'pw', saltB64: 'salt');
      final r = await m.runClaim(target: 'acct', fromSecret: 'ANON', to: to);
      expect(r.reencrypted, 1);
      final copy = _repo(box, cipher: cipher, ctx: (_) async => to);
      expect((await copy.load('acct'))!.items, _plan().items);

      // A second device's account that already has its own plan keeps it.
      final box2 = MemorySafetyPlanBox();
      await _repo(
        box2,
        cipher: cipher,
        ctx: (_) async => const CryptoContext(secret: 'ANON', saltB64: 's'),
      ).save('anon', _plan(), now);
      final own = SafetyPlan(
        items: {
          SafetyPlanSection.reasons: [
            const SafetyPlanItem(id: 'r', text: 'Mine'),
          ],
        },
      );
      await _repo(
        box2,
        cipher: cipher,
        ctx: (_) async => to,
      ).save('acct', own, now);
      final m2 = migration(box2, cipher, MemoryKeyValueStore());
      await m2.offerClaim(source: 'anon', target: 'acct');
      final r2 = await m2.runClaim(target: 'acct', fromSecret: 'ANON', to: to);
      expect(r2.alreadyDone, 1);
      expect(
        (await _repo(box2, cipher: cipher, ctx: (_) async => to).load('acct'))!
            .items,
        own.items,
      );
    });
  });

  group('SAFE-11 / SAFE-12 wording rules (both languages)', () {
    final sp = [
      for (final k in CareText.values)
        if (k.name.startsWith('sp')) k,
    ];

    test('SAFE-11 "surroundings" is ONE gentle question; no method or means '
        'words anywhere', () {
      expect(
        CareStrings.en.t(CareText.spSaferSurroundingsHelp),
        'What could you do to make your surroundings safer when things feel '
        'hard?',
      );
      const banned = [
        'method',
        'means',
        'weapon',
        'knife',
        'gun',
        'pill',
        'medication',
        'medicine',
        'poison',
        'rope',
        'blade',
        'overdose',
        'lethal',
        'suicid',
        'kill',
        'harm',
      ];
      for (final k in sp) {
        final text = CareStrings.en.t(k).toLowerCase();
        for (final w in banned) {
          expect(text.contains(w), isFalse, reason: '${k.name}: "$w"');
        }
      }
    });

    test('SAFE-12 no score, percentage or completeness wording', () {
      const banned = ['score', '%', 'complete', 'progress', 'risk', 'level'];
      for (final k in sp) {
        for (final lang in [CareStrings.en, CareStrings.ur]) {
          final text = lang.t(k).toLowerCase();
          for (final w in banned) {
            expect(text.contains(w), isFalse, reason: '${k.name}: "$w"');
          }
        }
      }
      // The model has nothing to score either.
      final source = File('lib/safety_plan/safety_plan_models.dart')
          .readAsStringSync();
      expect(
        RegExp(r'\b(score|percent|completeness)\b')
            .hasMatch(source.replaceAll(RegExp(r'//.*'), '')),
        isFalse,
      );
    });

    test('SAFE-12 every safety plan string exists in both languages; '
        'footnote and "add more" texts', () {
      for (final k in sp) {
        expect(CareStrings.table(CareLang.en)[k], isNotNull, reason: k.name);
        expect(CareStrings.table(CareLang.ur)[k], isNotNull, reason: k.name);
      }
      expect(
        CareStrings.en.t(CareText.spFootnote),
        'Based on a widely used safety-planning approach. This does not '
        'replace professional help.',
      );
      expect(CareStrings.en.t(CareText.spAddMore), 'You can add more anytime.');
      final table = File('lib/care/care_strings.dart').readAsStringSync();
      expect(table.contains('NEEDS CLINICIAN REVIEW'), isTrue);
      expect(table.contains('NEEDS NATIVE REVIEW'), isTrue);
    });
  });

  test('SAFE-21 user text keeps its own direction', () {
    expect(userTextDirection('میری بہن'), TextDirection.rtl);
    expect(userTextDirection('My sister'), TextDirection.ltr);
    expect(userTextDirection('  2 میری'), TextDirection.rtl);
    expect(userTextDirection('123'), isNull);
  });

  group('SAFE-26 nothing about the plan leaves the device', () {
    test('lib/safety_plan imports no network, Firestore, chat, speech, '
        'platform or sync code', () {
      const forbidden = [
        'dart:io',
        'package:http',
        'cloud_firestore',
        'firebase',
        'chat_api',
        'conversation_service.dart\';', // only the cipher types (show ...)
        'speech',
        'voice',
        'platform_client',
        'sync_queue',
        'analytics',
        'care_api',
        'questionnaire_api',
        'expert_api',
      ];
      final files = Directory('lib/safety_plan')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      for (final f in files) {
        final imports = f
            .readAsLinesSync()
            .where((l) => l.startsWith('import '))
            .join('\n');
        for (final w in forbidden) {
          expect(imports.contains(w), isFalse, reason: '${f.path}: $w');
        }
      }
    });

    test('save, load, clear and the controller make no HTTP request and '
        'log no plan text', () async {
      final requests = <String>[];
      final logs = <String?>[];
      final oldPrint = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m);
      addTearDown(() => debugPrint = oldPrint);
      await HttpOverrides.runZoned(
        () async {
          final box = MemorySafetyPlanBox();
          final repo = _repo(box);
          await repo.save('u1', _plan(), now);
          await repo.load('u1');
          final c = SafetyPlanController('u1', repo, () => now);
          await c.reload();
          await c.save(_plan());
          await c.fillDemo();
          // An unreadable row logs only the error type.
          await box.put('u1', jsonEncode({'userId': 'u1', 'payload': 'x'}));
          await c.reload();
          await c.clear();
        },
        createHttpClient: (_) {
          requests.add('HttpClient created');
          throw StateError('no network allowed');
        },
      );
      expect(requests, isEmpty);
      for (final l in logs.nonNulls) {
        for (final w in _secretWords) {
          expect(l.contains(w), isFalse, reason: l);
        }
      }
    });
  });
}
