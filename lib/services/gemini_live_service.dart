import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:sound_stream/sound_stream.dart';
import '../models/app_config.dart';

class GeminiLiveService {
  final AppConfig config;
  WebSocketChannel? _channel;
  final PlayerStream _player = PlayerStream();
  bool _isConnected = false;
  
  // Stream controller to expose text updates to UI
  final _textController = StreamController<String>.broadcast();
  Stream<String> get textStream => _textController.stream;

  GeminiLiveService(this.config);

  Future<void> connect() async {
    if (_isConnected) return;

    try {
      // 1. Initialize Audio Player
      // Live API typically returns 24kHz audio
      await _player.initialize(
        sampleRate: config.liveSampleRate, 
        showLogs: false,
      );
      
      // 2. Connect WebSocket
      final uri = Uri.parse('${config.liveWsUrl}?key=${config.apiKey}');
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      
      // Start player stream
      await _player.start();

      // 3. Listen for messages
      _channel!.stream.listen(
        (message) {
          if (message is String) {
            _handleMessage(message);
          } else {
            print("Received binary message (unexpected)");
          }
        },
        onError: (error) {
          print("WS Error: $error");
          disconnect();
        },
        onDone: () {
          print("WS Closed");
          disconnect();
        },
      );

      // 4. Send Setup Message
      _sendSetupMessage();

    } catch (e) {
      print("Connection Error: $e");
      disconnect();
      rethrow;
    }
  }

  void _sendSetupMessage() {
    final setup = {
      "setup": {
        "model": "models/gemini-2.0-flash-exp", 
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
