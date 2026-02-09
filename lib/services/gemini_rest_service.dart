import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/app_config.dart';

class GeminiRestService {
  final AppConfig config;
  http.Client? _client;

  GeminiRestService(this.config) {
    _initClient();
  }

  void _initClient() {
    if (config.proxyUrl.isNotEmpty) {
      final httpClient = HttpClient();
      // Configure proxy
      httpClient.findProxy = (uri) {
        return "PROXY ${config.proxyUrl}";
      };
      // Allow self-signed certificates (often needed for local proxies)
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      _client = IOClient(httpClient);
    } else {
      _client = http.Client();
    }
  }

  /// Translates audio file using Gemini Native Multimodal API
  Future<Map<String, dynamic>> translateAudio(File audioFile) async {
    if (config.apiKey.isEmpty) {
      throw Exception("API Key is missing. Please set it in Settings.");
    }

    // Read audio file as Base64
    List<int> audioBytes = await audioFile.readAsBytes();
    String base64Audio = base64Encode(audioBytes);

    // Default to gemini-1.5-flash if not set or if it's an OpenAI model name
    String model = config.modelName;
    if (model.isEmpty || model.contains('gpt')) {
      model = 'gemini-1.5-flash';
    }

    // Construct the URL
    // Use the provided baseUrl from config
    String baseUrl = config.baseUrl;
    if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);

    // FIX: If the user provided an OpenAI compatibility URL (ending in /openai), remove it.
    // Native API calls should be to /v1beta/, NOT /v1beta/openai/
    if (baseUrl.endsWith('/openai')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 7); // Remove '/openai'
    }

    // If base URL includes 'openai' (compatibility endpoint), we might need to adjust or error out.
    // But since this service is specifically for Native API, we assume the user has set a native-compatible base URL.
    // Standard Google Native Base URL: https://generativelanguage.googleapis.com/v1beta/
    
    final url = Uri.parse('$baseUrl/models/$model:generateContent?key=${config.apiKey}');

    final prompt = """
You are a professional interpreter. 
1. Listen to the audio. 
2. Detect the language (Chinese or English). 
3. Translate it to the other language. 
4. Return ONLY a JSON object with this format: {"detected_lang": "zh", "translated_text": "..."}.
Do not include markdown formatting like ```json.
""";

    final body = jsonEncode({
      "contents": [{
        "parts": [
          {"text": prompt},
          {
            "inline_data": {
              // Note: AudioRecorderService records as AAC (.m4a container). 
              // 'audio/m4a' is not always standard, 'audio/aac' or 'audio/mp4' is safer for Gemini.
              "mime_type": "audio/aac", 
              "data": base64Audio
            }
          }
        ]
      }]
    });

    try {
      final response = await (_client ?? http.Client()).post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // Debug Log
        print("Gemini Response: $data");
        
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
           final candidate = data['candidates'][0];
           if (candidate['content'] != null && candidate['content']['parts'] != null) {
             String text = candidate['content']['parts'][0]['text'];
             
             // Clean up potential markdown code blocks
             text = text.replaceAll('```json', '').replaceAll('```', '').trim();
             
             try {
               // Try to parse JSON
               final jsonResult = jsonDecode(text);
               return jsonResult;
             } catch (e) {
               // Fallback if JSON parsing fails (model outputted raw text)
               return {
                 "detected_lang": "unknown",
                 "translated_text": text
               };
             }
           }
        }
        throw Exception("Empty response from Gemini");
      } else {
        // Include URL in error (masking key) for debugging 404s
        final safeUrl = url.toString().replaceAll(config.apiKey, '***');
        throw Exception("API Error ($safeUrl): ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      throw Exception("Network Error: $e");
    }
  }
}
