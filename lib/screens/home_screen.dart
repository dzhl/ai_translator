import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../providers/translation_provider.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranslationProvider>();
    final mode = provider.config?.translationMode ?? TranslationMode.standard;

    return Scaffold(
      appBar: AppBar(
        title: Text(mode == TranslationMode.live ? "Live Conversation" : "AI Translator"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: mode == TranslationMode.live 
          ? _buildLiveModeUI(context, provider)
          : _buildStandardModeUI(context, provider),
    );
  }

  // --- Standard Mode UI ---

  Widget _buildStandardModeUI(BuildContext context, TranslationProvider provider) {
    final messages = provider.messages;
    
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              return _buildMessageBubble(msg);
            },
          ),
        ),
        if (provider.state == AppState.listening)
           const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text(
              "Listening...",
              style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.blue),
            ),
          ),
          if (provider.state == AppState.processing)
             const LinearProgressIndicator(),

          if (provider.state == AppState.error)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                provider.statusMessage,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          
          _buildStandardControlArea(context, provider),

      ],
    );
  }

  Widget _buildMessageBubble(TranslationMessage msg) {
    bool isChineseSource = msg.sourceLang == 'zh' || msg.sourceLang == 'Chinese';
    // If language is unknown or mixed, default to grey or blue
    Color bubbleColor = isChineseSource ? Colors.blue[100]! : Colors.green[100]!;
    if (msg.sourceLang == 'unknown') bubbleColor = Colors.grey[300]!;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            msg.sourceText,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Divider(),
          Text(
            msg.translatedText,
            style: const TextStyle(fontSize: 18, color: Colors.black87),
          ),
          const SizedBox(height: 5),
          Text(
            msg.sourceLang.toUpperCase(),
            style: TextStyle(fontSize: 10, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardControlArea(BuildContext context, TranslationProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.grey[200],
      child: Center(
        child: GestureDetector(
          onLongPressStart: (_) => provider.startRecording("auto"),
          onLongPressEnd: (_) => provider.stopRecording(),
          child: Container(
            width: 200,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.blue, Colors.purple]),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mic, color: Colors.white, size: 32),
                const SizedBox(width: 10),
                Text(
                  provider.state == AppState.listening ? "Release to Send" : "Hold to Speak",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Live Mode UI (Placeholder for Phase 3) ---

  Widget _buildLiveModeUI(BuildContext context, TranslationProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.graphic_eq, size: 100, color: Colors.redAccent),
          const SizedBox(height: 20),
          const Text(
            "Live Conversation Mode",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text("Real-time bi-directional translation"),
          const SizedBox(height: 40),
          ElevatedButton.icon(
             icon: const Icon(Icons.play_arrow),
             label: const Text("Start Live Session"),
             onPressed: () {
               // Trigger Live Session (Phase 3)
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text("Phase 3: Live Mode Implementation Coming Soon"))
               );
             },
          ),
        ],
      ),
    );
  }
}
