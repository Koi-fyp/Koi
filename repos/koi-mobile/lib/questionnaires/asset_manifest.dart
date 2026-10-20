import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'questionnaire_models.dart';

/// One bundled picture (`AssetManifestEntry`).
@immutable
class QuestionnaireAsset {
  const QuestionnaireAsset({
    required this.assetId,
    required this.kind,
    required this.visualDescription,
    this.license,
  });

  final String assetId;
  final String kind;

  /// The picture's text equivalent (semantics label).
  final String visualDescription;
  final String? license;

  String get path => '${QuestionnaireAssetManifest.folder}$assetId.png';
}

/// The bundled asset_id library: `assets/questionnaire/<asset_id>.png` plus
/// manifest.json in the AI repo's manifest format
/// (`{"assets": [{asset_id, kind, visual_description, license}]}`,
/// KOI-Psycholov MOBILE_HANDOFF.md §3, AssetManifestEntry.json).
/// // PROVISIONAL CONTRACT: how the library is shipped is open (AI question
/// M2); KOI_MOB1_PROVISIONAL_CONTRACTS.md §6.
///
/// Pictures are referenced by asset id ONLY: never a URL, never Firebase
/// Storage, never a remote load. [resolve] returns null for an unknown or
/// malformed id; the renderer then shows the visual description text.
class QuestionnaireAssetManifest {
  const QuestionnaireAssetManifest({required this.assets});

  static const String folder = 'assets/questionnaire/';
  static const String manifestPath = '${folder}manifest.json';

  /// Nothing bundled (e.g. the manifest failed to load).
  static const QuestionnaireAssetManifest empty = QuestionnaireAssetManifest(
    assets: {},
  );

  final Map<String, QuestionnaireAsset> assets;

  QuestionnaireAsset? resolve(String? assetId) =>
      isQuestionnaireId(assetId) ? assets[assetId] : null;

  /// Entries with a malformed id or missing fields are skipped.
  factory QuestionnaireAssetManifest.fromJson(Object? v) {
    final raw = ((v! as Map)['assets']! as List).cast<Object?>();
    final out = <String, QuestionnaireAsset>{};
    for (final e in raw) {
      if (e is! Map) continue;
      final id = e['asset_id'];
      final kind = e['kind'];
      final visual = e['visual_description'];
      final license = e['license'];
      if (!isQuestionnaireId(id) || kind is! String || visual is! String) {
        continue;
      }
      out[id! as String] = QuestionnaireAsset(
        assetId: id as String,
        kind: kind,
        visualDescription: visual,
        license: license is String ? license : null,
      );
    }
    return QuestionnaireAssetManifest(assets: Map.unmodifiable(out));
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
