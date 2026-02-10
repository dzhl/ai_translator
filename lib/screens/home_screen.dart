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

    // Scroll to bottom after build if new records added
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (provider.state == AppState.idle || provider.state == AppState.speaking) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(isMultiSelect 
          ? "已选择 ${provider.selectedRecordIds.length} 项" 
          : (provider.currentSession?.title ?? "AI Translator")),
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
           const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text(
              "正在聆听...",
              style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.blue),
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

  Widget _buildStandardControlArea(BuildContext context, TranslationProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.grey[100],
      child: Center(
        child: GestureDetector(
          onLongPressStart: (_) => provider.startRecording("auto"),
          onLongPressEnd: (_) => provider.stopRecording(),
          child: Container(
            width: 200,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: provider.state == AppState.listening 
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
                Icon(
                  provider.state == AppState.listening ? Icons.stop : Icons.mic, 
                  color: Colors.white, 
                  size: 28
                ),
                const SizedBox(width: 10),
                Text(
                  provider.state == AppState.listening ? "松开结束" : "按住翻译",
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

  Widget _buildLiveModeUI(BuildContext context, TranslationProvider provider) {
    return const Center(child: Text("实时对话模式暂未完全整合至 Session 系统"));
  }
}