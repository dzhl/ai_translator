import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_config.dart';
import '../providers/translation_provider.dart';
import '../widgets/session_drawer.dart';
import '../widgets/translation_bubble.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranslationProvider>();
    final mode = provider.config?.translationMode ?? TranslationMode.standard;
    final isMultiSelect = provider.isMultiSelectMode;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (provider.state == AppState.idle || provider.state == AppState.speaking) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(isMultiSelect 
          ? "已选择 ${provider.selectedRecordIds.length} 项" 
          : (provider.currentSession?.title ?? "VoiceTranslator")),
        actions: [
          if (isMultiSelect)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDeleteSelected(context, provider),
            ),
          if (isMultiSelect)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => provider.clearSelection(),
            ),
          if (!isMultiSelect)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
        ],
      ),
      drawer: const SessionDrawer(),
      body: mode == TranslationMode.live 
          ? _buildLiveModeUI(context, provider)
          : _buildStandardModeUI(context, provider),
    );
  }

  Widget _buildStandardModeUI(BuildContext context, TranslationProvider provider) {
    final records = provider.records;
    bool isFreeHand = provider.config?.translationMode == TranslationMode.freeHand;
    
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              final isSelected = provider.selectedRecordIds.contains(record.id);
              
              return TranslationBubble(
                record: record,
                isSelected: isSelected,
                onLongPress: () {
                  provider.toggleRecordSelection(record.id!);
                },
                onTap: () {
                  if (provider.isMultiSelectMode) {
                    provider.toggleRecordSelection(record.id!);
                  }
                },
              );
            },
          ),
        ),
        if (provider.state == AppState.listening)
           Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              isFreeHand ? "免手持模式: 聆听中..." : "正在聆听...",
              style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.blue),
            ),
          ),
          if (provider.state == AppState.processing)
             const LinearProgressIndicator(),

          if (provider.state == AppState.error)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                provider.statusMessage,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          
          _buildStandardControlArea(context, provider),
      ],
    );
  }

  Widget _buildLiveModeUI(BuildContext context, TranslationProvider provider) {
    bool isError = provider.state == AppState.error;
    bool isConnecting = provider.state == AppState.connecting;
    bool isListening = provider.state == AppState.listening;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.spatial_audio_off, 
          size: 80, 
          color: isError ? Colors.red : (isListening ? Colors.green : Colors.blueGrey)
        ),
        const SizedBox(height: 20),
        Text(
          isConnecting ? "正在连接..." :
          isListening ? "实时对话已连接" : 
          isError ? "连接中断" : "点击下方按钮开始",
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (isConnecting || isListening || isError) ...[
          const SizedBox(height: 20),
          if (isConnecting) const CircularProgressIndicator(),
          if (isListening) 
             const Padding(
               padding: EdgeInsets.all(8.0),
               child: Text("正在聆听...", style: TextStyle(color: Colors.green)),
             ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              provider.statusMessage, 
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: isError ? Colors.red : Colors.blue),
            ),
          ),
        ],
        const Spacer(),
        _buildStandardControlArea(context, provider),
      ],
    );
  }

  Widget _buildStandardControlArea(BuildContext context, TranslationProvider provider) {
    bool isLiveMode = provider.config?.translationMode == TranslationMode.live;
    bool isFreeHand = provider.config?.translationMode == TranslationMode.freeHand;
    bool isListening = provider.state == AppState.listening;
    bool isConnecting = provider.state == AppState.connecting;

    String buttonText;
    if (isConnecting) {
      buttonText = "连接中...";
    } else if (isListening) {
      if (isLiveMode) buttonText = "结束对话";
      else if (isFreeHand) buttonText = "结束免手持";
      else buttonText = "松开结束";
    } else {
      if (isLiveMode) buttonText = "开始对话";
      else if (isFreeHand) buttonText = "开始免手持";
      else buttonText = "按住翻译";
    }

    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.grey[100],
      child: Center(
        child: GestureDetector(
          onTap: () {
            if (isLiveMode || isFreeHand) {
              if (isListening || isConnecting) {
                provider.stopRecording();
              } else {
                provider.startRecording("auto");
              }
            }
          },
          onLongPressStart: (_) {
            if (!isLiveMode && !isFreeHand) provider.startRecording("auto");
          },
          onLongPressEnd: (_) {
            if (!isLiveMode && !isFreeHand) provider.stopRecording();
          },
          child: Container(
            width: 200,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isListening || isConnecting
                  ? [Colors.red, Colors.orange] 
                  : [Colors.blue, Colors.purple]
              ),
              borderRadius: BorderRadius.circular(35),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isConnecting)
                  const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  )
                else
                  Icon(
                    isListening ? Icons.stop : (isFreeHand ? Icons.record_voice_over : Icons.mic), 
                    color: Colors.white, 
                    size: 28
                  ),
                const SizedBox(width: 10),
                Text(
                  buttonText,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteSelected(BuildContext context, TranslationProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认删除"),
        content: Text("确定要删除选中的 ${provider.selectedRecordIds.length} 条记录吗？相关的语音文件也将被删除。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          TextButton(
            onPressed: () {
              provider.deleteSelectedRecords();
              Navigator.pop(context);
            }, 
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}