import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:io';
import '../models/app_config.dart';
import '../providers/translation_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _modelNameController;
  late TextEditingController _liveWsUrlController;
  late TextEditingController _proxyUrlController; // New Proxy Field
  
  String _selectedModel = 'gemini-1.5-flash-latest';
  TranslationMode _translationMode = TranslationMode.standard;
  OutputMode _outputMode = OutputMode.both;
  bool _isTesting = false;

  final Map<String, Map<String, String>> _modelPresets = {
    'gemini-1.5-flash-latest': {
      'name': 'Gemini 1.5 Flash',
      'url': 'https://generativelanguage.googleapis.com/v1beta',
    },
    'gemini-2.0-flash-exp': {
      'name': 'Gemini 2.0 Flash (New)',
      'url': 'https://generativelanguage.googleapis.com/v1beta',
    },
    'gpt-4o-mini': {
      'name': 'GPT-4o-mini',
      'url': 'https://api.openai.com/v1',
    },
    'deepseek-chat': {
      'name': 'DeepSeek-V3 (推荐)',
      'url': 'https://api.deepseek.com',
    },
    'qwen-turbo': {
      'name': 'Qwen-Turbo (通义千问)',
      'url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    },
    'custom': {
      'name': '自定义模型',
      'url': '',
    },
  };

  @override
  void initState() {
    super.initState();
    final config = context.read<TranslationProvider>().config!;
    _apiKeyController = TextEditingController(text: config.apiKey);
    _baseUrlController = TextEditingController(text: config.baseUrl);
    _modelNameController = TextEditingController(text: config.modelName);
    _liveWsUrlController = TextEditingController(text: config.liveWsUrl);
    _proxyUrlController = TextEditingController(text: config.proxyUrl);
    
    // Determine selected model preset
    if (_modelPresets.containsKey(config.modelName)) {
      _selectedModel = config.modelName;
    } else {
      _selectedModel = 'custom';
    }
    
    _translationMode = config.translationMode;
    _outputMode = config.outputMode;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelNameController.dispose();
    _liveWsUrlController.dispose();
    _proxyUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final provider = context.read<TranslationProvider>();
    final newConfig = AppConfig(
      apiKey: _apiKeyController.text,
      baseUrl: _baseUrlController.text,
      modelName: _modelNameController.text,
      sttProvider: provider.config!.sttProvider,
      ttsProvider: provider.config!.ttsProvider,
      speechRate: provider.config!.speechRate,
      translationMode: _translationMode,
      outputMode: _outputMode,
      liveWsUrl: _liveWsUrlController.text,
      proxyUrl: _proxyUrlController.text.trim(),
    );
    await provider.updateConfig(newConfig);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelNameController.text.trim();
    final proxy = _proxyUrlController.text.trim();

    if (apiKey.isEmpty) {
      _showSnackBar("Please enter an API Key");
      setState(() => _isTesting = false);
      return;
    }

    try {
      bool isGemini = baseUrl.contains('generativelanguage.googleapis.com');
      final Uri url;
      if (isGemini) {
        url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model?key=$apiKey');
      } else {
        String cleanBaseUrl = baseUrl;
        if (cleanBaseUrl.endsWith('/')) cleanBaseUrl = cleanBaseUrl.substring(0, cleanBaseUrl.length - 1);
        url = Uri.parse('$cleanBaseUrl/models');
      }

      // Configure Client with Proxy if needed
      http.Client client;
      if (proxy.isNotEmpty) {
        final httpClient = HttpClient();
        httpClient.findProxy = (uri) {
          return "PROXY $proxy";
        };
        httpClient.badCertificateCallback = (cert, host, port) => true;
        client = IOClient(httpClient);
      } else {
        client = http.Client();
      }

      final response = await client.get(
        url,
        headers: isGemini ? {} : {'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode == 200) {
        _showSnackBar("✅ Connection Successful!", color: Colors.green);
      } else {
        _showSnackBar("❌ Error: ${response.statusCode} - ${response.body}", color: Colors.red);
      }
    } catch (e) {
      _showSnackBar("❌ Network Error: $e", color: Colors.red);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  void _showSnackBar(String message, {Color color = Colors.black87}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader("Interaction Mode"),
          const SizedBox(height: 10),
          SegmentedButton<TranslationMode>(
            segments: const [
              ButtonSegment(
                value: TranslationMode.standard, 
                label: Text("Standard"),
                icon: Icon(Icons.mic),
              ),
              ButtonSegment(
                value: TranslationMode.live, 
                label: Text("Live"),
                icon: Icon(Icons.spatial_audio_off),
              ),
              ButtonSegment(
                value: TranslationMode.freeHand, 
                label: Text("Free Hand"),
                icon: Icon(Icons.record_voice_over),
              ),
            ],
            selected: {_translationMode},
            onSelectionChanged: (Set<TranslationMode> newSelection) {
              setState(() {
                _translationMode = newSelection.first;
              });
            },
          ),
          
          if (_translationMode == TranslationMode.standard || _translationMode == TranslationMode.freeHand) ...[
            const SizedBox(height: 20),
            _buildSectionHeader("Output Preference"),
            const SizedBox(height: 10),
            DropdownButtonFormField<OutputMode>(
              value: _outputMode,
              decoration: const InputDecoration(labelText: "Output Mode"),
              items: const [
                DropdownMenuItem(value: OutputMode.text, child: Text("Text Only")),
                DropdownMenuItem(value: OutputMode.audio, child: Text("Audio Only")),
                DropdownMenuItem(value: OutputMode.both, child: Text("Both (Text + Audio)")),
              ],
              onChanged: (value) => setState(() => _outputMode = value!),
            ),
          ],

          const SizedBox(height: 20),
          _buildSectionHeader("AI Configuration"),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            decoration: const InputDecoration(labelText: "Model Preset"),
            items: _modelPresets.entries.map((e) => DropdownMenuItem(
              value: e.key, 
              child: Text(e.value['name']!)
            )).toList(),
            onChanged: (value) {
              setState(() {
                _selectedModel = value!;
                if (value != 'custom') {
                  _modelNameController.text = value;
                  _baseUrlController.text = _modelPresets[value]!['url']!;
                }
              });
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _modelNameController,
            decoration: const InputDecoration(labelText: "Model Name"),
            enabled: _selectedModel == 'custom',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(labelText: "Base URL (REST)"),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(labelText: "API Key"),
            obscureText: true,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _proxyUrlController,
            decoration: const InputDecoration(
              labelText: "Proxy URL (Optional)",
              hintText: "e.g., 127.0.0.1:7890",
            ),
          ),
          
          // Test Button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                : const Icon(Icons.check_circle_outline),
              label: Text(_isTesting ? "Testing..." : "Test Connection"),
            ),
          ),

          if (_translationMode == TranslationMode.live) ...[
             const SizedBox(height: 20),
             _buildSectionHeader("Live Configuration"),
             const SizedBox(height: 10),
             TextField(
               controller: _liveWsUrlController,
               decoration: const InputDecoration(labelText: "WebSocket URL"),
             ),
          ],
          
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _saveConfig,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text("Save Configuration"),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  }
}
