import 'second_page.dart'; // file ka exact name check karo
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ocr_service.dart';
import 'splash_screen.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:translator/translator.dart';
import 'services/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/login_page.dart'; // Added for authentication
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize AuthService
  await AuthService.init();
  runApp(CodeBharatApp());
}

class CodeBharatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CodeBharat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.deepPurpleAccent,
          surface: Color(0xFF1E1E30),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => SplashScreen(),
        '/home': (context) => TransliterateTranslateHome(),
      },
    );
  }
}

class HistoryItem {
  final String input;
  final String output;
  final String action; // 'translate' or 'transliterate' or 'auto_camera'
  final String source;
  final String target;
  final String timestamp;
  final String? imageBase64; // ✅ new field (image stored as base64 string)

  HistoryItem({
    required this.input,
    required this.output,
    required this.action,
    required this.source,
    required this.target,
    required this.timestamp,
    this.imageBase64, // optional
  });

  Map<String, dynamic> toJson() => {
        'input': input,
        'output': output,
        'action': action,
        'source': source,
        'target': target,
        'timestamp': timestamp,
        'imageBase64': imageBase64, // ✅ added
      };

  static HistoryItem fromJson(Map<String, dynamic> j) => HistoryItem(
        input: j['input'] ?? '',
        output: j['output'] ?? '',
        action: j['action'] ?? '',
        source: j['source'] ?? '',
        target: j['target'] ?? '',
        timestamp: j['timestamp'] ?? '',
        imageBase64: j['imageBase64'], // ✅ added
      );
}

class TransliterateTranslateHome extends StatefulWidget {
  @override
  _TransliterateTranslateHomeState createState() =>
      _TransliterateTranslateHomeState();
}

class _TransliterateTranslateHomeState
    extends State<TransliterateTranslateHome> {
  bool isJarvisListening = false;
  bool isJarvisSpeaking = false;

  late stt.SpeechToText _speech;
  late FlutterTts _tts;
  bool _isListening = false;
  String _spokenText = "";
  String _translatedText = "";

  TextEditingController inputTextController = TextEditingController();
  String outputText = "";
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Uint8List? _imageBytes;
  bool _loading = false;
  String _output = '';
  String _detected = '';

  // languages list (code,name)
  final List<Map<String, String>> _langs = [
    {'code': 'auto', 'name': 'Auto-Detect'},
    {'code': 'en', 'name': 'English'},
    {'code': 'hi', 'name': 'Hindi'},
    {'code': 'bn', 'name': 'Bengali'},
    {'code': 'ta', 'name': 'Tamil'},
    {'code': 'te', 'name': 'Telugu'},
    {'code': 'ml', 'name': 'Malayalam'},
    {'code': 'kn', 'name': 'Kannada'},
    {'code': 'gu', 'name': 'Gujarati'},
    {'code': 'mr', 'name': 'Marathi'},
    {'code': 'pa', 'name': 'Punjabi'},
    {'code': 'or', 'name': 'Odia'},
    {'code': 'ur', 'name': 'Urdu'},
    {'code': 'ne', 'name': 'Nepali'},
    {'code': 'si', 'name': 'Sinhala'},
  ];

  String _source = 'auto';
  String _target = 'en';

  // history (left drawer + separate screen)
  List<HistoryItem> _history = [];

  // LibreTranslate base (public instance) - can be switched to your own server
  final String _libreBase = 'https://translate.argosopentech.com';
  @override
  void initState() {
    super.initState();
    _loadHistory();
    _speech = stt.SpeechToText();
    _tts = FlutterTts();
  }

  @override
  void dispose() {
    _controller.dispose();
    _tts.stop();
    super.dispose();
  }

  // -------------------------- History storage --------------------------
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('history_v1') ?? [];
    setState(() {
      _history = raw.map((s) {
        try {
          return HistoryItem.fromJson(jsonDecode(s));
        } catch (_) {
          return HistoryItem(
              input: s,
              output: s,
              action: 'unknown',
              source: 'na',
              target: 'na',
              timestamp: DateTime.now().toIso8601String());
        }
      }).toList();
    });
  }

  Future<void> _saveToHistory(HistoryItem it) async {
    final prefs = await SharedPreferences.getInstance();
    _history.insert(0, it); // newest first
    final list = _history.take(200).map((h) => jsonEncode(h.toJson())).toList();
    await prefs.setStringList('history_v1', list);
    setState(() {});
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('history_v1');
    setState(() {
      _history.clear();
    });
  }

  // -------------------------- OCR --------------------------
  Future<void> _pickImageAndRecognizeText({bool fromGallery = false}) async {
    try {
      setState(() {
        _loading = true;
      });
      final XFile? picked = await _picker.pickImage(
        source: fromGallery ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 100,
      );
      if (picked == null) {
        setState(() {
          _loading = false;
        });
        return;
      }
      _imageBytes = await picked.readAsBytes();
      if (kIsWeb) {
        setState(() { _loading = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Camera/Image text recognition is only available on the mobile app.')));
        return;
      }
      final inputImage = InputImage.fromFilePath(picked.path);
      final textRecognizer = TextRecognizer();
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

// ✅ Full safe extraction — ensures no text line is missed
      final StringBuffer fullText = StringBuffer();
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            fullText.write("${element.text} "); // har word ke baad space
          }
          fullText.writeln(); // har line ke baad new line
        }
        fullText.writeln(); // gap between blocks
      }

      final text = fullText.toString().trim();
      setState(() {
        _controller.text = text;
        _loading = false;
      });
      if (text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Image scanned but no text found')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Text added from image ✅')));

        // 🧠 Auto detect + translate + transliterate
        final detected = await _detectLanguage(text);
        final src = (detected == 'und' ? 'en' : detected);
        setState(() => _detected = src);

        final translit = await _transliterateViaInputTools(text, _target);
        setState(() {
          _output = translit;
          _loading = false;
        });

        String? base64Image;
        if (_imageBytes != null) {
          base64Image = base64Encode(_imageBytes!);
        }

        await _saveToHistory(HistoryItem(
          input: text,
          output: _output, // transliteration result stored yahan hai
          action: 'transliterate',
          source: _source,
          target: _target,
          timestamp: DateTime.now().toIso8601String(),
          imageBase64: base64Image, // ✅ full image saved in Base64
        ));
      }
    } catch (e) {
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('OCR error: $e')));
    }
  }

  // -------------------------- LibreTranslate detect --------------------------
  // -------------------------- Reliable Translate + Detect (Auto Fallback) --------------------------
  Future<String> _detectLanguage(String text) async {
    try {
      final translator = GoogleTranslator();
      final translation = await translator.translate(text, from: 'auto', to: 'en');
      return translation.sourceLanguage.code;
    } catch (_) {
      return 'en';
    }
  }

  Future<String> _translateText(
      String text, String source, String target) async {
    final result = await TranslationService.translateText(text, source, target);

    return result;
  }

  // -------------------------- Large Text Translator --------------------------
  Future<String> _translateLargeText(
      String text, String source, String target) async {
    const chunkSize = 500; // ek time me 500 characters
    final chunks = <String>[];

    for (int i = 0; i < text.length; i += chunkSize) {
      chunks.add(text.substring(
        i,
        i + chunkSize > text.length ? text.length : i + chunkSize,
      ));
    }

    final translatedChunks = await Future.wait(
      chunks.map((chunk) => _translateText(chunk, source, target)),
    );

    return translatedChunks.join(' ');
  }

  // -------------------------- Transliteration (Google InputTools) --------------------------
  Future<String> _transliterateViaInputTools(
      String text, String targetLang) async {
    try {
      final itc = '$targetLang-t-i0-und';
      final encoded = Uri.encodeComponent(text);
      final rawUrl =
          'https://inputtools.google.com/request?text=$encoded&itc=$itc&num=5&cp=0&cs=1&ie=utf-8&oe=utf-8';
      final url = Uri.parse(kIsWeb
          ? 'https://corsproxy.io/?${Uri.encodeComponent(rawUrl)}'
          : rawUrl);

      final resp = await http.get(url);
      if (resp.statusCode != 200)
        return '❌ Transliteration API error: ${resp.statusCode}';
      final data = jsonDecode(resp.body);

      // Try safe extraction: look for the first plausible suggestion string
      String? candidate;
      void search(dynamic node) {
        if (candidate != null) return;
        if (node is String) {
          if (node.trim().isNotEmpty && node.length > 0) candidate = node;
        } else if (node is List) {
          for (var e in node) {
            if (candidate != null) break;
            search(e);
          }
        } else if (node is Map) {
          node.values.forEach((v) {
            if (candidate == null) search(v);
          });
        }
      }

      // Preferred path used by many responses:
      try {
        if (data is List &&
            data.length > 1 &&
            data[1] is List &&
            data[1].isNotEmpty) {
          final alt = data[1][0];
          // alt is often like ["hello","हॅलो", ...] or [[...],...]
          if (alt is List && alt.length > 1) {
            final inside = alt[1];
            if (inside is List && inside.isNotEmpty) {
              final pick = inside[0];
              if (pick is String && pick.trim().isNotEmpty) return pick;
            }
          }
        }
      } catch (_) {}

      search(data);
      if (candidate == null) return '⚠ No transliteration result';
      return candidate!;
    } catch (e) {
      return '❌ Transliteration error: $e';
    }
  }

  // -------------------------- Actions --------------------------
  Future<void> _doAutoDetectAndTranslate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _output = '⚠ Enter or capture text first');
      return;
    }

    setState(() {
      _loading = true;
      _output = '';
      _detected = '';
    });

    String src = _source;
    if (_source == 'auto') {
      final detected = await _detectLanguage(text);
      src = (detected == 'und' ? 'en' : detected);
      setState(() => _detected = src);
    }

    final translation = await _translateLargeText(text, src, _target);
    final transliteration =
        await _transliterateViaInputTools(text, _target); // ✅ add this line

    setState(() {
      _output = "$translation\n\n$transliteration";
      _loading = false;
    });

    await _saveToHistory(HistoryItem(
      input: text,
      output: "$translation\n\n$transliteration",
      action: 'auto_camera',
      source: src,
      target: _target,
      timestamp: DateTime.now().toIso8601String(),
      imageBase64:
          _imageBytes != null ? base64Encode(_imageBytes!) : null,
    ));
  }

  Future<void> _doTransliterate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _output = '⚠ Enter or capture text first');
      return;
    }
    setState(() {
      _loading = true;
      _output = '';
      _detected = '';
    });

    // InputTools expects target like 'hi' to transliterate into that script.
    // We still auto-detect source for info if needed.
    if (_source == 'auto') {
      final detected = await _detectLanguage(text);
      if (detected != 'und') setState(() => _detected = detected);
    }

    final translit = await _transliterateViaInputTools(text, _target);
    setState(() {
      _output = translit;
      _loading = false;
    });

    String? base64Image;
    if (_imageBytes != null) {
      base64Image = base64Encode(_imageBytes!);
    }

    await _saveToHistory(HistoryItem(
      input: text,
      output: "$_output",
      action: 'auto_camera',
      source: _source,
      target: _target,
      timestamp: DateTime.now().toIso8601String(),
      imageBase64: base64Image,
    ));
  }

  Future<void> _doSpeak() async {
    final t = _output.trim();
    if (t.isEmpty) return;

    setState(() {
      isJarvisSpeaking = true; // 🔥 JARVIS voice glow ON
      isJarvisListening = false;
    });

    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.42);
    await _tts.setPitch(0.9);

    await _tts.speak(t);

    _tts.setCompletionHandler(() {
      setState(() {
        isJarvisSpeaking = false; // 🔥 Glow OFF
      });
    });
  }

  Widget jarvisCircle() {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      height: isJarvisListening || isJarvisSpeaking ? 170 : 140,
      width: isJarvisListening || isJarvisSpeaking ? 170 : 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: isJarvisListening
                ? Colors.blueAccent.withOpacity(0.8)
                : isJarvisSpeaking
                    ? Colors.orangeAccent.withOpacity(0.8)
                    : Colors.cyanAccent.withOpacity(0.3),
            blurRadius: isJarvisListening || isJarvisSpeaking ? 40 : 10,
            spreadRadius: isJarvisListening || isJarvisSpeaking ? 25 : 4,
          ),
        ],
        gradient: RadialGradient(
          colors: isJarvisListening
              ? [Colors.blueAccent, Colors.black]
              : isJarvisSpeaking
                  ? [Colors.orangeAccent, Colors.black]
                  : [Colors.cyanAccent, Colors.black],
        ),
      ),
      child: Center(
        child: Icon(
          isJarvisListening
              ? Icons.mic
              : isJarvisSpeaking
                  ? Icons.volume_up
                  : Icons.circle,
          color: Colors.white,
          size: 50,
        ),
      ),
    );
  }

  Future<void> speakAndTranslate() async {
    bool available = await _speech.initialize();

    if (available) {
      setState(() {
        isJarvisListening = true;
        isJarvisSpeaking = false;
      });

      _speech.listen(
        onResult: (val) async {
          if (val.finalResult) {
            setState(() {
              isJarvisListening = false;
            });

            String spoken = val.recognizedWords;
            _controller.text = spoken;

            String translated = await _translateText(spoken, _source, _target);

            setState(() {
              _output = translated;
              isJarvisSpeaking = true;
            });

            await _tts.speak(translated);

            setState(() {
              isJarvisSpeaking = false;
            });
          }
        },
        localeId: "en-US",
      );
    }
  }

  Future<void> speakAndTransliterate() async {
    bool available = await _speech.initialize();

    if (available) {
      setState(() {
        isJarvisListening = true;
        isJarvisSpeaking = false;
      });

      _speech.listen(
        onResult: (val) async {
          if (val.finalResult) {
            setState(() {
              isJarvisListening = false;
            });

            String spoken = val.recognizedWords;
            _controller.text = spoken;

            String translit =
                await _transliterateViaInputTools(spoken, _target);

            setState(() {
              _output = translit;
              isJarvisSpeaking = true;
            });

            await _tts.speak(translit);

            setState(() {
              isJarvisSpeaking = false;
            });
          }
        },
        localeId: "en-US",
      );
    }
  }

  Future<void> _doCopy() async {
    await Clipboard.setData(ClipboardData(text: _output));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Copied ✅')));
  }

  Future<void> _doShare() async {
    if (_output.trim().isEmpty) return;
    await Share.share(_output);
  }

  // -------------------------- UI --------------------------
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('CodeBharat AI', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: colors.primary)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'history') {
                // navigate to history screen
                final selected = await Navigator.of(context).push<HistoryItem>(
                  MaterialPageRoute(
                      builder: (_) => HistoryScreen(
                          history: _history, onClear: _clearHistory)),
                );
                if (selected != null) {
                  setState(() {
                    _controller.text = selected.input;
                    _output = selected.output;
                    _source = selected.source;
                    _target = selected.target;
                    _imageBytes = selected.imageBase64 != null
                        ? base64Decode(selected.imageBase64!)
                        : null;
                  });
                }

                await _loadHistory();
              } else if (val == 'clear') {
                await _clearHistory();
              } else if (val == 'paste') {
                final cb = await Clipboard.getData('text/plain');
                if (cb != null && cb.text != null)
                  setState(() => _controller.text = cb.text!);
              } else if (val == 'detect') {
                if (_controller.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Enter text first for detect')));
                  return;
                }
                final det = await _detectLanguage(_controller.text.trim());
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Detected: $det')));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'history', child: Text('Open History')),
              PopupMenuItem(
                  value: 'paste', child: Text('Paste from clipboard')),
              PopupMenuItem(value: 'detect', child: Text('Detect language')),
              PopupMenuItem(value: 'clear', child: Text('Clear history')),
            ],
          )
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              DrawerHeader(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('History',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text('Recent translations & transliterations'),
                  ])),
              Expanded(
                child: _history.isEmpty
                    ? Center(child: Text('No history yet'))
                    : ListView.builder(
                        itemCount: _history.length,
                        itemBuilder: (_, i) {
                          final h = _history[i];
                          return ListTile(
                            title: Text(h.output,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${h.action} • ${h.source}→${h.target} • ${DateTime.tryParse(h.timestamp)?.toLocal().toString().split('.').first ?? h.timestamp}'),
                            onTap: () {
                              // load into input / output
                              Navigator.of(context).pop();
                              setState(() {
                                _controller.text = h.input;
                                _output = h.output;
                                _source = h.source == 'na' ? _source : h.source;
                                _target = h.target == 'na' ? _target : h.target;
                              });
                            },
                            trailing: IconButton(
                              icon: Icon(Icons.copy),
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: h.output));
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('Copied history item')));
                              },
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: ElevatedButton.icon(
                    onPressed: _clearHistory,
                    icon: Icon(Icons.delete),
                    label: Text('Clear History'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent)),
              )
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F0F1E), Color(0xFF1A1A2E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: jarvisCircle()),
            SizedBox(height: 30),

            // Source & Target pickers in a sleek card
            Card(
              elevation: 4,
              shadowColor: Colors.black45,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _source,
                        isExpanded: true,
                        icon: Icon(Icons.keyboard_arrow_down, color: colors.primary),
                        onChanged: (v) => setState(() => _source = v!),
                        items: _langs
                            .map((l) => DropdownMenuItem(
                                value: l['code'], child: Text(l['name']!, style: TextStyle(fontWeight: FontWeight.w500))))
                            .toList(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.swap_horiz, size: 28, color: colors.secondary),
                    onPressed: () {
                      setState(() {
                        final t = _source;
                        _source = _target;
                        _target = t;
                      });
                    },
                  ),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _target,
                        isExpanded: true,
                        icon: Icon(Icons.keyboard_arrow_down, color: colors.primary),
                        onChanged: (v) => setState(() => _target = v!),
                        items: _langs
                            .where((l) => l['code'] != 'auto')
                            .map((l) => DropdownMenuItem(
                                value: l['code'], child: Text(l['name']!, style: TextStyle(fontWeight: FontWeight.w500))))
                            .toList(),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SizedBox(height: 20),

            // Input text
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: TextField(
                controller: _controller,
                minLines: 4,
                maxLines: 6,
                style: TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Enter text, paste, or use camera...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                  suffixIcon: IconButton(
                      icon: Icon(Icons.close, color: Colors.white54),
                      onPressed: () => _controller.clear()),
                ),
              ),
            ),
            SizedBox(height: 12),

            // Sleek Action Row (Camera & Mic)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                onPressed: _loading ? null : () => _pickImageAndRecognizeText(fromGallery: false),
                icon: Icon(Icons.camera_alt_outlined, color: colors.primary),
                tooltip: 'Capture & OCR',
                style: IconButton.styleFrom(backgroundColor: colors.surface),
              ),
              SizedBox(width: 12),
              IconButton(
                onPressed: _loading ? null : () => _pickImageAndRecognizeText(fromGallery: true),
                icon: Icon(Icons.photo_library_outlined, color: colors.secondary),
                tooltip: 'Gallery',
                style: IconButton.styleFrom(backgroundColor: colors.surface),
              ),
              SizedBox(width: 12),
              IconButton(
                onPressed: speakAndTranslate,
                icon: Icon(Icons.mic_none_outlined, color: Colors.purpleAccent),
                tooltip: 'Speak & Translate',
                style: IconButton.styleFrom(backgroundColor: colors.surface),
              ),
            ]),
            SizedBox(height: 20),

            // Primary Translate / Transliterate Buttons
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _doAutoDetectAndTranslate,
                  icon: Icon(Icons.g_translate),
                  label: Text("Translate", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: colors.primary.withOpacity(0.15),
                    foregroundColor: colors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _doTransliterate,
                  icon: Icon(Icons.language),
                  label: Text("Transliterate", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: colors.secondary.withOpacity(0.15),
                    foregroundColor: colors.secondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
            SizedBox(height: 24),

            // Output box (Glassmorphic look)
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [colors.surface.withOpacity(0.8), colors.surface.withOpacity(0.4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white12, width: 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Output', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white54)),
                    if (_loading)
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary)),
                    if (_detected.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: colors.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                        child: Text('Detected: $_detected', style: TextStyle(color: colors.primary, fontSize: 12)),
                      ),
                  ],
                ),
                SizedBox(height: 12),
                SelectableText(
                  _output.isEmpty ? 'Translation will appear here...' : _output,
                  style: GoogleFonts.inter(fontSize: 18, color: Colors.white),
                ),
              ]),
            ),
            SizedBox(height: 16),

          // copy/share/speak
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                  onPressed: _output.isEmpty ? null : _doCopy,
                  icon: Icon(Icons.copy_rounded, size: 20),
                  label: Text('Copy')),
              SizedBox(width: 8),
              TextButton.icon(
                  onPressed: _output.isEmpty ? null : _doShare,
                  icon: Icon(Icons.share_rounded, size: 20),
                  label: Text('Share')),
              SizedBox(width: 8),
              TextButton.icon(
                  onPressed: _output.isEmpty ? null : _doSpeak,
                  icon: Icon(Icons.volume_up_rounded, size: 20),
                  label: Text('Speak')),
            ]),

            SizedBox(height: 24),

          if (_imageBytes != null) ...[
            Divider(),
            Text('Captured image:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_imageBytes!)),
          ],

          SizedBox(height: 20),

          Center(
            child: Column(
              children: [
                Text(
                  'Left drawer shows history • 3-dot menu has extra actions',
                  style: TextStyle(color: Colors.white70),
                ),
                SizedBox(height: 6),
                Text(
                  'SISTec E — 3rd Year (IoT)',
                  style: TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '🇮🇳 Team CODEBHARAT ',
                  style: TextStyle(
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          // ---------------- output box ----------------

          SizedBox(height: 12),

// ✅ Next button
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SecondPage(
                      text: _output.isEmpty
                          ? "No text available"
                          : _output, // yahan text pass ho raha hai
                    ),
                  ),
                );
              },
              child: Text("Next"),
            ),
          ),
          SizedBox(height: 12),
        ]),
      ),
    );
  }
}

// ---------------- history screen ----------------
class HistoryScreen extends StatefulWidget {
  final List<HistoryItem> history;
  final Future<void> Function() onClear;

  const HistoryScreen({required this.history, required this.onClear});

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('History'),
        actions: [
          IconButton(
            onPressed: () async {
              await widget.onClear();
              setState(() {});
            },
            icon: Icon(Icons.delete),
          ),
        ],
      ),
      body: widget.history.isEmpty
          ? Center(child: Text('No history yet'))
          : ListView.builder(
              itemCount: widget.history.length,
              itemBuilder: (_, i) {
                final h = widget.history[i];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: ListTile(
                    leading: h.imageBase64 != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              base64Decode(h.imageBase64!),
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(Icons.history, color: Colors.deepPurple),
                    title: Text(
                      h.output,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${h.action} • ${h.source}→${h.target}\n${DateTime.tryParse(h.timestamp)?.toLocal().toString().split(".").first ?? h.timestamp}',
                      style: TextStyle(fontSize: 12),
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'copy') {
                          await Clipboard.setData(
                              ClipboardData(text: h.output));
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Copied ✅')));
                        } else if (v == 'share') {
                          await Share.share(h.output);
                        } else if (v == 'view_image' && h.imageBase64 != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                appBar: AppBar(title: Text('Captured Image')),
                                body: Center(
                                  child: Image.memory(
                                      base64Decode(h.imageBase64!)),
                                ),
                              ),
                            ),
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'copy', child: Text('Copy')),
                        PopupMenuItem(value: 'share', child: Text('Share')),
                        if (h.imageBase64 != null)
                          PopupMenuItem(
                              value: 'view_image', child: Text('View Image')),
                      ],
                    ),
                    onTap: () {
                      Navigator.pop(context, h);
                    },
                  ),
                );
              },
            ),
    );
  }
}
