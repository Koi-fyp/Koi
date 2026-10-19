import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'questionnaire_models.dart';

/// One bundled picture: the asset path and its alt label per locale.
@immutable
class QuestionnaireAsset {
  const QuestionnaireAsset({required this.path, required this.alt});

  final String path;
  final Map<String, String> alt;

  String? altFor(QuestionnaireLocale locale) => alt[locale.wire];
}

/// The shared, versioned asset manifest bundled with the app
/// (assets/questionnaire_assets/manifest.json). Picture options refer to
/// asset IDS only; the app never loads a remote URL or Firebase Storage.
///
/// [resolve] returns null for an unknown id, or when the questionnaire
/// version was made for a different manifest version: the renderer then
/// shows an accessible fallback with the option's label, never a different
/// picture.
class QuestionnaireAssetManifest {
  const QuestionnaireAssetManifest({
    required this.version,
    required this.assets,
  });

  static const String folder = 'assets/questionnaire_assets/';
  static const String manifestPath = '${folder}manifest.json';

  /// Nothing bundled (e.g. the manifest failed to load).
  static const QuestionnaireAssetManifest empty = QuestionnaireAssetManifest(
    version: '',
    assets: {},
  );

  final String version;
  final Map<String, QuestionnaireAsset> assets;

  QuestionnaireAsset? resolve(String assetId, {String? forManifestVersion}) {
    if (forManifestVersion != null && forManifestVersion != version) {
      return null;
    }
    return assets[assetId];
  }

  factory QuestionnaireAssetManifest.fromJson(Object? v) {
    final j = (v! as Map).cast<String, Object?>();
    final raw = (j['assets']! as Map).cast<String, Object?>();
    return QuestionnaireAssetManifest(
      version: j['manifest_version']! as String,
      assets: {
        for (final e in raw.entries)
          e.key: QuestionnaireAsset(
            path: '$folder${(e.value! as Map)['file']}',
            alt: ((e.value! as Map)['alt'] as Map? ?? const {})
                .cast<String, String>(),
          ),
      },
    );
  }

  static Future<QuestionnaireAssetManifest> load([AssetBundle? bundle]) async {
    try {
      final text = await (bundle ?? rootBundle).loadString(manifestPath);
      return QuestionnaireAssetManifest.fromJson(jsonDecode(text));
    } catch (e) {
      debugPrint('[KOI] questionnaire assets unavailable (${e.runtimeType})');
      return empty;
    }
  }
}
