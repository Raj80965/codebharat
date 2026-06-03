import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class TransliterationService {
  static const _baseUrl = "https://inputtools.google.com/request";

  /// Check Internet
  static Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Transliteration (works online, warns offline)
  static Future<String> transliterate(String text, String langCode) async {
    if (text.trim().isEmpty) return "⚠️ Please enter text";

    bool online = await _hasInternet();
    if (!online) {
      // ⚙️ Offline Mode - transliteration not possible
      return "❌ Offline mode: Transliteration not available (needs internet)";
    }

    try {
      final url =
          Uri.parse("$_baseUrl?text=$text&itc=$langCode-t-i0-und&num=1");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data[0] == "SUCCESS" && data[1][0]["suggestions"].isNotEmpty) {
          return data[1][0]["suggestions"][0];
        }
        return "⚠️ No transliteration found";
      } else {
        throw Exception("HTTP error ${response.statusCode}");
      }
    } catch (e) {
      return "❌ Transliteration error: $e";
    }
  }
}
