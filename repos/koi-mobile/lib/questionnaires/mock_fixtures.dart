// Demo questionnaires for KOI_MOCKS=true (and tests), as the raw JSON a
// server would send: PublishedQuestionnaire + QuestionnaireDraft body
// (// PROVISIONAL CONTRACT, KOI_MOB1_PROVISIONAL_CONTRACTS.md §3). They go
// through the same parser as real data.
//
// PLACEHOLDER wording only. No clinical instrument wording is bundled in
// the app (MOB-1 rule, kept in MOB-3): the WHO-5 and DASS-21 templates are
// test fixtures only (test/fixtures/mob3/).

Map<String, Object?> _option(
  String id,
  String label, {
  String? asset,
  String? visual,
}) => {
  'option_id': id,
  'label': label,
  'asset_id': asset,
  'visual_description': visual,
};

Map<String, Object?> _question(
  String id,
  String type,
  String text, {
  List<Map<String, Object?>> options = const [],
  bool required = true,
  String? help,
  num? min,
  num? max,
  num? step,
  String? asset,
  String? visual,
}) => {
  'question_id': id,
  'type': type,
  'text': text,
  'help_text': help,
  'required': required,
  'options': options,
  'min_value': min,
  'max_value': max,
  'step': step,
  'asset_id': asset,
  'visual_description': visual,
  'source_kind': 'psychologist_authored',
  'source_id': null,
};

Map<String, Object?> _published(String id, Map<String, Object?> body) => {
  'questionnaire_id': id,
  'version': 1,
  'org_id': 'demo_org',
  'status': 'published',
  'body': {
    'category': 'custom_psychologist',
    'validated': false,
    'version': {
      'draft_id': '${id}_d1',
      'version': 1,
      'revision_history': <Object?>[],
      'created_at': '2026-10-20T00:00:00Z',
    },
    'status': 'published',
    ...body,
  },
};

/// Every question type, in English.
Map<String, Object?> demoAllTypesEn() => _published('demo_all_types_en', {
  'title': 'Placeholder form (English)',
  'description': 'Placeholder description. Answer each item.',
  'language': 'en',
  'rtl': false,
  'questions': [
    _question(
      'q_single',
      'single',
      'Placeholder single choice',
      options: [
        _option('o_a', 'Option A'),
        _option('o_b', 'Option B'),
        _option('o_c', 'Option C'),
      ],
    ),
    _question(
      'q_multi',
      'multi',
      'Placeholder multiple choice',
      help: 'Choose one or more.',
      options: [
        _option('o_a', 'Option A'),
        _option('o_b', 'Option B'),
        _option('o_c', 'Option C'),
      ],
    ),
    _question(
      'q_yes_no',
      'yes_no',
      'Placeholder yes or no',
      options: [_option('o_yes', 'Yes'), _option('o_no', 'No')],
    ),
    _question(
      'q_likert',
      'likert',
      'Placeholder scale',
      options: [
        _option('o1', 'Placeholder least'),
        _option('o2', 'Placeholder a little'),
        _option('o3', 'Placeholder middle'),
        _option('o4', 'Placeholder quite a lot'),
        _option('o5', 'Placeholder most'),
      ],
    ),
    _question(
      'q_free_text',
      'free_text',
      'Placeholder free text',
      required: false,
      help: 'Optional. Up to 4000 characters.',
    ),
    _question(
      'q_numeric',
      'numeric',
      'Placeholder number',
      help: 'A whole number from 0 to 10.',
      min: 0,
      max: 10,
      step: 1,
    ),
    _question(
      'q_image_single',
      'image_single',
      'Placeholder picture choice',
      asset: 'placeholder_triangle_v1',
      visual: 'Green triangle',
      options: [
        _option('img_circle', 'Circle', asset: 'placeholder_circle_v1'),
        _option('img_square', 'Square', asset: 'placeholder_square_v1'),
        _option('img_triangle', 'Triangle', asset: 'placeholder_triangle_v1'),
      ],
    ),
    _question(
      'q_image_multi',
      'image_multi',
      'Placeholder pictures (choose any)',
      required: false,
      options: [
        _option('img_circle', 'Circle', asset: 'placeholder_circle_v1'),
        _option('img_square', 'Square', asset: 'placeholder_square_v1'),
        // Not in the manifest: its visual description is shown instead.
        _option(
          'img_missing',
          'Star',
          asset: 'placeholder_star_v1',
          visual: 'A five-pointed star',
        ),
        // No picture at all, only a description.
        _option('img_text_only', 'Moon', visual: 'A crescent moon'),
      ],
    ),
  ],
  'sources': [
    {
      'source_id': 'demo_source',
      'kind': 'psychologist_authored',
      'title': 'Placeholder source',
      'citation': 'Placeholder citation (demo data only).',
      'attribution_text': 'Placeholder attribution (demo data only).',
      'redistribution_reviewed': false,
    },
  ],
});

/// Urdu (right-to-left, Noto Nastaliq Urdu).
Map<String, Object?> demoUrdu() => _published('demo_urdu', {
  'title': 'نمونہ فارم (اردو)',
  'description': 'نمونہ ہدایات۔ ہر سوال کا جواب دیں۔',
  'language': 'ur',
  'rtl': true,
  'questions': [
    _question(
      'q_single',
      'single',
      'نمونہ سوال ایک',
      options: [
        _option('o_a', 'اختیار الف'),
        _option('o_b', 'اختیار ب'),
        _option('o_c', 'اختیار ج'),
      ],
    ),
    _question(
      'q_yes_no',
      'yes_no',
      'نمونہ سوال دو',
      options: [_option('o_yes', 'ہاں'), _option('o_no', 'نہیں')],
    ),
    _question(
      'q_likert',
      'likert',
      'نمونہ سوال تین',
      options: [
        _option('o1', 'نمونہ کم'),
        _option('o2', 'نمونہ درمیانہ'),
        _option('o3', 'نمونہ زیادہ'),
      ],
    ),
    _question(
      'q_free_text',
      'free_text',
      'نمونہ مختصر جواب',
      required: false,
      help: 'اختیاری',
    ),
    _question('q_numeric', 'numeric', 'نمونہ عدد', min: 1, max: 5, step: 1),
    _question(
      'q_image_single',
      'image_single',
      'نمونہ تصویر',
      options: [
        _option('img_circle', 'دائرہ', asset: 'placeholder_circle_v1'),
        _option('img_square', 'چوکور', asset: 'placeholder_square_v1'),
      ],
    ),
  ],
  'sources': <Object?>[],
});

/// Roman Urdu (Latin script, left-to-right).
Map<String, Object?> demoRomanUrdu() => _published('demo_roman_ur', {
  'title': 'Namoona form (Roman Urdu)',
  'description': 'Namoona hidayat. Har sawal ka jawab dein.',
  'language': 'roman_ur',
  'rtl': false,
  'questions': [
    _question(
      'q_single',
      'single',
      'Namoona sawal ek',
      options: [_option('o_a', 'Ikhtiyar A'), _option('o_b', 'Ikhtiyar B')],
    ),
    _question(
      'q_multi',
      'multi',
      'Namoona sawal do',
      options: [
        _option('o_a', 'Ikhtiyar A'),
        _option('o_b', 'Ikhtiyar B'),
        _option('o_c', 'Ikhtiyar C'),
      ],
    ),
    _question(
      'q_yes_no',
      'yes_no',
      'Namoona sawal teen',
      options: [_option('o_yes', 'Haan'), _option('o_no', 'Nahin')],
    ),
    _question(
      'q_likert',
      'likert',
      'Namoona sawal chaar',
      options: [
        _option('o1', 'Namoona kam'),
        _option('o2', 'Namoona thora'),
        _option('o3', 'Namoona kaafi'),
        _option('o4', 'Namoona zyada'),
      ],
    ),
    _question(
      'q_free_text',
      'free_text',
      'Namoona mukhtasar jawab',
      required: false,
    ),
    _question(
      'q_image_multi',
      'image_multi',
      'Namoona tasveerein',
      options: [
        _option('img_circle', 'Daira', asset: 'placeholder_circle_v1'),
        _option('img_square', 'Chokor', asset: 'placeholder_square_v1'),
      ],
    ),
  ],
});
