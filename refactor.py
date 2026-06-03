import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# We want to refactor the build method to use helper methods
# Let's find the start of `Widget build(BuildContext context) {`
build_start = content.find('  @override\n  Widget build(BuildContext context) {')

# Find the end of `_TransliterateTranslateHomeState` class
class_end = content.rfind('}', 0, content.find('class HistoryScreen extends StatefulWidget {'))

# Extract everything before build
before_build = content[:build_start]

# We need to extract the UI pieces and put them in helper methods, but we can also just write the helper methods and the new build method.
helpers = """
  // -------------------------- UI Helpers --------------------------

  Widget _buildLanguagePickers(ColorScheme colors) {
    return ProfessionalCard(
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
    );
  }

  Widget _buildInputBox() {
    return ProfessionalCard(
      padding: EdgeInsets.zero,
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
    );
  }

  Widget _buildMediaActions(ColorScheme colors) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
    ]);
  }

  Widget _buildActionButtons(ColorScheme colors) {
    return Row(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [colors.primary, colors.secondary]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: colors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _doAutoDetectAndTranslate,
            icon: const Icon(Icons.g_translate, color: Colors.white),
            label: Text("Translate", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Colors.deepPurpleAccent, Colors.pinkAccent]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _doTransliterate,
            icon: const Icon(Icons.language, color: Colors.white),
            label: Text("Transliterate", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildOutputBox(ColorScheme colors) {
    return ProfessionalCard(
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
        _output.isEmpty
            ? Text('Translation will appear here...', style: GoogleFonts.inter(fontSize: 18, color: Colors.white54))
            : DefaultTextStyle(
                style: GoogleFonts.inter(fontSize: 18, color: Colors.white),
                child: AnimatedTextKit(
                  key: ValueKey(_output),
                  animatedTexts: [TypewriterAnimatedText(_output, speed: const Duration(milliseconds: 30))],
                  isRepeatingAnimation: false,
                  displayFullTextOnTap: true,
                ),
              ),
        SizedBox(height: 16),
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
      ]),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        if (_imageBytes != null) ...[
          Divider(),
          Text('Captured image:', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_imageBytes!)),
          SizedBox(height: 20),
        ],
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
        SizedBox(height: 12),
        Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SecondPage(
                    text: _output.isEmpty ? "No text available" : _output,
                  ),
                ),
              );
            },
            child: Text("Next"),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF000000), // Pure Black for ambient glow to pop
      appBar: AppBar(
        title: Text('CodeBharat AI', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: colors.primary)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'history') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => HistoryScreen(
                      history: _history,
                      onClear: _clearHistory,
                    ),
                  ),
                );
                setState(() {});
              } else if (val == 'clear_image') {
                setState(() => _imageBytes = null);
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem(value: 'history', child: Text('View History')),
              PopupMenuItem(value: 'clear_image', child: Text('Clear Captured Image')),
            ],
          )
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Translation History', style: Theme.of(context).textTheme.titleLarge),
              ),
              Expanded(
                child: _history.isEmpty
                    ? Center(child: Text('No history yet.'))
                    : ListView.builder(
                        itemCount: _history.length,
                        itemBuilder: (c, i) {
                          final h = _history[i];
                          return ListTile(
                            title: Text(h.input, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${h.sourceLang} → ${h.targetLang}\\n${h.output}',
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            isThreeLine: true,
                            onTap: () {
                              setState(() {
                                _source = h.sourceLang;
                                _target = h.targetLang;
                                _controller.text = h.input;
                                _output = h.output;
                              });
                              Navigator.pop(context);
                            },
                            trailing: IconButton(
                              icon: Icon(Icons.copy),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: h.output));
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied history item')));
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
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent)),
              )
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Ambient Glow
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withOpacity(0.15),
                boxShadow: [
                  BoxShadow(color: colors.primary.withOpacity(0.2), blurRadius: 100, spreadRadius: 100),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.secondary.withOpacity(0.15),
                boxShadow: [
                  BoxShadow(color: colors.secondary.withOpacity(0.2), blurRadius: 100, spreadRadius: 100),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool isDesktop = constraints.maxWidth >= 800;
                  final double maxContainerWidth = isDesktop ? 1200 : 450;

                  return ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContainerWidth),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      child: isDesktop
                          // ---------------- DESKTOP LAYOUT (Side-by-Side) ----------------
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left Panel: AI Core & Controls
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(height: 20),
                                      Center(child: jarvisCircle()),
                                      SizedBox(height: 40),
                                      _buildLanguagePickers(colors),
                                      SizedBox(height: 20),
                                      _buildActionButtons(colors),
                                      SizedBox(height: 40),
                                      _buildFooter(),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 40),
                                // Right Panel: Input & Output
                                Expanded(
                                  flex: 6,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _buildInputBox(),
                                      SizedBox(height: 12),
                                      _buildMediaActions(colors),
                                      SizedBox(height: 20),
                                      _buildOutputBox(colors),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          // ---------------- MOBILE LAYOUT (Vertical) ----------------
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(child: jarvisCircle()),
                                SizedBox(height: 30),
                                _buildLanguagePickers(colors),
                                SizedBox(height: 20),
                                _buildInputBox(),
                                SizedBox(height: 12),
                                _buildMediaActions(colors),
                                SizedBox(height: 20),
                                _buildActionButtons(colors),
                                SizedBox(height: 24),
                                _buildOutputBox(colors),
                                SizedBox(height: 24),
                                _buildFooter(),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
"""

after_class = content[class_end:]

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(before_build + helpers + after_class)
