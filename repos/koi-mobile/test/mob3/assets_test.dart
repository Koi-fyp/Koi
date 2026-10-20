import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_mobile/questionnaires/asset_manifest.dart';
import 'package:koi_mobile/questionnaires/mock_fixtures.dart';
import 'package:koi_mobile/questionnaires/questionnaire_models.dart';
import 'package:koi_mobile/questionnaires/questionnaire_wire.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MOB3-28 the asset manifest is the AI repo format', () {
    test('parses {"assets": [...]} and skips bad entries', () {
      final m = QuestionnaireAssetManifest.fromJson({
        'assets': [
          {
            'asset_id': 'sleep_moon_01',
            'kind': 'illustration',
            'visual_description': 'A crescent moon over a bed',
            'license': 'CC0',
          },
          {
            'asset_id': 'https://x/y.png',
            'kind': 'x',
            'visual_description': 'x',
          },
          {'asset_id': 'no_kind', 'visual_description': 'x'},
          'junk',
        ],
      });
      expect(m.assets.keys, ['sleep_moon_01']);
      final a = m.resolve('sleep_moon_01')!;
      expect(a.path, 'assets/questionnaire/sleep_moon_01.png');
      expect(a.license, 'CC0');
      expect(m.resolve('unknown_id'), isNull);
      expect(m.resolve('../sleep_moon_01'), isNull);
      expect(m.resolve(null), isNull);
    });
    test(
      'the bundled manifest loads; a missing manifest means text only',
      () async {
        final m = await QuestionnaireAssetManifest.load();
        expect(m.assets.keys.toSet(), {
          'placeholder_circle_v1',
          'placeholder_square_v1',
          'placeholder_triangle_v1',
        });
        final missing = await QuestionnaireAssetManifest.load(_EmptyBundle());
        expect(missing.assets, isEmpty);
      },
    );
  });

  group('MOB3-29 the three MOB-1 placeholder pictures still work', () {
    test('valid ids, files on disk and in the bundle, AI keys only', () async {
      final raw = jsonDecode(
        File('assets/questionnaire/manifest.json').readAsStringSync(),
      ) as Map;
      expect(raw.keys, ['assets']);
      for (final e in (raw['assets'] as List).cast<Map>()) {
        expect(e.keys.toSet(), {
          'asset_id',
          'kind',
          'visual_description',
          'license',
        });
        final id = e['asset_id'] as String;
        expect(isQuestionnaireId(id), isTrue, reason: id);
        expect(File('assets/questionnaire/$id.png').existsSync(), isTrue);
        final png = await rootBundle.load('assets/questionnaire/$id.png');
        expect(png.lengthInBytes, greaterThan(0));
      }
      expect(Directory('assets/questionnaire_assets').existsSync(), isFalse);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- assets/questionnaire/'),
      );
    });
    test(
      'every asset id in the demo fixtures is either bundled or has a text',
      () async {
        final m = await QuestionnaireAssetManifest.load();
        for (final f in [demoAllTypesEn(), demoUrdu(), demoRomanUrdu()]) {
          final q = parsePublishedQuestionnaire(f);
          for (final question in q.questions) {
            for (final o in question.options.where((o) => o.assetId != null)) {
              expect(
                m.resolve(o.assetId) != null || o.visualDescription != null,
                isTrue,
                reason: '${q.questionnaireId}/${o.id}',
              );
            }
          }
        }
      },
    );
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw StateError('not bundled: $key');
}
