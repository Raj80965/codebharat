import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import '../services/translation_service.dart';
import '../services/transliteration_service.dart';

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  Future<String> extractAndTranslateWordLevel(File imageFile, String targetLang) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      await _textRecognizer.close();

      if (recognizedText.text.trim().isEmpty) return '❌ No text detected';

      final languageIdentifier = LanguageIdentifier(confidenceThreshold: 0.4);

      StringBuffer output = StringBuffer();
      output.writeln("📸 OCR Text & Translation:\n");

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final word = element.text.trim();
            if (word.isEmpty) continue;

            // 🔹 Detect language of each word
            String lang = await languageIdentifier.identifyLanguage(word);
            if (lang == 'und') lang = 'auto';

            // 🔹 Translate word
            final translated = await TranslationService.translateText(word, lang, targetLang);

            // 🔹 Transliterate (optional)
            final translit = await TransliterationService.transliterate(word, targetLang);

            output.writeln("🈂️ Word: $word");
            output.writeln("🌐 Lang: $lang");
            output.writeln("➡️ Translation: $translated");
            output.writeln("✍️ Transliteration: $translit\n");
          }
          output.writeln('-----------------------------');
        }
      }

      await languageIdentifier.close();
      return output.toString();
    } catch (e) {
      return '❌ Error: $e';
    }
  }
}