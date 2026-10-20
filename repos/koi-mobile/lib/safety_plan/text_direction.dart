import 'package:flutter/widgets.dart';

// Arabic-script (Urdu) and Hebrew blocks, plus their presentation forms.
final RegExp _rtl = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final RegExp _ltr = RegExp(r'[A-Za-z\u00C0-\u024F]');

/// The direction of text the user wrote, from its first strong letter, so
/// Urdu reads right-to-left and English left-to-right whatever the app
/// language is. Null (no letters) keeps the surrounding direction.
TextDirection? userTextDirection(String text) {
  for (final rune in text.runes) {
    final c = String.fromCharCode(rune);
    if (_rtl.hasMatch(c)) return TextDirection.rtl;
    if (_ltr.hasMatch(c)) return TextDirection.ltr;
  }
  return null;
}
