import 'asset_manifest.dart';

// Demo questionnaires for KOI_MOCKS=true (and tests), as the raw JSON a
// server sends: contract v0.5.2 `PatientQuestionnaireDTO` (MOB-6). They go
// through the same strict parser as real data.
//
// PLACEHOLDER wording only. No clinical instrument wording is bundled in
// the app (MOB-1 rule, kept since): the WHO-5 and DASS-21 templates are
// test fixtures only (test/fixtures/mob3/).

/// LocalizedText with the given texts.
Map<String, Object?> _t(String en, [String? ur, String? romanUr]) => {
  'en': en,
  'ur': ?ur,
  'ur-Latn': ?romanUr,
};

Map<String, Object?> _option(String id, Map<String, Object?> label) => {
  'id': id,
  'label': label,
};

/// An `ImageOption` whose asset is one of the bundled placeholder pictures,
/// with its pinned `{asset_id, version, sha256}`.
Map<String, Object?> _picture(
  String id,
  Map<String, Object?> label,
  String assetId,
) {
  final ref = QuestionnaireAssetManifest.bundledReferences[assetId]!;
  return {
    'id': id,
    'label': label,
    'asset': {
      'asset_id': ref.assetId,
      'version': ref.version,
      'sha256': ref.sha256,
    },
  };
}

Map<String, Object?> _question(
  String id,
  String type,
  Map<String, Object?> prompt, {
  bool required = true,
  List<Map<String, Object?>>? options,
  int? maxLength,
  int? minSelections,
  int? maxSelections,
}) => {
  'id': id,
  'type': type,
  'prompt': prompt,
  'required': required,
  'options': ?options,
  'max_length': ?maxLength,
  'min_selections': ?minSelections,
  'max_selections': ?maxSelections,
};

Map<String, Object?> _questionnaire(
  String versionId,
  Map<String, Object?> title,
  List<String> locales,
  List<Map<String, Object?>> questions,
) => {
  'version_id': versionId,
  'schema_version': '0.5.0',
  'title': title,
  'locales': locales,
  'questions': questions,
};

/// Every question type, in English, Urdu and Roman Urdu (the language
/// chips show).
Map<String, Object?> demoAllTypesEn([
  String versionId = 'demo_version_en',
]) => _questionnaire(
  versionId,
  _t('Placeholder form (English)', 'نمونہ فارم', 'Namoona form'),
  const ['en', 'ur', 'ur-Latn'],
  [
    _question(
      'q_single',
      'single_choice',
      _t('Placeholder single choice', 'نمونہ سوال ایک', 'Namoona sawal ek'),
      options: [
        _option('o_a', _t('Option A', 'اختیار الف', 'Ikhtiyar A')),
        _option('o_b', _t('Option B', 'اختیار ب', 'Ikhtiyar B')),
        _option('o_c', _t('Option C', 'اختیار ج', 'Ikhtiyar C')),
      ],
    ),
    _question(
      'q_multi',
      'multi_choice',
      _t(
        'Placeholder multiple choice',
        'نمونہ کثیر انتخاب',
        'Namoona kayi intikhab',
      ),
      minSelections: 2,
      maxSelections: 3,
      options: [
        _option('o_a', _t('Option A', 'اختیار الف', 'Ikhtiyar A')),
        _option('o_b', _t('Option B', 'اختیار ب', 'Ikhtiyar B')),
        _option('o_c', _t('Option C', 'اختیار ج', 'Ikhtiyar C')),
        _option('o_d', _t('Option D', 'اختیار د', 'Ikhtiyar D')),
      ],
    ),
    _question(
      'q_yes_no',
      'yes_no',
      _t('Placeholder yes or no', 'نمونہ ہاں یا نہیں', 'Namoona haan ya nahin'),
    ),
    _question(
      'q_likert',
      'likert',
      _t('Placeholder scale', 'نمونہ پیمانہ', 'Namoona paimana'),
      options: [
        _option('o1', _t('Placeholder least', 'نمونہ کم', 'Namoona kam')),
        _option(
          'o2',
          _t('Placeholder a little', 'نمونہ تھوڑا', 'Namoona thora'),
        ),
        _option(
          'o3',
          _t('Placeholder middle', 'نمونہ درمیانہ', 'Namoona darmiyana'),
        ),
        _option(
          'o4',
          _t('Placeholder quite a lot', 'نمونہ کافی', 'Namoona kaafi'),
        ),
        _option('o5', _t('Placeholder most', 'نمونہ زیادہ', 'Namoona zyada')),
      ],
    ),
    _question(
      'q_short_text',
      'short_text',
      _t(
        'Placeholder short answer',
        'نمونہ مختصر جواب',
        'Namoona mukhtasar jawab',
      ),
      required: false,
      maxLength: 500,
    ),
    _question(
      'q_image_single',
      'image_single_choice',
      _t('Placeholder picture choice', 'نمونہ تصویر', 'Namoona tasveer'),
      options: [
        _picture(
          'img_circle',
          _t('Circle', 'دائرہ', 'Daira'),
          'placeholder_circle_v1',
        ),
        _picture(
          'img_square',
          _t('Square', 'چوکور', 'Chokor'),
          'placeholder_square_v1',
        ),
        _picture(
          'img_triangle',
          _t('Triangle', 'تکون', 'Tikon'),
          'placeholder_triangle_v1',
        ),
      ],
    ),
    _question(
      'q_image_multi',
      'image_multi_choice',
      _t(
        'Placeholder pictures (choose any)',
        'نمونہ تصاویر',
        'Namoona tasveerein',
      ),
      required: false,
      minSelections: 0,
      maxSelections: 2,
      options: [
        _picture(
          'img_circle',
          _t('Circle', 'دائرہ', 'Daira'),
          'placeholder_circle_v1',
        ),
        _picture(
          'img_square',
          _t('Square', 'چوکور', 'Chokor'),
          'placeholder_square_v1',
        ),
        _picture(
          'img_triangle',
          _t('Triangle', 'تکون', 'Tikon'),
          'placeholder_triangle_v1',
        ),
      ],
    ),
  ],
);

Map<String, Object?> _ur(String text) => {'ur': text};

/// Urdu only (right-to-left, Noto Nastaliq Urdu).
Map<String, Object?> demoUrdu([String versionId = 'demo_version_ur']) =>
    _questionnaire(
      versionId,
      _ur('نمونہ فارم (اردو)'),
      const ['ur'],
      [
        _question(
          'q_single',
          'single_choice',
          _ur('نمونہ سوال ایک'),
          options: [
            _option('o_a', _ur('اختیار الف')),
            _option('o_b', _ur('اختیار ب')),
            _option('o_c', _ur('اختیار ج')),
          ],
        ),
        _question('q_yes_no', 'yes_no', _ur('نمونہ سوال دو')),
        _question(
          'q_likert',
          'likert',
          _ur('نمونہ سوال تین'),
          options: [
            _option('o1', _ur('نمونہ کم')),
            _option('o2', _ur('نمونہ درمیانہ')),
            _option('o3', _ur('نمونہ زیادہ')),
          ],
        ),
        _question(
          'q_short_text',
          'short_text',
          _ur('نمونہ مختصر جواب'),
          required: false,
          maxLength: 4000,
        ),
        _question(
          'q_image_single',
          'image_single_choice',
          _ur('نمونہ تصویر'),
          options: [
            _picture('img_circle', _ur('دائرہ'), 'placeholder_circle_v1'),
            _picture('img_square', _ur('چوکور'), 'placeholder_square_v1'),
          ],
        ),
      ],
    );

Map<String, Object?> _rom(String text) => {'ur-Latn': text};

/// Roman Urdu only (Latin script, left-to-right).
Map<String, Object?> demoRomanUrdu([String versionId = 'demo_version_roman']) =>
    _questionnaire(
      versionId,
      _rom('Namoona form (Roman Urdu)'),
      const ['ur-Latn'],
      [
        _question(
          'q_single',
          'single_choice',
          _rom('Namoona sawal ek'),
          options: [
            _option('o_a', _rom('Ikhtiyar A')),
            _option('o_b', _rom('Ikhtiyar B')),
          ],
        ),
        _question(
          'q_multi',
          'multi_choice',
          _rom('Namoona sawal do'),
          minSelections: 1,
          maxSelections: 3,
          options: [
            _option('o_a', _rom('Ikhtiyar A')),
            _option('o_b', _rom('Ikhtiyar B')),
            _option('o_c', _rom('Ikhtiyar C')),
          ],
        ),
        _question('q_yes_no', 'yes_no', _rom('Namoona sawal teen')),
        _question(
          'q_likert',
          'likert',
          _rom('Namoona sawal chaar'),
          options: [
            _option('o1', _rom('Namoona kam')),
            _option('o2', _rom('Namoona thora')),
            _option('o3', _rom('Namoona kaafi')),
            _option('o4', _rom('Namoona zyada')),
          ],
        ),
        _question(
          'q_short_text',
          'short_text',
          _rom('Namoona mukhtasar jawab'),
          required: false,
          maxLength: 1000,
        ),
      ],
    );
