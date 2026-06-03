import 'second_page.dart'; // file ka exact name check karo
import 'dart:convert';
import 'dart:io';
import 'ocr_service.dart';
import 'splash_screen.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'services/translation_service.dart';
import 'package:flutter/material.dart';
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
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => SplashScreen(),
        '/login': (context) => LoginPage(),
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

  File? _image;
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
      _image = File(picked.path);
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
        if (_image != null) {
          final bytes = await _image!.readAsBytes();
          base64Image = base64Encode(bytes);
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
    final result = await TranslationService.translateText(text, 'auto', 'hi');

    return result;
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
      final url = Uri.parse(
          'https://inputtools.google.com/request?text=$encoded&itc=$itc&num=5&cp=0&cs=1&ie=utf-8&oe=utf-8');

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
          _image != null ? base64Encode(await _image!.readAsBytes()) : null,
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
    if (_image != null) {
      final bytes = await _image!.readAsBytes();
      base64Image = base64Encode(bytes);
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
    return Scaffold(
      appBar: AppBar(
        title: Text('CodeBharat — Translate & Transliterate'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
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
                    _image = selected.imageBase64 != null
                        ? File.fromRawPath(base64Decode(selected.imageBase64!))
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
      body: SingleChildScrollView(
        padding: EdgeInsets.all(14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: jarvisCircle()),
          SizedBox(height: 20),

          // Source & Target pickers
          Row(children: [
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                    labelText: 'Source', border: OutlineInputBorder()),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _source,
                    isExpanded: true,
                    onChanged: (v) => setState(() => _source = v!),
                    items: _langs
                        .map((l) => DropdownMenuItem(
                            value: l['code'], child: Text(l['name']!)))
                        .toList(),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.swap_horiz, size: 30),
              onPressed: () {
                setState(() {
                  final t = _source;
                  _source = _target;
                  _target = t;
                });
              },
            ),
            SizedBox(width: 8),
            Expanded(
              child: InputDecorator(
                decoration: InputDecoration(
                    labelText: 'Target', border: OutlineInputBorder()),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _target,
                    isExpanded: true,
                    onChanged: (v) => setState(() => _target = v!),
                    items: _langs
                        .where((l) => l['code'] != 'auto')
                        .map((l) => DropdownMenuItem(
                            value: l['code'], child: Text(l['name']!)))
                        .toList(),
                  ),
                ),
              ),
            ),
          ]),
          SizedBox(height: 12),

          // input text
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'Enter / paste text (or use camera)',
              border: OutlineInputBorder(),
              suffixIcon: IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () => _controller.clear()),
            ),
          ),
          SizedBox(height: 10),

          // Capture/Gallery
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _pickImageAndRecognizeText(fromGallery: false),
                icon: _loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Icon(Icons.camera_alt),
                label: Text('Capture & OCR'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _pickImageAndRecognizeText(fromGallery: true),
                icon: Icon(Icons.photo),
                label: Text('Gallery'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
              ),
            ),
          ]),
          SizedBox(height: 10),

          // action buttons Translate / Transliterate
          Row(children: [
            Expanded(
              child: // action buttons Translate / Transliterate
                  Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _doAutoDetectAndTranslate,
                    icon: Icon(Icons.text_fields),
                    label: Text("Translate"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFD1C4E9), // Light Lavender
                      foregroundColor:
                          Color(0xFF4A148C), // Text/Icon Dark Purple
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _doTransliterate,
                    icon: Icon(Icons.text_fields),
                    label: Text("Transliterate"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFB2DFDB), // 🩵 Soft Mint Green
                      foregroundColor: Color(0xFF004D40), // Text/Icon Dark Teal
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
          SizedBox(height: 14),

          // output box
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.deepPurple.shade50),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text('Output:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_detected.isNotEmpty)
                    Chip(label: Text('Detected: $_detected')),
                  if (_loading)
                    SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator()),
                ],
              ),
              SizedBox(height: 8),
              SelectableText(
                  _output.isEmpty ? 'Result will appear here...' : _output,
                  style: TextStyle(fontSize: 16)),
            ]),
          ),
          SizedBox(height: 12),

          // copy/share/speak
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton.icon(
                onPressed: _output.isEmpty ? null : _doCopy,
                icon: Icon(Icons.copy),
                label: Text('Copy')),
            SizedBox(width: 8),
            ElevatedButton.icon(
                onPressed: _output.isEmpty ? null : _doShare,
                icon: Icon(Icons.share),
                label: Text('Share')),
            SizedBox(width: 8),
            ElevatedButton.icon(
                onPressed: _output.isEmpty ? null : _doSpeak,
                icon: Icon(Icons.volume_up),
                label: Text('Speak')),
          ]),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: speakAndTranslate,
                  icon: Icon(Icons.mic, color: Colors.white),
                  label: Text("Speak & Translate"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: speakAndTransliterate,
                  icon: Icon(Icons.record_voice_over, color: Colors.white),
                  label: Text("Speak & Transliterate"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 12),

          if (_image != null) ...[
            Divider(),
            Text('Captured image:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(_image!)),
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
