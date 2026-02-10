import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  final FlutterTts flutterTts = FlutterTts();

  TTSService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
  }

  Future<void> speak(String text, String language) async {
    await flutterTts.setLanguage(language);
    await flutterTts.speak(text);
  }

  Future<void> stop() async {
    await flutterTts.stop();
  }

  Future<bool> synthesizeToFile(String text, String fileName, String language) async {
    try {
      await flutterTts.setLanguage(language);
      // Note: flutter_tts implementation varies by platform.
      // On Android, fileName is just the name. On iOS, it might be full path.
      // On Windows, it might not support saving to file easily without extra config.
      if (Platform.isWindows) {
        // Windows implementation of flutter_tts might not support synthesizeToFile fully
        // or requires a specific path format.
        // If it fails, we will handle it in the provider.
      }
      await flutterTts.synthesizeToFile(text, fileName);
      return true;
    } catch (e) {
      print("TTS File Error: $e");
      return false;
    }
  }
}