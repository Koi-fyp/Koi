import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';
import 'package:koi_mobile/widgets/koi_loader.dart';

/// The new MOB-1 feature folders.
const _featureDirs = [
  'lib/account',
  'lib/experts',
  'lib/platform',
  'lib/questionnaires',
];

Iterable<File> _dartFiles(List<String> dirs) sync* {
  for (final d in dirs) {
    for (final f in Directory(d).listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) yield f;
    }
  }
}

/// Code only: comments stripped (the colour names in doc comments are
/// fine; literals in code are not).
String _code(File f) => f
    .readAsLinesSync()
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  group('MOB1-36 new screens use only the KOI design system', () {
    test('no hard-coded colour hex values in the new feature folders', () {
      final hex = RegExp(
        r'Color\(\s*0x|Color\.fromARGB|Color\.fromRGBO|#[0-9a-fA-F]{6}\b|0x[0-9a-fA-F]{8}',
      );
      final offenders = [
        for (final f in [
          ..._dartFiles(_featureDirs),
          File('lib/widgets/koi_loader.dart'),
        ])
          if (hex.hasMatch(_code(f))) f.path,
      ];
      expect(offenders, isEmpty);
    });
    test('no new font families outside the theme files', () {
      final fonts = RegExp(r'fontFamily\s*:|GoogleFonts\.|fontFamilyFallback');
      final offenders = [
        for (final f in [
          ..._dartFiles(_featureDirs),
          File('lib/widgets/koi_loader.dart'),
        ])
          if (fonts.hasMatch(_code(f))) f.path,
      ];
      expect(offenders, isEmpty);
    });
    test('no third-party UI kit imported', () {
      final allowed = RegExp(
        r"^import '(dart:|package:flutter/|package:flutter_riverpod/|package:dio/|package:hive/|package:flutter_secure_storage/|package:url_launcher/|\.\.?/|[a-z_]+\.dart')",
      );
      final offenders = <String>[];
      for (final f in _dartFiles(_featureDirs)) {
        for (final l in f.readAsLinesSync().where(
          (l) => l.startsWith('import '),
        )) {
          if (!allowed.hasMatch(l)) offenders.add('${f.path}: $l');
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('MOB1-33 patient DTOs/models carry NO score / evaluation fields', () {
    // Patient-side models and DTO parsers.
    const files = [
      'lib/questionnaires/questionnaire_models.dart',
      'lib/questionnaires/questionnaire_api.dart',
      'lib/questionnaires/questionnaire_wire.dart',
      'lib/questionnaires/draft_store.dart',
      'lib/questionnaires/attempt_controller.dart',
      'lib/account/capabilities.dart',
      'lib/experts/expert_api.dart',
    ];
    final forbidden = RegExp(
      r'scor(e|es|ing)|evaluat|interpret|\bjob|review|severity|diagnos|\bresult|ai_|agent_?router|clinician_',
      caseSensitive: false,
    );

    test('source scan of every patient model / DTO file (code only)', () {
      final hits = <String>[];
      for (final p in files) {
        final lines = _code(File(p)).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (forbidden.hasMatch(lines[i])) {
            hits.add('$p:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(hits, isEmpty);
    });

    test('extra server fields are dropped, never kept or re-sent', () {
      final attempt = parseAttempt({
        'id': 'a',
        'assignment_id': 's',
        'patient_uid': 'p',
        'version_id': 'v',
        'status': 'in_progress',
        'revision': 3,
        'server_updated_at': '2026-10-19T10:00:00Z',
        'answers': [
          {
            'answer_id': 'x1',
            'question_id': 'q1',
            'option_ids': ['x'],
            'value': null,
            'text': null,
            'score': 4,
            'evaluation': 'hidden',
          },
        ],
        'score': 12,
        'evaluation_status': 'pending',
        'ai_job_id': 'j1',
      });
      expect(encodeAnswer(attempt.answers.single), {
        'answer_id': 'x1',
        'question_id': 'q1',
        'option_ids': ['x'],
        'value': null,
        'text': null,
      });
      final ack = parseSubmitAck({
        'attempt_id': 'a',
        'assignment_id': 's',
        'status': 'submitted',
        'submitted_at': '2026-10-19T10:00:00Z',
        'score': 12,
        'review_status': 'queued',
      });
      expect(ack.attemptId, 'a');
    });

    test('the app never calls psychologist-only, review or AI endpoints', () {
      final calls = RegExp(r"'/api/[^']*'|'\$_p/[^']*'");
      final bad = RegExp(
        r'psycholog|review|evaluat|score|agent|/ai/',
        caseSensitive: false,
      );
      final hits = <String>[];
      for (final f in _dartFiles(_featureDirs)) {
        for (final m in calls.allMatches(_code(f))) {
          if (bad.hasMatch(m.group(0)!)) hits.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(hits, isEmpty);
    });
  });

  group('MOB1-35 reduced motion', () {
    testWidgets('KoiLoader animates normally', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: KoiLoader(label: 'Loading')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });
    testWidgets('…and is completely still with "Remove animations"', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(child: KoiLoader(label: 'Loading')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
      expect(
        find.bySemanticsLabel('Loading'),
        findsOneWidget,
        reason: 'still labelled',
      );
    });
    testWidgets('skeleton list is still too', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: NeoSkeletonList()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
