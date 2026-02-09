import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_config.dart';

class LLMService {
  final AppConfig config;

  LLMService(this.config);

  Future<String> translate(String text, String sourceLang, String targetLang) async {
    if (config.apiKey.isEmpty) {
      return "⚠️ 请先在设置中填写 API Key";
    }

    // Determine target prompt based on language direction
    final systemPrompt = "You are a professional interpreter. Translate the following text from $sourceLang to $targetLang accurately and naturally. Only return the translated text, do not add any explanations.";

    final url = Uri.parse('${config.baseUrl}chat/completions');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config.apiKey}',
        },
        body: jsonEncode({
          'model': config.modelName,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': text}
          ],
          'temperature': 0.3, // Lower temperature for more deterministic translations
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices'][0]['message']['content'];
        return content.trim();
      } else {
        return "Translation Error: ${response.statusCode} - ${response.body}";
      }
    } catch (e) {
      return "Network Error: $e";
    }
  }
}
