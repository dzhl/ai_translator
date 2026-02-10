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
  int _lastRecordCount = 0;
  int? _lastSessionId;
  AppState? _lastState;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // Use a small delay to ensure the list has finished building
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranslationProvider>();
    final mode = provider.config?.translationMode ?? TranslationMode.standard;
    final isMultiSelect = provider.isMultiSelectMode;

    // Check if we need to scroll to bottom
    final currentSessionId = provider.currentSession?.id;
    final recordsCount = provider.records.length;
    final currentState = provider.state;

    bool shouldScroll = false;
    if (currentSessionId != _lastSessionId) {
      _lastSessionId = currentSessionId;
      _lastRecordCount = recordsCount;
      shouldScroll = true;
    } else if (recordsCount > _lastRecordCount) {
      _lastRecordCount = recordsCount;
      shouldScroll = true;
    } else if (currentState != _lastState) {
      _lastState = currentState;
      shouldScroll = true;
    }

    if (shouldScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

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
            padding: const EdgeInsets.only(bottom: 30),
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
        
        _buildStatusPanel(context, provider),
          
        _buildStandardControlArea(context, provider),
      ],
    );
  }
        
          Widget _buildStatusPanel(BuildContext context, TranslationProvider provider) {
            if (provider.state == AppState.idle) return const SizedBox.shrink();
        
            Color bgColor;
            Color textColor;
            IconData icon;
            String text;
            bool showProgress = false;
        
                switch (provider.state) {
                  case AppState.listening:
                    final mode = provider.activeRecordingMode ?? provider.config?.translationMode ?? TranslationMode.standard;
                    bool isFreeHand = mode == TranslationMode.freeHand;
                    bgColor = Colors.blue.withOpacity(0.1);
                    textColor = Colors.blue;
                    icon = isFreeHand ? Icons.record_voice_over : Icons.mic;
                    text = isFreeHand ? "免手持模式：聆听中..." : "正在聆听...";
                    break;              case AppState.processing:
                bgColor = Colors.orange.withOpacity(0.1);
                textColor = Colors.orange[800]!;
                icon = Icons.psychology;
                text = "正在思考翻译...";
                showProgress = true;
                break;
              case AppState.speaking:
                bgColor = Colors.green.withOpacity(0.1);
                textColor = Colors.green;
                icon = Icons.volume_up;
                text = "正在朗读...";
                break;
              case AppState.connecting:
                bgColor = Colors.purple.withOpacity(0.1);
                textColor = Colors.purple;
                icon = Icons.cloud_sync;
                text = "正在连接服务...";
                showProgress = true;
                break;
              case AppState.error:
                bgColor = Colors.red.withOpacity(0.1);
                textColor = Colors.red;
                icon = Icons.error_outline;
                text = provider.statusMessage;
                break;
              default:
                return const SizedBox.shrink();
            }
        
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: textColor.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: textColor),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          text,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      backgroundColor: textColor.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(textColor),
                    ),
                  ],
                ],
              ),
            );
          }
        
          Widget _buildLiveModeUI(BuildContext context, TranslationProvider provider) {    bool isError = provider.state == AppState.error;
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
    bool isListening = provider.state == AppState.listening;
    bool isConnecting = provider.state == AppState.connecting;

    if (isLiveMode) {
      String buttonText = isConnecting ? "连接中..." : (isListening ? "结束对话" : "开始对话");
      return _buildSingleControlButton(
        context, 
        provider, 
        text: buttonText, 
        icon: isListening ? Icons.stop : Icons.mic,
        color: isListening || isConnecting ? Colors.red : Colors.blue,
        onTap: () {
          if (isListening || isConnecting) {
            provider.stopRecording();
          } else {
            provider.startRecording("auto", overrideMode: TranslationMode.live);
          }
        },
      );
    }

    // Two buttons for Standard and FreeHand
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      color: Colors.grey[100],
      child: Row(
        children: [
          // Standard Mode Button
          Expanded(
            child: _buildManualButton(context, provider),
          ),
          const SizedBox(width: 16),
          // FreeHand Mode Button
          Expanded(
            child: _buildFreeHandButton(context, provider),
          ),
        ],
      ),
    );
  }

  Widget _buildManualButton(BuildContext context, TranslationProvider provider) {
    bool isListeningManual = provider.state == AppState.listening && 
        provider.config?.translationMode != TranslationMode.freeHand;
    
    return GestureDetector(
      onLongPressStart: (_) => provider.startRecording("auto", overrideMode: TranslationMode.standard),
      onLongPressEnd: (_) => provider.stopRecording(),
      child: _buildButtonUI(
        text: isListeningManual ? "松开结束" : "按住翻译",
        icon: Icons.mic,
        isActive: isListeningManual,
        activeColor: Colors.orange,
        baseColor: Colors.blue,
      ),
    );
  }

  Widget _buildFreeHandButton(BuildContext context, TranslationProvider provider) {
    bool isListeningFreeHand = provider.state == AppState.listening && 
        (provider.config?.translationMode == TranslationMode.freeHand || true); // Allow toggle
    
    // Check if the provider is actually in free hand mode
    bool isActuallyFreeHand = provider.state == AppState.listening && 
        provider.statusMessage.contains("免手持");

    return GestureDetector(
      onTap: () {
        if (isActuallyFreeHand) {
          provider.stopRecording();
        } else {
          provider.startRecording("auto", overrideMode: TranslationMode.freeHand);
        }
      },
      child: _buildButtonUI(
        text: isActuallyFreeHand ? "结束免手持" : "开启免手持",
        icon: Icons.record_voice_over,
        isActive: isActuallyFreeHand,
        activeColor: Colors.red,
        baseColor: Colors.purple,
      ),
    );
  }

  Widget _buildButtonUI({
    required String text, 
    required IconData icon, 
    required bool isActive,
    required Color activeColor,
    required Color baseColor,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive ? [activeColor, activeColor.withOpacity(0.7)] : [baseColor, baseColor.withOpacity(0.7)]
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: (isActive ? activeColor : baseColor).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isActive ? Icons.stop : icon, color: Colors.white, size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleControlButton(
    BuildContext context, 
    TranslationProvider provider, 
    {required String text, required IconData icon, required Color color, required VoidCallback onTap}
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.grey[100],
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 200,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
              borderRadius: BorderRadius.circular(35),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Text(
                  text,
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