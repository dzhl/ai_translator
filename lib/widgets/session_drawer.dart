import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/translation_provider.dart';
import '../models/session.dart';

class SessionDrawer extends StatelessWidget {
  const SessionDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TranslationProvider>();
    final sessions = provider.sessions;

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blue, Colors.purple]),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.translate, size: 48, color: Colors.white),
                  const SizedBox(height: 10),
                  const Text(
                    "会话管理",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text("新建对话"),
            onTap: () {
              _showCreateSessionDialog(context, provider);
            },
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final isSelected = provider.currentSession?.id == session.id;

                return ListTile(
                  selected: isSelected,
                  selectedTileColor: Colors.blue.withOpacity(0.1),
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(session.title),
                  subtitle: Text(
                    "${session.createdAt.year}-${session.createdAt.month}-${session.createdAt.day}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _confirmDeleteSession(context, provider, session),
                  ),
                  onTap: () {
                    provider.loadSession(session);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateSessionDialog(BuildContext context, TranslationProvider provider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("新建对话"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "请输入对话标题"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.createSession(controller.text);
                Navigator.pop(context);
                Navigator.pop(context); // Close drawer
              }
            }, 
            child: const Text("创建"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSession(BuildContext context, TranslationProvider provider, Session session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("删除对话"),
        content: Text("确定要删除对话 \"${session.title}\" 吗？这将永久删除所有相关的文字和语音记录。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          TextButton(
            onPressed: () {
              provider.deleteSession(session);
              Navigator.pop(context);
            }, 
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
