import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/translation_record.dart';
import '../providers/translation_provider.dart';

class TranslationBubble extends StatelessWidget {
  final TranslationRecord record;
  final bool isSelected;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const TranslationBubble({
    super.key,
    required this.record,
    this.isSelected = false,
    required this.onLongPress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranslationProvider>();
    bool isChineseSource = record.sourceLang == 'zh' || record.sourceLang == 'Chinese';
    Color bubbleColor = isChineseSource ? Colors.blue[50]! : Colors.green[50]!;

    bool isCurrentInputPlaying = provider.playingRecordId == record.id && provider.isPlayingInput;
    bool isCurrentOutputPlaying = provider.playingRecordId == record.id && provider.isPlayingOutput;

    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange[100] : bubbleColor,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: Colors.orange, width: 2) : null,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(
                _formatDateTime(record.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2.0),
                        child: Icon(Icons.mic, size: 16, color: Colors.grey),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          record.sourceText,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
                if (record.inputAudioPath != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: IconButton(
                      icon: Icon(
                        isCurrentInputPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline, 
                        color: Colors.blue
                      ),
                      onPressed: () => provider.playInputAudio(record),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    record.translatedText,
                    style: const TextStyle(fontSize: 17, color: Colors.black87),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isCurrentOutputPlaying ? Icons.stop_circle_outlined : Icons.volume_up, 
                    color: Colors.green
                  ),
                  onPressed: () => provider.playOutputAudio(record),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    String date = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    String time = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    return "$date $time";
  }
}