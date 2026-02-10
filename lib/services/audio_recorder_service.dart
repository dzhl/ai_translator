import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  Future<void> startRecording(String path) async {
    // Record to M4A (AAC LC) which is supported by Gemini API
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc), 
      path: path
    );
  }

  Future<String?> stopRecording() async {
    return await _recorder.stop();
  }

  Future<Stream<Uint8List>> startStream() async {
    return await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
  }

  Future<void> stopStream() async {
    await _recorder.stop();
  }
  
  Future<void> dispose() async {
    _recorder.dispose();
  }

  Future<String> getTempFilePath() async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${tempDir.path}/recording_$timestamp.m4a';
  }

  Future<Amplitude> getAmplitude() async {
    return await _recorder.getAmplitude();
  }
}
