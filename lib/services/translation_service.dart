import 'package:translator/translator.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;

class TranslationService {
  static final _translator = GoogleTranslator();

  /// Check Internet Connection
  static Future<bool> hasInternet() async {
    if (kIsWeb) return true;
    try {
      final resp = await http.get(Uri.parse('https://google.com')).timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Translate Text (Online + Offline)
  static Future<String> translateText(
      String text, String source, String target) async {
    if (text.trim().isEmpty) return "⚠️ Please enter text";

    bool online = await hasInternet();

    // 🌐 Online Mode (Flawless Google Translate)
    if (online) {
      try {
        final translation = await _translator.translate(
          text,
          from: source == "auto" ? "auto" : source,
          to: target,
        );
        return translation.text;
      } catch (e) {
        print("Online translation failed: $e");
        if (kIsWeb) return "❌ Translation failed: $e";
      }
    }

    // ⚙️ Offline Mode (ML Kit)
    if (kIsWeb) {
      return "❌ Offline translation is not supported on the Web.";
    }
    try {
      TranslateLanguage sourceLang = TranslateLanguage.values.firstWhere(
        (lang) => lang.bcpCode == source,
        orElse: () => TranslateLanguage.english,
      );

      TranslateLanguage targetLang = TranslateLanguage.values.firstWhere(
        (lang) => lang.bcpCode == target,
        orElse: () => TranslateLanguage.hindi,
      );

      final onDeviceTranslator = OnDeviceTranslator(
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
      );

      final result = await onDeviceTranslator.translateText(text);
      await onDeviceTranslator.close();
      return result;
    } catch (e) {
      return "❌ Offline translation failed: $e";
    }
  }

  /// Optional: List of supported languages
  static List<Map<String, String>> getSupportedLanguages() {
    return TranslateLanguage.values
        .map((lang) => {"name": lang.name, "code": lang.bcpCode})
        .toList();
  }
}
