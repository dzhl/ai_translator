import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:sound_stream/sound_stream.dart';
import '../models/app_config.dart';

class GeminiLiveService {
  final AppConfig config;
  WebSocketChannel? _channel;
  final PlayerStream _player = PlayerStream();
  bool _isConnected = false;
  
  // Callbacks
  Function(String)? onError;
  Function()? onDisconnected;
  
  // Stream controller to expose text updates to UI
  final _textController = StreamController<String>.broadcast();
  Stream<String> get textStream => _textController.stream;

  GeminiLiveService(this.config);

  Future<void> connect() async {
    if (_isConnected) return;

    try {
      // 1. Initialize Audio Player
      await _player.initialize(
        sampleRate: config.liveSampleRate, 
        showLogs: false,
      );
      
      // 2. Connect WebSocket with Proxy support
      final uri = Uri.parse('${config.liveWsUrl}?key=${config.apiKey}');
      
      final HttpClient client = HttpClient();
      if (config.proxyUrl.isNotEmpty) {
        client.findProxy = (uri) {
          return "PROXY ${config.proxyUrl}";
        };
        client.badCertificateCallback = (cert, host, port) => true;
      }

      final WebSocket ws = await WebSocket.connect(
        uri.toString(), 
        customClient: client
      ).timeout(const Duration(seconds: 10));

      _channel = IOWebSocketChannel(ws);
      _isConnected = true;
      
      // Start player stream
      await _player.start();

      // 3. Listen for messages
      _channel!.stream.listen(
        (message) {
          if (message is String) {
            _handleMessage(message);
          }
        },
        onError: (error) {
          print("WS Error: $error");
          if (onError != null) onError!(error.toString());
          disconnect();
        },
        onDone: () {
          final code = _channel?.closeCode;
          final reason = _channel?.closeReason;
          print("WS Closed. Code: $code, Reason: $reason");
          
          if (_isConnected && code != null && code > 1001) {
            if (onError != null) onError!("服务器断开 ($code): $reason");
          } else if (onDisconnected != null) {
            onDisconnected!();
          }
          disconnect();
        },
      );

      // 4. Send Setup Message
      _sendSetupMessage();

    } catch (e) {
      print("Connection Error: $e");
      _isConnected = false;
      if (onError != null) onError!(e.toString());
      rethrow;
    }
  }

  void _sendSetupMessage() {
    String model = config.modelName;
    if (!model.startsWith('models/')) {
      model = 'models/$model';
    }
    // Live API requires gemini-2.0
    if (!model.contains('gemini-2.0')) {
      model = 'models/gemini-2.0-flash-exp';
    }

    final setup = {
      "setup": {
        "model": model, 
        "generation_config": {
          "response_modalities": ["AUDIO"], 
          "speech_config": {
            "voice_config": {
              "prebuilt_voice_config": {"voice_name": "Puck"}
            }
          }
        }
      }
    };
    _channel?.sink.add(jsonEncode(setup));
  }

  void sendAudioChunk(Uint8List data) {
    if (!_isConnected) return;
    
    final msg = {
      "realtime_input": {
        "media_chunks": [
          {
            "mime_type": "audio/pcm",
            "data": base64Encode(data)
          }
        ]
      }
    };
    _channel?.sink.add(jsonEncode(msg));
  }

  void _handleMessage(String message) {
    try {
      final data = jsonDecode(message);
      
      // Handle Server Content (check both camelCase and snake_case just in case)
      final serverContent = data['serverContent'] ?? data['server_content'];
      
      if (serverContent != null) {
        final modelTurn = serverContent['modelTurn'] ?? serverContent['model_turn'];
        
        if (modelTurn != null) {
          final parts = (modelTurn['parts'] as List);
          for (var part in parts) {
            final text = part['text'];
            if (text != null) {
              _textController.add(text);
            }
            
            final inlineData = part['inlineData'] ?? part['inline_data'];
            if (inlineData != null) {
              final mimeType = inlineData['mimeType'] ?? inlineData['mime_type'];
              if (mimeType.startsWith('audio/pcm')) {
                final audioData = base64Decode(inlineData['data']);
                _player.writeChunk(audioData);
              }
            }
          }
        }
      }
    } catch (e) {
      print("Error parsing message: $e");
    }
  }

  Future<void> disconnect() async {
    if (!_isConnected) return;
    _isConnected = false;
    await _channel?.sink.close();
    await _player.stop();
  }
  
  void dispose() {
    disconnect();
    _textController.close();
    _player.dispose();
  }
}
