import 'package:flutter/foundation.dart';

/// The seven parts of a personal safety plan (a widely used
/// safety-planning approach: Stanley & Brown). The order is the order on
/// screen.
// NEEDS CLINICIAN REVIEW: the section list and every section text
// (care_strings.dart, CareText.sp*) were drafted for development.
enum SafetyPlanSection {
  warningSigns('warning_signs'),
  copingAlone('coping_alone'),
  distractions('distractions'),
  peopleToAsk('people_to_ask'),
  professionals('professionals'),
  saferSurroundings('safer_surroundings'),
  reasons('reasons');

  const SafetyPlanSection(this.id);

  /// The JSON key (stable; never shown).
  final String id;

  /// Sections whose items may carry a phone number.
  bool get hasPhone => this == peopleToAsk || this == professionals;

  static SafetyPlanSection? fromId(Object? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// One line the user wrote, with an optional phone number (people and
/// professionals only).
@immutable
class SafetyPlanItem {
  const SafetyPlanItem({required this.id, required this.text, this.phone});

  static const int maxText = 300;
  static const int maxPhone = 20;

  final String id;
  final String text;
  final String? phone;

  /// Digits, spaces, `+`, `-`, `(` and `)` only.
  static final RegExp phoneChars = RegExp(r'^[0-9+\-() ]*$');

  /// Trims and cuts [text] to [maxText]; a blank or invalid phone becomes
  /// null. Returns null when nothing is left to save.
  static SafetyPlanItem? clean({
    required String id,
    required String text,
    String? phone,
  }) {
    var t = text.trim();
    if (t.isEmpty) return null;
    if (t.length > maxText) t = t.substring(0, maxText);
    var p = phone?.trim();
    if (p != null &&
        (p.isEmpty ||
            p.length > maxPhone ||
            !phoneChars.hasMatch(p) ||
            !p.contains(RegExp('[0-9]')))) {
      p = null;
    }
    return SafetyPlanItem(id: id, text: t, phone: p);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    if (phone != null) 'phone': phone,
  };

  static SafetyPlanItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    final phone = raw['phone'];
    if (id is! String || text is! String) return null;
    return clean(id: id, text: text, phone: phone is String ? phone : null);
  }

  @override
  bool operator ==(Object other) =>
      other is SafetyPlanItem &&
      other.id == id &&
      other.text == text &&
      other.phone == phone;

  @override
  int get hashCode => Object.hash(id, text, phone);
}

/// The whole plan. 1166 is NOT stored: the screens always show it first in
/// [SafetyPlanSection.professionals], so it can never be edited or deleted.
///
/// There is deliberately no score, progress or "completeness" here.
@immutable
class SafetyPlan {
  SafetyPlan({
    Map<SafetyPlanSection, List<SafetyPlanItem>> items = const {},
    this.updatedAt,
  }) : items = Map.unmodifiable({
         for (final s in SafetyPlanSection.values)
           s: List<SafetyPlanItem>.unmodifiable(
             (items[s] ?? const <SafetyPlanItem>[])
                 .take(maxItems)
                 .map(
                   (i) =>
                       s.hasPhone ? i : SafetyPlanItem(id: i.id, text: i.text),
                 ),
           ),
       });

  static const int version = 1;
  static const int maxItems = 10;

  static final SafetyPlan empty = SafetyPlan();

  final Map<SafetyPlanSection, List<SafetyPlanItem>> items;
  final DateTime? updatedAt;

  List<SafetyPlanItem> operator [](SafetyPlanSection s) => items[s]!;

  /// True when the user wrote nothing (1166 alone is not a plan).
  bool get isEmpty => items.values.every((l) => l.isEmpty);

  SafetyPlan withSection(SafetyPlanSection s, List<SafetyPlanItem> list) =>
      SafetyPlan(items: {...items, s: list}, updatedAt: updatedAt);

  SafetyPlan withUpdatedAt(DateTime t) =>
      SafetyPlan(items: items, updatedAt: t);

  /// The encrypted part (everything the user wrote).
  Map<String, Object?> toPayload() => {
    'v': version,
    'sections': {
      for (final s in SafetyPlanSection.values)
        s.id: [for (final i in items[s]!) i.toJson()],
    },
  };

  static SafetyPlan fromPayload(
    Map<String, Object?> json, {
    DateTime? updatedAt,
  }) {
    final raw = json['sections'];
    final out = <SafetyPlanSection, List<SafetyPlanItem>>{};
    if (raw is Map) {
      for (final MapEntry(:key, :value) in raw.entries) {
        final s = SafetyPlanSection.fromId(key);
        if (s == null || value is! List) continue;
        out[s] = [for (final v in value) ?SafetyPlanItem.fromJson(v)];
      }
    }
    return SafetyPlan(items: out, updatedAt: updatedAt);
  }
}
