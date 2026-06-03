import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  static const _libreBase = "https://translate.argosopentech.com";
  static const _memoryBase = "https://api.mymemory.translated.net/get";

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
  /// source & target are BCP-47 codes, e.g., "en", "hi", "fr", "es"
  static Future<String> translateText(
      String text, String source, String target) async {
    if (text.trim().isEmpty) return "⚠️ Please enter text";

    bool online = await hasInternet();

    // 🌐 Online Mode
    if (online) {
      try {
        final rawUri = "$_libreBase/translate";
        final uri = Uri.parse(kIsWeb
            ? 'https://corsproxy.io/?${Uri.encodeComponent(rawUri)}'
            : rawUri);
        final resp = await http.post(uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "q": text,
              "source": source == "auto" ? "auto" : source,
              "target": target,
              "format": "text"
            }));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data["translatedText"] != null) return data["translatedText"];
        }

        // Backup API
        final rawBackupUri = "$_memoryBase?q=$text&langpair=$source|$target";
        final backupUri = Uri.parse(kIsWeb
            ? 'https://corsproxy.io/?${Uri.encodeComponent(rawBackupUri)}'
            : rawBackupUri);
        final backupResp = await http.get(backupUri);
        if (backupResp.statusCode == 200) {
          final backupData = jsonDecode(backupResp.body);
          return backupData["responseData"]["translatedText"] ??
              "⚠️ No translation found";
        }
      } catch (e) {
        print("Online translation failed: $e");
      }
    }

    // ⚙️ Offline Mode (ML Kit) with multiple languages support
    if (kIsWeb) {
      return "❌ Offline translation is not supported on the Web.";
    }
    try {
      // Find source language
      TranslateLanguage sourceLang = TranslateLanguage.values.firstWhere(
        (lang) => lang.bcpCode == source,
        orElse: () => TranslateLanguage.english,
      );

      // Find target language
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
