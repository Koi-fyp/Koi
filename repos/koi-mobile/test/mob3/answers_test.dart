import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/questionnaires/attempt_controller.dart';
import 'package:koi_mobile/questionnaires/draft_store.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/question_view.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

import '../support/mob1_fakes.dart';
import '../support/mob3_support.dart';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  final form = parsePublishedQuestionnaire(demoAllTypesEn());
  late MockQuestionnaireRemote remote;
  late MemoryDraftBox box;
  late Assignment assignment;

  DraftRepository draftsOn(MemoryDraftBox b, {bool enabled = true}) =>
      DraftRepository(
        box: b,
        cipher: SecretCipher(),
        cryptoContext: (uid) async =>
            CryptoContext(secret: 'k-$uid', saltB64: 's'),
        enabled: enabled,
      );

  AttemptController device({MemoryDraftBox? store, bool drafts = true}) =>
      AttemptController(
        uid: 'p1',
        assignment: assignment,
        api: remote,
        drafts: draftsOn(store ?? box, enabled: drafts),
        debounce: Duration.zero,
      );

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  List<Map<String, Object?>> lastSentAnswers() =>
      (remote.autosaveBodies.last['answers']! as List)
          .cast<Map<String, Object?>>();

  setUp(() async {
    remote = MockQuestionnaireRemote();
    box = MemoryDraftBox();
    assignment = (await remote.assignments()).items.first;
  });

  group('MOB3-09 the answer shape is exactly the AI Answer', () {
    test('every key is always sent; unused ones are [] / null', () {
      expect(
        encodeAnswer(
          const Answer(answerId: 'a1', questionId: 'q1', optionIds: ['o1']),
        ),
        {
          'answer_id': 'a1',
          'question_id': 'q1',
          'option_ids': ['o1'],
          'value': null,
          'text': null,
        },
      );
      expect(
        encodeAnswer(
          const Answer(answerId: 'a2', questionId: 'q2', value: 2.5),
        ),
        {
          'answer_id': 'a2',
          'question_id': 'q2',
          'option_ids': <String>[],
          'value': 2.5,
          'text': null,
        },
      );
      expect(
        encodeAnswer(
          const Answer(answerId: 'a3', questionId: 'q3', text: 'hi'),
        ),
        {
          'answer_id': 'a3',
          'question_id': 'q3',
          'option_ids': <String>[],
          'value': null,
          'text': 'hi',
        },
      );
      final back = decodeAnswer(
        encodeAnswer(
          const Answer(answerId: 'a3', questionId: 'q3', text: 'hi'),
        ),
      );
      expect(back, const Answer(answerId: 'a3', questionId: 'q3', text: 'hi'));
    });
    test('malformed answers from the server are dropped', () {
      for (final bad in <Object?>[
        {'question_id': 'q1'},
        {'answer_id': 'a b', 'question_id': 'q1'},
        {'answer_id': 'a', 'question_id': 'q1', 'option_ids': 'o1'},
        {'answer_id': 'a', 'question_id': 'q1', 'value': 'five'},
        {'answer_id': 'a', 'question_id': 'q1', 'text': 5},
        'nope',
      ]) {
        expect(decodeAnswer(bad), isNull, reason: '$bad');
      }
    });
  });

  group('MOB3-10 each type is sent with the right field', () {
    test('single / multi / yes_no / likert / image → option_ids; numeric → '
        'value; free_text → text', () async {
      final c = device();
      await c.load();
      c
        ..setAnswer('q_single', const AnswerValue(optionIds: ['o_b']))
        ..setAnswer('q_multi', const AnswerValue(optionIds: ['o_c', 'o_a']))
        ..setAnswer('q_yes_no', const AnswerValue(optionIds: ['o_no']))
        ..setAnswer('q_likert', const AnswerValue(optionIds: ['o5']))
        ..setAnswer('q_free_text', const AnswerValue(text: 'Some words'))
        ..setAnswer('q_numeric', const AnswerValue(value: 7))
        ..setAnswer(
          'q_image_single',
          const AnswerValue(optionIds: ['img_circle']),
        )
        ..setAnswer(
          'q_image_multi',
          const AnswerValue(optionIds: ['img_square', 'img_text_only']),
        );
      await settle();
      final sent = {for (final a in lastSentAnswers()) a['question_id']: a};
      expect(sent.keys, form.questions.map((q) => q.id), reason: 'form order');
      expect(sent['q_single']!['option_ids'], ['o_b']);
      expect(sent['q_multi']!['option_ids'], ['o_c', 'o_a']);
      expect(sent['q_yes_no']!['option_ids'], ['o_no']);
      expect(sent['q_likert']!['option_ids'], ['o5']);
      expect(sent['q_image_multi']!['option_ids'], [
        'img_square',
        'img_text_only',
      ]);
      expect(sent['q_numeric'], containsPair('value', 7.0));
      expect(sent['q_numeric']!['option_ids'], isEmpty);
      expect(sent['q_numeric']!['text'], isNull);
      expect(sent['q_free_text'], containsPair('text', 'Some words'));
      expect(sent['q_free_text']!['value'], isNull);
      for (final a in sent.values) {
        expect(a.keys.toSet(), {
          'answer_id',
          'question_id',
          'option_ids',
          'value',
          'text',
        });
      }
      c.dispose();
    });
  });

  group('MOB3-11 question_id / option_id values are never altered', () {
    test('ids are matched byte for byte (case, dashes, no trimming)', () {
      final q = parsePublishedQuestionnaire(
        publishedFixture('f', {
          'title': 'T',
          'language': 'en',
          'rtl': false,
          'questions': [
            {
              'question_id': 'Q-1_x',
              'type': 'multi',
              'text': 'T',
              'options': [
                {'option_id': 'Opt-A_1', 'label': 'A'},
                {'option_id': 'opt-a_1', 'label': 'B'},
              ],
            },
          ],
        }),
      );
      final clean = sanitizeAnswers(q, const {
        'Q-1_x': Answer(
          answerId: 'a',
          questionId: 'Q-1_x',
          optionIds: ['Opt-A_1', 'OPT-A_1', 'Opt-A_1 ', 'opt-a_1'],
        ),
      });
      expect(clean['Q-1_x']!.optionIds, ['Opt-A_1', 'opt-a_1']);
      expect(
        sanitizeAnswers(q, const {
          'q-1_x': Answer(
            answerId: 'a',
            questionId: 'q-1_x',
            optionIds: ['Opt-A_1'],
          ),
        }),
        isEmpty,
        reason: 'question ids are case-sensitive',
      );
    });
    test('the PATCH body carries the published ids unchanged', () async {
      final c = device();
      await c.load();
      c.setAnswer(
        'q_image_single',
        const AnswerValue(optionIds: ['img_triangle']),
      );
      await settle();
      expect(lastSentAnswers().single['question_id'], 'q_image_single');
      expect(lastSentAnswers().single['option_ids'], ['img_triangle']);
      c.dispose();
    });
  });

  group('MOB3-12 numeric answers follow min / max / step', () {
    const q = Question(
      id: 'n',
      type: QuestionType.numeric,
      text: 'n',
      minValue: 1,
      maxValue: 5,
      step: 0.5,
    );
    test('range and step grid', () {
      expect(numericProblem(q, 0.5), NumericProblem.belowMin);
      expect(numericProblem(q, 5.5), NumericProblem.aboveMax);
      expect(numericProblem(q, 2.3), NumericProblem.offStep);
      for (final ok in [1.0, 2.5, 5.0]) {
        expect(numericProblem(q, ok), isNull, reason: '$ok');
      }
      const tenths = Question(
        id: 't',
        type: QuestionType.numeric,
        text: 't',
        step: 0.1,
      );
      expect(
        numericProblem(tenths, 0.3),
        isNull,
        reason: 'float drift tolerated',
      );
      const free = Question(id: 'f', type: QuestionType.numeric, text: 'f');
      expect(numericProblem(free, -123.456), isNull);
      expect(numericProblem(free, double.nan), isNotNull);
    });
    test('typed numbers: Western, Urdu and Arabic-Indic digits', () {
      expect(parseQuestionnaireNumber(' 42 '), 42);
      expect(parseQuestionnaireNumber('۴۲'), 42);
      expect(parseQuestionnaireNumber('٤٢'), 42);
      expect(parseQuestionnaireNumber('2,5'), 2.5);
      expect(parseQuestionnaireNumber('abc'), isNull);
      expect(formatQuestionnaireNumber(4), '4');
      expect(formatQuestionnaireNumber(2.5), '2.5');
    });
    test('an invalid number is never stored or sent', () async {
      final c = device();
      await c.load();
      c.setAnswer('q_numeric', const AnswerValue(value: 11));
      c.setAnswer('q_numeric', const AnswerValue(value: 3.5));
      expect(c.answers.containsKey('q_numeric'), isFalse);
      c.setAnswer('q_numeric', const AnswerValue(value: 10));
      expect(c.answers['q_numeric']!.value, 10);
      c.dispose();
    });
  });

  group('MOB3-13 free text holds at most 4000 characters', () {
    test('4000 kept, 4001 refused, empty removes the answer', () {
      Map<String, Answer> clean(String t) => sanitizeAnswers(form, {
        'q_free_text': Answer(
          answerId: 'a',
          questionId: 'q_free_text',
          text: t,
        ),
      });
      expect(clean('x' * 4000)['q_free_text']!.text!.length, 4000);
      expect(clean('x' * 4001), isEmpty);
      expect(clean(''), isEmpty);
      expect(
        clean('  spaced  ')['q_free_text']!.text,
        '  spaced  ',
        reason: 'not trimmed',
      );
    });
  });

  group('MOB3-14 one answer id per question, made once', () {
    test(
      'changing an answer keeps its id; each question has its own',
      () async {
        final c = device();
        await c.load();
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        final id = c.answers['q_single']!.answerId;
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_b']));
        c.setAnswer('q_single', AnswerValue.none); // cleared
        expect(c.answers.containsKey('q_single'), isFalse);
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_c']));
        expect(c.answers['q_single']!.answerId, id);
        c.setAnswer('q_multi', const AnswerValue(optionIds: ['o_a']));
        expect(c.answers['q_multi']!.answerId, isNot(id));
        await settle();
        expect(
          lastSentAnswers().firstWhere(
            (a) => a['question_id'] == 'q_single',
          )['answer_id'],
          id,
        );
        c.dispose();
      },
    );
  });

  group('MOB3-15 answer ids survive autosave retry and resume', () {
    test(
      'offline retry, then resume from the server and from the draft',
      () async {
        final a = device();
        await a.load();
        remote.offline = true;
        a.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        final id = a.answerIds['q_single']!;
        await settle();
        expect(a.saveStatus, SaveStatus.offline);
        a.dispose();

        // Resume on this device from the encrypted draft (still offline-dirty).
        remote.offline = false;
        final resumed = device();
        await resumed.load();
        await settle();
        expect(resumed.answers['q_single']!.answerId, id);
        expect(remote.answersOf('demo_attempt_en').single.answerId, id);
        resumed.dispose();

        // Resume on another device: from the server copy.
        final other = device(store: MemoryDraftBox());
        await other.load();
        expect(other.answers['q_single']!.answerId, id);
        other.dispose();
      },
    );
  });

  group('MOB3-16 answer ids survive the Restart button', () {
    test(
      'same question → same id after Restart, in memory and after resume',
      () async {
        final c = device();
        await c.load();
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        final id = c.answerIds['q_single']!;
        await settle();
        expect(await c.restart(), isTrue);
        expect(remote.answersOf('demo_attempt_en'), isEmpty);
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_b']));
        expect(c.answers['q_single']!.answerId, id);
        c.dispose();

        // App killed right after a Restart (no new answer yet): the draft
        // still knows the id.
        final d = device();
        await d.load();
        expect(await d.restart(), isTrue);
        d.dispose();
        final resumed = device();
        await resumed.load();
        resumed.setAnswer('q_single', const AnswerValue(optionIds: ['o_c']));
        expect(resumed.answers['q_single']!.answerId, id);
        resumed.dispose();
      },
    );
    test('local drafts OFF: nothing is written; after Restart + kill the id is new (documented)', () async {
      final off = MemoryDraftBox();
      final c = device(store: off, drafts: false);
      await c.load();
      c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
      final id = c.answerIds['q_single']!;
      await settle();
      expect(await c.restart(), isTrue);
      c.setAnswer('q_single', const AnswerValue(optionIds: ['o_b']));
      expect(c.answers['q_single']!.answerId, id, reason: 'in memory');
      await settle();
      expect(await c.restart(), isTrue);
      c.dispose();
      expect(off.rows, isEmpty);
      final resumed = device(store: off, drafts: false);
      await resumed.load();
      resumed.setAnswer('q_single', const AnswerValue(optionIds: ['o_c']));
      expect(resumed.answers['q_single']!.answerId, isNot(id));
      resumed.dispose();
    });
  });

  group('MOB3-17 answer ids are uuid v4 made on the device', () {
    test('format', () async {
      final c = device();
      await c.load();
      for (final q in form.questions.where((q) => q.type.isChoice)) {
        c.setAnswer(q.id, AnswerValue(optionIds: [q.options.first.id]));
      }
      final ids = c.answerIds.values.toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(_uuidV4.hasMatch(id), isTrue, reason: id);
        expect(isQuestionnaireId(id), isTrue);
      }
      c.dispose();
    });
  });
}
