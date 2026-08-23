import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../database/db_helper.dart';
import '../services/gemini_service.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<MessageModel> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() async {
    final list = await DBHelper.instance.getAllMessages();
    setState(() {
      _messages.addAll(list);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    final userMsg = MessageModel(role: 'user', content: text, timestamp: DateTime.now().toIso8601String());
    _inputController.clear();

    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    await DBHelper.instance.insertMessage(userMsg);

    try {
      final res = await GeminiService.sendMessage(text, _messages.sublist(0, _messages.length - 1));
      
      final aiMsg = MessageModel(
        role: 'model',
        content: res.text,
        timestamp: DateTime.now().toIso8601String(),
      );
      
      await DBHelper.instance.insertMessage(aiMsg);
      setState(() {
        _messages.add(aiMsg);
      });
    } catch (e) {
      final errorMsg = MessageModel(
        role: 'model', 
        content: "⚠️ **Lỗi:** ${e.toString().replaceAll("Exception: ", "")}", 
        timestamp: DateTime.now().toIso8601String()
      );
      setState(() {
        _messages.add(errorMsg);
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C0C),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF3a0f0f), Color(0xFF5c1d1d)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Google Studio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, 0.4),
            radius: 1.5,
            colors: [Color(0xFF200707), Color(0xFF080808)],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome, size: 50, color: const Color(0xFF5c1d1d).withOpacity(0.8)),
                          const SizedBox(height: 16),
                          const Text("Google Studio Sẵn Sàng", style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          const Text("Nhập API Key trong Cài đặt và bắt đầu trò chuyện", style: TextStyle(color: Colors.white30, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isUser = msg.role == 'user';
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isUser ? const Color(0xFF5c1d1d) : const Color(0xFF161616),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                                bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                              ),
                              border: Border.all(
                                color: isUser ? Colors.transparent : const Color(0xFF3a0f0f).withOpacity(0.6),
                              ),
                            ),
                            child: isUser
                                ? Text(msg.content, style: const TextStyle(color: Colors.white, fontSize: 15))
                                : MarkdownBody(
                                    data: msg.content,
                                    styleSheet: MarkdownStyleSheet(
                                      p: const TextStyle(color: Color(0xFFE5E5E5), fontSize: 15, height: 1.45),
                                      code: const TextStyle(backgroundColor: Color(0xFF0A0A0A), color: Colors.amberAccent),
                                      codeblockDecoration: BoxDecoration(
                                        color: const Color(0xFF0A0A0A),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5c1d1d)),
                ),
              ),
            // Khung gõ phím Gemini Bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF0C0C0C),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF3a0f0f).withOpacity(0.8)),
                      ),
                      child: TextField(
                        controller: _inputController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Hỏi Google Studio bất cứ điều gì...',
                          hintStyle: TextStyle(color: Colors.white30),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF5c1d1d), Color(0xFF3a0f0f)]),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
