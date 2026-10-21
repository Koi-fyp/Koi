import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/core/crypto_context.dart';
import 'package:koi_mobile/questionnaires/attempt_controller.dart';
import 'package:koi_mobile/questionnaires/draft_store.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/mock_questionnaire_api.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

import '../support/mob1_fakes.dart';

// MOB-6: rewritten for the contract v0.5.2 Answer `{question_id, type,
// value}`. MOB3-12 (numeric), MOB3-14 and MOB3-17 (answer ids) are retired:
// v0.5.2 has neither; see the MOB-6 report.

void main() {
  final form = parsePatientQuestionnaire(demoAllTypesEn());
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

  group('MOB3-09 the answer shape is exactly the v0.5.2 Answer', () {
    test('{question_id, type, value} and nothing else', () {
      expect(
        encodeAnswer(
          const Answer(
            questionId: 'q1',
            type: QuestionType.single,
            value: 'o1',
          ),
        ),
        {'question_id': 'q1', 'type': 'single_choice', 'value': 'o1'},
      );
      expect(
        encodeAnswer(
          const Answer(
            questionId: 'q2',
            type: QuestionType.multi,
            value: ['o1', 'o2'],
          ),
        ),
        {
          'question_id': 'q2',
          'type': 'multi_choice',
          'value': ['o1', 'o2'],
        },
      );
      expect(
        encodeAnswer(
          const Answer(
            questionId: 'q3',
            type: QuestionType.yesNo,
            value: false,
          ),
        ),
        {'question_id': 'q3', 'type': 'yes_no', 'value': false},
      );
      const text = Answer(
        questionId: 'q4',
        type: QuestionType.shortText,
        value: 'hi',
      );
      expect(decodeAnswer(encodeAnswer(text)), text);
    });
    test('malformed answers from the server are refused', () {
      for (final bad in <Object?>[
        {'question_id': 'q1', 'type': 'single_choice'},
        {'question_id': 'q 1', 'type': 'single_choice', 'value': 'o1'},
        {
          'question_id': 'q1',
          'type': 'single_choice',
          'value': ['o1'],
        },
        {'question_id': 'q1', 'type': 'multi_choice', 'value': 'o1'},
        {
          'question_id': 'q1',
          'type': 'multi_choice',
          'value': ['a', 'a'],
        },
        {'question_id': 'q1', 'type': 'yes_no', 'value': 'yes'},
        {'question_id': 'q1', 'type': 'short_text', 'value': 5},
        {'question_id': 'q1', 'type': 'numeric', 'value': 5},
        {
          'answer_id': 'a1',
          'question_id': 'q1',
          'type': 'single_choice',
          'value': 'o1',
        },
        'nope',
      ]) {
        expect(
          () => decodeAnswer(bad),
          throwsA(isA<FormatException>()),
          reason: '$bad',
        );
      }
    });
  });

  group('MOB3-10 each type is sent with the right value', () {
    test('choice → option id; multi → option ids; yes_no → bool; '
        'short_text → text', () async {
      final c = device();
      await c.load();
      c
        ..setAnswer('q_single', const AnswerValue(optionIds: ['o_b']))
        ..setAnswer('q_multi', const AnswerValue(optionIds: ['o_c', 'o_a']))
        ..setAnswer('q_yes_no', const AnswerValue(yes: false))
        ..setAnswer('q_likert', const AnswerValue(optionIds: ['o5']))
        ..setAnswer('q_short_text', const AnswerValue(text: 'Some words'))
        ..setAnswer(
          'q_image_single',
          const AnswerValue(optionIds: ['img_circle']),
        )
        ..setAnswer(
          'q_image_multi',
          const AnswerValue(optionIds: ['img_square', 'img_triangle']),
        );
      await settle();
      final sent = {for (final a in lastSentAnswers()) a['question_id']: a};
      expect(sent.keys, form.questions.map((q) => q.id), reason: 'form order');
      expect(sent['q_single']!['value'], 'o_b');
      expect(sent['q_multi']!['value'], ['o_c', 'o_a']);
      expect(sent['q_yes_no']!['value'], false);
      expect(sent['q_likert']!['value'], 'o5');
      expect(sent['q_short_text']!['value'], 'Some words');
      expect(sent['q_image_single']!['value'], 'img_circle');
      expect(sent['q_image_multi']!['value'], ['img_square', 'img_triangle']);
      for (final q in form.questions) {
        expect(sent[q.id]!['type'], q.type.wire);
        expect(sent[q.id]!.keys.toSet(), {'question_id', 'type', 'value'});
      }
      c.dispose();
    });
  });

  group('MOB3-11 question_id / option_id values are never altered', () {
    test('ids are matched byte for byte (case, dashes, no trimming)', () {
      final q = parsePatientQuestionnaire({
        'version_id': 'v1',
        'schema_version': '0.5.0',
        'title': {'en': 'T'},
        'locales': ['en'],
        'questions': [
          {
            'id': 'Q-1_x',
            'type': 'multi_choice',
            'prompt': {'en': 'T'},
            'required': true,
            'min_selections': 0,
            'max_selections': 2,
            'options': [
              {
                'id': 'Opt-A_1',
                'label': {'en': 'A'},
              },
              {
                'id': 'opt-a_1',
                'label': {'en': 'B'},
              },
            ],
          },
        ],
      });
      Map<String, Answer> clean(String qid, List<String> ids) =>
          sanitizeAnswers(q, {
            qid: Answer(questionId: qid, type: QuestionType.multi, value: ids),
          });
      expect(clean('Q-1_x', ['Opt-A_1', 'opt-a_1'])['Q-1_x']!.optionIds, [
        'Opt-A_1',
        'opt-a_1',
      ]);
      for (final bad in [
        ['OPT-A_1'],
        ['Opt-A_1 '],
      ]) {
        expect(clean('Q-1_x', bad), isEmpty, reason: '$bad');
      }
      expect(
        clean('q-1_x', ['Opt-A_1']),
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
      expect(lastSentAnswers().single, {
        'question_id': 'q_image_single',
        'type': 'image_single_choice',
        'value': 'img_triangle',
      });
      c.dispose();
    });
  });

  group('MOB3-13 short text holds at most its max_length', () {
    test('500 kept, 501 refused, empty removes the answer', () {
      Map<String, Answer> clean(String t) => sanitizeAnswers(form, {
        'q_short_text': Answer(
          questionId: 'q_short_text',
          type: QuestionType.shortText,
          value: t,
        ),
      });
      expect(form.question('q_short_text')!.maxLength, 500);
      expect(clean('x' * 500)['q_short_text']!.text!.length, 500);
      expect(clean('x' * 501), isEmpty);
      expect(clean(''), isEmpty);
      expect(
        clean('  spaced  ')['q_short_text']!.text,
        '  spaced  ',
        reason: 'not trimmed',
      );
    });
  });

  group('MOB3-15 answers survive autosave retry and resume', () {
    test(
      'offline retry, then resume from the draft and from the server',
      () async {
        final a = device();
        await a.load();
        remote.offline = true;
        a.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        await settle();
        expect(a.saveStatus, SaveStatus.offline);
        a.dispose();

        // Resume on this device from the encrypted draft (still offline-dirty).
        remote.offline = false;
        final resumed = device();
        await resumed.load();
        await settle();
        expect(resumed.answers['q_single']!.value, 'o_a');
        expect(remote.answersOf('demo_attempt_en').single.value, 'o_a');
        resumed.dispose();

        // Resume on another device: from the server copy.
        final other = device(store: MemoryDraftBox());
        await other.load();
        expect(other.answers['q_single']!.value, 'o_a');
        other.dispose();
      },
    );
  });

  group('MOB3-16 Restart clears the attempt everywhere', () {
    test(
      'server copy empty; a resume after Restart shows no answers',
      () async {
        final c = device();
        await c.load();
        c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
        await settle();
        expect(await c.restart(), isTrue);
        expect(remote.answersOf('demo_attempt_en'), isEmpty);
        expect(remote.autosaveBodies.last, {
          'expected_revision': 1,
          'answers': <Object?>[],
        });
        c.dispose();
        final resumed = device();
        await resumed.load();
        expect(resumed.answers, isEmpty);
        resumed.dispose();
      },
    );
    test('local drafts OFF: nothing is written', () async {
      final off = MemoryDraftBox();
      final c = device(store: off, drafts: false);
      await c.load();
      c.setAnswer('q_single', const AnswerValue(optionIds: ['o_a']));
      await settle();
      expect(await c.restart(), isTrue);
      c.dispose();
      expect(off.rows, isEmpty);
    });
  });
}
