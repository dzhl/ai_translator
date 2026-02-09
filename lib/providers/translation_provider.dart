import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../services/llm_service.dart';
import '../services/stt_service.dart'; // Keeping for potential fallback
import '../services/tts_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/gemini_rest_service.dart';
import '../services/gemini_live_service.dart';

enum AppState { idle, listening, processing, speaking, error }

class TranslationProvider with ChangeNotifier {
  AppState _state = AppState.idle;
  String _statusMessage = "";
  List<TranslationMessage> _messages = [];
  String _currentLang = ""; // 'zh' or 'en'
  String? _currentRecordingPath;
  
  AppConfig? _config;
  
  // Services
  LLMService? _llmService; // Legacy/Text-only
  late final STTService _sttService; // Legacy/Text-only
  late final TTSService _ttsService;
  late final AudioRecorderService _recorderService;
  GeminiRestService? _geminiService;
  GeminiLiveService? _liveService;
  
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  StreamSubscription<String>? _liveTextSubscription;

  TranslationProvider() {
    _sttService = STTService();
    _ttsService = TTSService();
    _recorderService = AudioRecorderService();
    _loadConfig();
  }

  AppState get state => _state;
  String get statusMessage => _statusMessage;
  List<TranslationMessage> get messages => _messages;
  String get currentTranscript => ""; // Not used in audio mode usually
  AppConfig? get config => _config;

  Future<void> _loadConfig() async {
    _config = await AppConfig.load();
    if (_config != null) {
      _llmService = LLMService(_config!);
      _geminiService = GeminiRestService(_config!);
      _liveService = GeminiLiveService(_config!);
    }
    notifyListeners();
  }

  Future<void> updateConfig(AppConfig newConfig) async {
    _config = newConfig;
    await _config!.save();
    _llmService = LLMService(_config!);
    _geminiService = GeminiRestService(_config!);
    _liveService = GeminiLiveService(_config!);
    notifyListeners();
  }

  void _setState(AppState state, {String msg = ""}) {
    _state = state;
    if (msg.isNotEmpty) _statusMessage = msg;
    notifyListeners();
  }

  StringBuffer _liveTranscript = StringBuffer();

  // User presses button
  Future<void> startRecording(String langCode) async {
    // langCode is just a hint or for UI now
    if (_state == AppState.processing) return;
    
    await _ttsService.stop();
    _currentLang = langCode;

    if (_config?.translationMode == TranslationMode.live) {
      if (_liveService == null) return;
      
      _setState(AppState.listening, msg: "Connecting Live...");
      
      try {
        await _liveService!.connect();
        
        _liveTranscript.clear();
        final stream = await _recorderService.startStream();
        _audioStreamSubscription = stream.listen((data) {
          _liveService!.sendAudioChunk(data);
        });
        
        _liveTextSubscription = _liveService!.textStream.listen((text) {
           if (text.isNotEmpty) {
             _liveTranscript.write(text);
             _statusMessage = _liveTranscript.toString();
             notifyListeners();
           }
        });
        
        _setState(AppState.listening, msg: "Live: Listening...");
      } catch (e) {
        _setState(AppState.error, msg: "Live Error: $e");
        await stopRecording();
      }
      return;
    }

    // Standard Mode (Native Audio)
    _setState(AppState.listening, msg: "Listening...");
    
    try {
      if (!await _recorderService.hasPermission()) {
        _setState(AppState.error, msg: "Microphone permission denied");
        return;
      }

      _currentRecordingPath = await _recorderService.getTempFilePath();
      await _recorderService.startRecording(_currentRecordingPath!);
    } catch (e) {
      _setState(AppState.error, msg: "Rec Error: $e");
    }
  }

  // User releases button
  Future<void> stopRecording() async {
    if (_state != AppState.listening && _state != AppState.processing) {
       // Allow stopping if processing/connecting
       if (_config?.translationMode == TranslationMode.live && _audioStreamSubscription != null) {
         // Proceed to stop live
       } else {
         return;
       }
    }

    if (_config?.translationMode == TranslationMode.live) {
       await _audioStreamSubscription?.cancel();
       _audioStreamSubscription = null;
       
       await _recorderService.stopStream();
       
       await _liveTextSubscription?.cancel();
       _liveTextSubscription = null;
       
       await _liveService?.disconnect();
       
       if (_liveTranscript.isNotEmpty) {
          _messages.insert(0, TranslationMessage(
            sourceText: "[Live Session]",
            translatedText: _liveTranscript.toString(),
            sourceLang: "auto",
          ));
       }
       
       _setState(AppState.idle, msg: "Live Session Ended");
       return;
    }

    try {
      final path = await _recorderService.stopRecording();
      if (path == null) {
        _setState(AppState.idle, msg: "Recording failed");
        return;
      }
      
      // Check file existence
      final file = File(path);
      if (!await file.exists() || await file.length() < 100) { // Check for minimal size (e.g., 100 bytes)
        _setState(AppState.idle, msg: "Audio too short or empty");
        return;
      }

      await _processAudioTranslation(file);

    } catch (e) {
      _setState(AppState.error, msg: "Stop Error: $e");
    }
  }

  Future<void> _processAudioTranslation(File audioFile) async {
    if (_geminiService == null) return;
    
    _setState(AppState.processing, msg: "Thinking...");

    try {
      // Gemini Native Audio Translation
      final result = await _geminiService!.translateAudio(audioFile);
      
      final detectedLang = result['detected_lang'] ?? 'unknown';
      final translatedText = result['translated_text'] ?? '';
      
      if (translatedText.isEmpty) {
        _setState(AppState.error, msg: "Could not translate");
        return;
      }

      // Add to messages
      final message = TranslationMessage(
        sourceText: "[Audio Input]", // We don't have STT text here unless we ask Gemini for it too
        translatedText: translatedText,
        sourceLang: detectedLang,
      );
      
      _messages.insert(0, message);
      
      // Output Control
      bool shouldSpeak = _config!.outputMode == OutputMode.both || _config!.outputMode == OutputMode.audio;
      
      if (shouldSpeak) {
        _setState(AppState.speaking, msg: "Speaking...");
        // Determine TTS lang based on target (if source is zh, target is en, etc.)
        // This relies on accurate detection. 
        // Simple logic: if detected is 'zh', speak 'en'. 
        String ttsLang = (detectedLang == 'zh' || detectedLang == 'Chinese') ? 'en-US' : 'zh-CN';
        await _ttsService.speak(translatedText, ttsLang);
      }
      
      _setState(AppState.idle, msg: "Ready");

    } catch (e) {
      _setState(AppState.error, msg: "Error: $e");
      print(e);
    }
  }
}
