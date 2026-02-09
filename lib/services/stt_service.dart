import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/material.dart';

class STTService {
  late stt.SpeechToText _speech;
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  Function(String)? onResultCallback;
  Function(String)? onErrorCallback;

  STTService() {
    _speech = stt.SpeechToText();
  }

  Future<bool> init() async {
    if (!_isInitialized) {
      try {
        _isInitialized = await _speech.initialize(
          onStatus: (status) {
            print('STT Status: $status');
            if (status == 'done' || status == 'notListening') {
              _isListening = false;
            }
          },
          onError: (errorNotification) {
            print('STT Error: $errorNotification');
            if (onErrorCallback != null) {
              onErrorCallback!(errorNotification.errorMsg);
            }
            _isListening = false;
          },
        );
      } catch (e) {
        print('STT Init Error: $e');
        _isInitialized = false;
      }
    }
    return _isInitialized;
  }

  Future<void> listen({
    required String localeId,
    required Function(String) onResult,
  }) async {
    if (!_isInitialized) {
      bool success = await init();
      if (!success) {
        if (onErrorCallback != null) onErrorCallback!("Speech recognition not available");
        return;
      }
    }

    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        _isListening = true;
        _speech.listen(
          onResult: (val) {
            if (val.finalResult) {
              onResult(val.recognizedWords);
              _isListening = false; // Stop listening after final result
              _speech.stop();
            }
          },
          localeId: localeId,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        );
      }
    }
  }

  Future<void> stop() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }
  }
}
