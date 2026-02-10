import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:audioplayers/audioplayers.dart';
import '../models/app_config.dart';
import '../models/session.dart';
import '../models/translation_record.dart';
import '../services/llm_service.dart';
import '../services/stt_service.dart'; 
import '../services/tts_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/gemini_rest_service.dart';
import '../services/gemini_live_service.dart';
import '../services/database_service.dart';

enum AppState { idle, connecting, listening, processing, speaking, error }

class TranslationProvider with ChangeNotifier {
  AppState _state = AppState.idle;
  String _statusMessage = "";
  
  // Data
  List<Session> _sessions = [];
  Session? _currentSession;
  List<TranslationRecord> _records = []; // Current session records
  final Set<int> _selectedRecordIds = {}; // For multi-select deletion
  
  // Services
  AppConfig? _config;
  LLMService? _llmService; 
  late final STTService _sttService;
  late final TTSService _ttsService;
  late final AudioRecorderService _recorderService;
  late final DatabaseService _dbService;
  late final AudioPlayer _audioPlayer;
  GeminiRestService? _geminiService;
  GeminiLiveService? _liveService;
  
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  StreamSubscription<String>? _liveTextSubscription;
  String? _currentRecordingPath;
  TranslationMode? _activeRecordingMode;

  // Free Hand State
  Timer? _vadTimer;
  DateTime? _lastSpeechTime;
  bool _hasDetectedSpeech = false;
  bool _isRotating = false; 
  final double _speechThreshold = -35.0; // More sensitive
  final int _silenceDurationMs = 1000;

  // Playback State
  int? _playingRecordId;
  bool _isPlayingInput = false;
  bool _isPlayingOutput = false;

  TranslationProvider() {
    _sttService = STTService();
    _ttsService = TTSService();
    _recorderService = AudioRecorderService();
    _dbService = DatabaseService();
    _audioPlayer = AudioPlayer();
    _initAudioListeners();
    _loadConfigAndData();
  }

  void _initAudioListeners() {
    _audioPlayer.onPlayerStateChanged.listen((s) {
      _isPlayingInput = s == PlayerState.playing;
      notifyListeners();
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      _playingRecordId = null;
      _isPlayingInput = false;
      notifyListeners();
    });
    
    // TTS listeners
    _ttsService.flutterTts.setStartHandler(() {
      _isPlayingOutput = true;
      notifyListeners();
    });
    _ttsService.flutterTts.setCompletionHandler(() {
      _playingRecordId = null;
      _isPlayingOutput = false;
      notifyListeners();
    });
    _ttsService.flutterTts.setPauseHandler(() {
      _isPlayingOutput = false;
      notifyListeners();
    });
    _ttsService.flutterTts.setContinueHandler(() {
      _isPlayingOutput = true;
      notifyListeners();
    });
    _ttsService.flutterTts.setErrorHandler((msg) {
      _playingRecordId = null;
      _isPlayingOutput = false;
      notifyListeners();
    });
  }

  // Getters
  AppState get state => _state;
  String get statusMessage => _statusMessage;
  List<TranslationRecord> get records => _records;
  List<Session> get sessions => _sessions;
  Session? get currentSession => _currentSession;
  AppConfig? get config => _config;
  Set<int> get selectedRecordIds => _selectedRecordIds;
  bool get isMultiSelectMode => _selectedRecordIds.isNotEmpty;
  TranslationMode? get activeRecordingMode => _activeRecordingMode;
  
  int? get playingRecordId => _playingRecordId;
  bool get isPlayingInput => _isPlayingInput;
  bool get isPlayingOutput => _isPlayingOutput;

  // Initialization
  Future<void> _loadConfigAndData() async {
    _config = await AppConfig.load();
    if (_config != null) {
      _initServices();
    }
    await _loadSessions();
    
    if (_sessions.isNotEmpty) {
      await loadSession(_sessions.first);
    } else {
      await createSession("默认对话");
    }
  }

  void _initServices() {
    _llmService = LLMService(_config!);
    _geminiService = GeminiRestService(_config!);
    _liveService = GeminiLiveService(_config!);

    _liveService!.onDisconnected = () {
      if (_state == AppState.listening || _state == AppState.connecting) {
        _setState(AppState.idle, msg: "实时对话已断开");
        _cleanupLiveResources();
      }
    };
    _liveService!.onError = (err) {
      _setState(AppState.error, msg: "错误: $err");
      _cleanupLiveResources();
    };
  }

  Future<void> _cleanupLiveResources() async {
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _recorderService.stopStream();
  }

  Future<void> updateConfig(AppConfig newConfig) async {
    _config = newConfig;
    await _config!.save();
    _initServices();
    notifyListeners();
  }

  void _setState(AppState state, {String msg = ""}) {
    _state = state;
    if (msg.isNotEmpty) _statusMessage = msg;
    notifyListeners();
  }

  // --- Session Management ---

  Future<void> _loadSessions() async {
    _sessions = await _dbService.getSessions();
    notifyListeners();
  }

  Future<void> createSession(String title) async {
    final id = await _dbService.createSession(title);
    await _loadSessions();
    final newSession = _sessions.firstWhere((s) => s.id == id);
    await loadSession(newSession);
  }

  Future<void> loadSession(Session session) async {
    _currentSession = session;
    _records = await _dbService.getRecords(session.id!);
    _selectedRecordIds.clear();
    notifyListeners();
  }

  Future<void> deleteSession(Session session) async {
    if (session.id == null) return;
    
    final sessionRecords = await _dbService.getRecords(session.id!);
    for (var record in sessionRecords) {
      _deleteRecordFiles(record);
    }
    final docDir = await getApplicationDocumentsDirectory();
    final sessionDir = Directory(p.join(docDir.path, 'sessions', session.id.toString()));
    if (await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
    }

    await _dbService.deleteSession(session.id!);
    await _loadSessions();

    if (_currentSession?.id == session.id) {
      if (_sessions.isNotEmpty) {
        await loadSession(_sessions.first);
      } else {
        await createSession("默认对话");
      }
    }
  }

  // --- Record Management ---

  void toggleRecordSelection(int id) {
    if (_selectedRecordIds.contains(id)) {
      _selectedRecordIds.remove(id);
    } else {
      _selectedRecordIds.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedRecordIds.clear();
    notifyListeners();
  }

  Future<void> deleteSelectedRecords() async {
    final recordsToDelete = _records.where((r) => _selectedRecordIds.contains(r.id)).toList();
    final ids = recordsToDelete.map((r) => r.id!).toList();
    
    for (var record in recordsToDelete) {
      _deleteRecordFiles(record);
    }

    await _dbService.deleteRecords(ids);
    _records.removeWhere((r) => ids.contains(r.id));
    _selectedRecordIds.clear();
    notifyListeners();
  }

  void _deleteRecordFiles(TranslationRecord record) {
    if (record.inputAudioPath != null) {
      final f = File(record.inputAudioPath!);
      if (f.existsSync()) f.deleteSync();
    }
    if (record.outputAudioPath != null) {
      final f = File(record.outputAudioPath!);
      if (f.existsSync()) f.deleteSync();
    }
  }

  // --- Translation Flow ---

  Future<void> startRecording(String langCode, {TranslationMode? overrideMode}) async {
    if (_state == AppState.connecting || _state == AppState.listening) return;
    if (_state == AppState.error) _setState(AppState.idle);

    if (_currentSession == null) await createSession("默认对话");
    
    await _ttsService.stop();
    await _audioPlayer.stop();

    final mode = overrideMode ?? _config?.translationMode ?? TranslationMode.standard;
    _activeRecordingMode = mode;

    if (mode == TranslationMode.live) {
      _setState(AppState.connecting, msg: "正在连接...");
      try {
        if (!await _recorderService.hasPermission()) {
          _setState(AppState.error, msg: "麦克风权限被拒绝");
          return;
        }

        if (_config!.apiKey.isEmpty) {
          _setState(AppState.error, msg: "请设置 API Key");
          return;
        }

        await _liveService!.connect();
        
        _liveTextSubscription?.cancel();
        _liveTextSubscription = _liveService!.textStream.listen((text) {
          _statusMessage = "AI: $text"; 
          notifyListeners();
        });

        final audioStream = await _recorderService.startStream();
        _audioStreamSubscription = audioStream.listen((data) {
          _liveService!.sendAudioChunk(data);
        });

        _setState(AppState.listening, msg: "实时对话中");
      } catch (e) {
        _setState(AppState.error, msg: "连接失败: $e");
        await _cleanupLiveResources();
        await _liveService?.disconnect();
      }
      return;
    }

    if (mode == TranslationMode.freeHand) {
      _setState(AppState.listening, msg: "免手持模式: 聆听中...");
      try {
        if (!await _recorderService.hasPermission()) {
          _setState(AppState.error, msg: "麦克风权限被拒绝");
          return;
        }
        await _startNewRecordingFile();
        _startVAD();
      } catch (e) {
        _setState(AppState.error, msg: "启动失败: $e");
      }
      return;
    }

    _setState(AppState.listening, msg: "正在聆听...");
    try {
      if (!await _recorderService.hasPermission()) {
        _setState(AppState.error, msg: "麦克风权限被拒绝");
        return;
      }
      _currentRecordingPath = await _recorderService.getTempFilePath();
      await _recorderService.startRecording(_currentRecordingPath!);
    } catch (e) {
      _setState(AppState.error, msg: "录音错误: $e");
    }
  }

  Future<void> _startNewRecordingFile() async {
    _currentRecordingPath = await _recorderService.getTempFilePath();
    await _recorderService.startRecording(_currentRecordingPath!);
    _hasDetectedSpeech = false;
    _lastSpeechTime = null;
  }

  void _startVAD() {
    _vadTimer?.cancel();
    _vadTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_state != AppState.listening && _state != AppState.speaking) {
        timer.cancel();
        return;
      }

      if (_isRotating) return;

      if (_isPlayingOutput) {
        if (_hasDetectedSpeech) _lastSpeechTime = DateTime.now(); 
        return;
      }

      final amplitude = await _recorderService.getAmplitude();
      if (amplitude.current > _speechThreshold) {
        _hasDetectedSpeech = true;
        _lastSpeechTime = DateTime.now();
      } else {
        if (_hasDetectedSpeech && _lastSpeechTime != null) {
          final silenceDuration = DateTime.now().difference(_lastSpeechTime!).inMilliseconds;
          if (silenceDuration > _silenceDurationMs) {
            print("VAD: Silence detected, rotating...");
            _rotateRecording();
          }
        }
      }
    });
  }

  Future<void> _rotateRecording() async {
    if (_isRotating) return;
    _isRotating = true;

    try {
      final path = await _recorderService.stopRecording();
      await _startNewRecordingFile();
      _isRotating = false; 

      if (path != null) {
        final file = File(path);
        if (await file.length() > 1000) { 
          _processAudioTranslation(file, isBackground: true); 
        }
      }
    } catch (e) {
      print("Rotation error: $e");
      _isRotating = false;
    }
  }

  Future<void> stopRecording() async {
    if (_state != AppState.listening && _state != AppState.connecting && _state != AppState.processing) return;

    final mode = _activeRecordingMode ?? _config?.translationMode ?? TranslationMode.standard;

    if (mode == TranslationMode.live) {
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      await _recorderService.stopStream();
      await _liveService!.disconnect();
      _setState(AppState.idle, msg: "实时对话结束");
      _activeRecordingMode = null;
      return;
    }

    if (mode == TranslationMode.freeHand) {
      _vadTimer?.cancel();
      final path = await _recorderService.stopRecording();
      _setState(AppState.idle, msg: "免手持模式结束");
      _activeRecordingMode = null;
      if (path != null && _hasDetectedSpeech) {
         _processAudioTranslation(File(path), isBackground: true);
      }
      return;
    }

    try {
      final path = await _recorderService.stopRecording();
      _activeRecordingMode = null;
      if (path == null) {
        _setState(AppState.idle, msg: "录音失败");
        return;
      }
      
      final file = File(path);
      if (!await file.exists() || await file.length() < 100) {
        _setState(AppState.idle, msg: "录音太短");
        return;
      }

      await _processAudioTranslation(file);
    } catch (e) {
      _setState(AppState.error, msg: "停止录音错误: $e");
      _activeRecordingMode = null;
    }
  }

  Future<void> _processAudioTranslation(File audioFile, {bool isBackground = false}) async {
    if (_geminiService == null) return;
    if (!isBackground) _setState(AppState.processing, msg: "正在思考...");

    try {
      final result = await _geminiService!.translateAudio(audioFile);
      final detectedLang = result['detected_lang'] ?? 'unknown';
      final translatedText = result['translated_text'] ?? '';
      final sourceText = result['source_text'] ?? '[语音输入]';
      
      // Filter out invalid or noise input
      if (_isInvalidInput(sourceText)) {
        print("Filtered out noise input: $sourceText");
        if (!isBackground) _setState(AppState.idle, msg: "无效输入，已忽略");
        return;
      }

      if (translatedText.isEmpty) {
        if (!isBackground) _setState(AppState.error, msg: "无法翻译");
        return;
      }

      final docDir = await getApplicationDocumentsDirectory();
      final sessionId = _currentSession!.id!;
      final sessionDir = Directory(p.join(docDir.path, 'sessions', sessionId.toString()));
      if (!await sessionDir.exists()) await sessionDir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final savedInputPath = p.join(sessionDir.path, 'input_$timestamp.m4a');
      await audioFile.copy(savedInputPath);

      String? savedOutputPath;
      String ttsLang = (detectedLang == 'zh' || detectedLang == 'Chinese') ? 'en-US' : 'zh-CN';
      String outputFileName = 'output_$timestamp.wav';
      
      if (Platform.isWindows) {
         savedOutputPath = p.join(sessionDir.path, outputFileName);
         await _ttsService.synthesizeToFile(translatedText, savedOutputPath, ttsLang);
      } else {
         savedOutputPath = null; 
      }
      
      if (savedOutputPath != null) {
        final f = File(savedOutputPath);
        await Future.delayed(const Duration(milliseconds: 500)); 
        if (!await f.exists()) savedOutputPath = null;
      }

      final newRecord = TranslationRecord(
        sessionId: sessionId,
        sourceText: sourceText, 
        translatedText: translatedText,
        sourceLang: detectedLang,
        inputAudioPath: savedInputPath,
        outputAudioPath: savedOutputPath,
        createdAt: DateTime.now(),
      );

      await _dbService.insertRecord(newRecord);
      await loadSession(_currentSession!); 

      bool shouldSpeak = _config!.outputMode == OutputMode.both || _config!.outputMode == OutputMode.audio;
      if (shouldSpeak) {
        if (!isBackground) _setState(AppState.speaking, msg: "正在朗读...");
        await _ttsService.speak(translatedText, ttsLang);
      }
      
      if (!isBackground) _setState(AppState.idle, msg: "就绪");
    } catch (e) {
      if (!isBackground) _setState(AppState.error, msg: "错误: $e");
    }
  }

  bool _isInvalidInput(String text) {
    String cleanText = text.trim().toLowerCase().replaceAll(RegExp(r'[\p{P}\p{S}]', unicode: true), '');
    if (cleanText.isEmpty) return true;
    
    // Check if text is just punctuation
    if (RegExp(r'^[\p{P}\p{S}]+$', unicode: true).hasMatch(text)) return true;

    // Common noise words/hallucinations from STT/LLM on silent/noisy audio
    final noisePhrases = [
      '啊', '诶', '嗯', '哦', '呃', '哼', '哈', '唉', '哎', '切', '啧', '测试', '测试一下',
      'okay', 'ok', 'ah', 'oh', 'uh', 'um', 'thanks', 'thank you', 'hello', 'bye'
    ];

    if (cleanText.length <= 3 || text.length <= 2) {
      if (noisePhrases.contains(cleanText)) return true;
    }

    // If it's just a single very short word that is in noise list
    if (noisePhrases.contains(cleanText)) return true;

    return false;
  }

  // Playback
  Future<void> playInputAudio(TranslationRecord record) async {
    if (record.inputAudioPath == null) return;

    if (_playingRecordId == record.id && _isPlayingInput) {
      await _audioPlayer.pause();
    } else {
      await _ttsService.stop();
      _isPlayingOutput = false; 
      await _audioPlayer.stop();
      _playingRecordId = record.id;
      await _audioPlayer.play(DeviceFileSource(record.inputAudioPath!));
    }
    notifyListeners();
  }
  
  Future<void> playOutputAudio(TranslationRecord record) async {
    if (_playingRecordId == record.id && _isPlayingOutput) {
      await _ttsService.stop();
      _playingRecordId = null;
      _isPlayingOutput = false;
    } else {
      await _audioPlayer.stop();
      _isPlayingInput = false; 
      await _ttsService.stop();
      _playingRecordId = record.id;
      String ttsLang = (record.sourceLang == 'zh' || record.sourceLang == 'Chinese') ? 'en-US' : 'zh-CN';
      await _ttsService.speak(record.translatedText, ttsLang);
      _isPlayingOutput = true;
    }
    notifyListeners();
  }
}