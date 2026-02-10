class TranslationRecord {
  final int? id;
  final int sessionId;
  final String sourceText;
  final String translatedText;
  final String sourceLang; // 'zh' or 'en' etc.
  final String? inputAudioPath; // Path to user's recorded audio
  final String? outputAudioPath; // Path to synthesized TTS audio (optional)
  final DateTime createdAt;

  TranslationRecord({
    this.id,
    required this.sessionId,
    required this.sourceText,
    required this.translatedText,
    required this.sourceLang,
    this.inputAudioPath,
    this.outputAudioPath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'source_text': sourceText,
      'translated_text': translatedText,
      'source_lang': sourceLang,
      'input_audio_path': inputAudioPath,
      'output_audio_path': outputAudioPath,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory TranslationRecord.fromMap(Map<String, dynamic> map) {
    return TranslationRecord(
      id: map['id'],
      sessionId: map['session_id'],
      sourceText: map['source_text'],
      translatedText: map['translated_text'],
      sourceLang: map['source_lang'],
      inputAudioPath: map['input_audio_path'],
      outputAudioPath: map['output_audio_path'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
    );
  }
}