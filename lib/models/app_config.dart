import 'package:shared_preferences/shared_preferences.dart';

enum STTProvider { system, openai }
enum TTSProvider { system, openai }
enum TranslationMode { standard, live, freeHand }
enum OutputMode { text, audio, both }

class AppConfig {
  String apiKey;
  String baseUrl;
  String modelName;
  STTProvider sttProvider;
  TTSProvider ttsProvider;
  double speechRate;
  
  TranslationMode translationMode;
  OutputMode outputMode;
  String liveWsUrl;
  int liveSampleRate;
  String proxyUrl;

  AppConfig({
    required this.apiKey,
    required this.baseUrl,
    required this.modelName,
    this.sttProvider = STTProvider.system,
    this.ttsProvider = TTSProvider.system,
    this.speechRate = 0.5,
    this.translationMode = TranslationMode.standard,
    this.outputMode = OutputMode.both,
    this.liveWsUrl = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent',
    this.liveSampleRate = 24000,
    this.proxyUrl = '',
  });

  factory AppConfig.defaultConfig() {
    return AppConfig(
      apiKey: '',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      modelName: 'gemini-1.5-flash-latest',
      sttProvider: STTProvider.system,
      ttsProvider: TTSProvider.system, // Fixed
      speechRate: 0.5,
      translationMode: TranslationMode.standard,
      outputMode: OutputMode.both,
      proxyUrl: '',
    );
  }

  // Save to SharedPrefs
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apiKey', apiKey);
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('modelName', modelName);
    await prefs.setInt('sttProvider', sttProvider.index);
    await prefs.setInt('ttsProvider', ttsProvider.index);
    await prefs.setDouble('speechRate', speechRate);
    await prefs.setInt('translationMode', translationMode.index);
    await prefs.setInt('outputMode', outputMode.index);
    await prefs.setString('liveWsUrl', liveWsUrl);
    await prefs.setInt('liveSampleRate', liveSampleRate);
    await prefs.setString('proxyUrl', proxyUrl);
  }

  // Load from SharedPrefs
  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfig(
      apiKey: prefs.getString('apiKey') ?? '',
      baseUrl: prefs.getString('baseUrl') ?? 'https://generativelanguage.googleapis.com/v1beta/',
      modelName: prefs.getString('modelName') ?? 'gemini-1.5-flash',
      sttProvider: STTProvider.values[prefs.getInt('sttProvider') ?? 0],
      ttsProvider: TTSProvider.values[prefs.getInt('ttsProvider') ?? 0],
      speechRate: prefs.getDouble('speechRate') ?? 0.5,
      translationMode: TranslationMode.values[prefs.getInt('translationMode') ?? 0],
      outputMode: OutputMode.values[prefs.getInt('outputMode') ?? 2], // Default to both
      liveWsUrl: prefs.getString('liveWsUrl') ?? 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent',
      liveSampleRate: prefs.getInt('liveSampleRate') ?? 24000,
      proxyUrl: prefs.getString('proxyUrl') ?? '',
    );
  }
}

class TranslationMessage {
  final String sourceText;
  final String translatedText;
  final String sourceLang; // 'zh' or 'en'
  final bool isUser; // true if it's the latest active record

  TranslationMessage({
    required this.sourceText,
    required this.translatedText,
    required this.sourceLang,
    this.isUser = true,
  });
}
