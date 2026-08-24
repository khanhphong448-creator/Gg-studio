import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const GeminiApp());
}

// -----------------------------------------------------------------------------
// 1. DATA MODELS
// -----------------------------------------------------------------------------
class ChatMessage {
  final String id;
  final String role; // 'user' hoặc 'model'
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] ?? const Uuid().v4(),
        role: json['role'] ?? 'user',
        text: json['text'] ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      );
}

class ChatSession {
  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] ?? const Uuid().v4(),
        title: json['title'] ?? 'Đoạn trò chuyện mới',
        messages: (json['messages'] as List? ?? [])
            .map((m) => ChatMessage.fromJson(m))
            .toList(),
        updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      );
}

// -----------------------------------------------------------------------------
// 2. MAIN APP
// -----------------------------------------------------------------------------
class GeminiApp extends StatelessWidget {
  const GeminiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini Native',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C92F6),
          surface: Colors.transparent,
        ),
      ),
      home: const MainChatScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. MAIN CHAT SCREEN
// -----------------------------------------------------------------------------
class MainChatScreen extends StatefulWidget {
  const MainChatScreen({super.key});

  @override
  State<MainChatScreen> createState() => _MainChatScreenState();
}

class _MainChatScreenState extends State<MainChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _apiKey = '';
  String _selectedModel = 'gemini-3.7-flash'; // Mặc định Gemini 3.7 Flash mới nhất
  bool _isLoading = false;
  List<ChatSession> _sessions = [];
  String? _currentSessionId;

  // Cá nhân hóa màu loang (Gradient)
  int _selectedGradientIndex = 0;
  final List<List<Color>> _gradientPresets = [
    [const Color(0xFF0F172A), const Color(0xFF1E1B4B), const Color(0xFF311042)],
    [const Color(0xFF08121E), const Color(0xFF06283D), const Color(0xFF034C52)],
    [const Color(0xFF1C0A2A), const Color(0xFF2C0B3E), const Color(0xFF4C0E32)],
    [const Color(0xFF141414), const Color(0xFF1F1F1F), const Color(0xFF0A0A0A)],
    [const Color(0xFF051923), const Color(0xFF003554), const Color(0xFF006494)],
  ];

  @override
  void initState() {
    super.initState();
    _loadStoredData();
  }

  Future<void> _loadStoredData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('gemini_api_key') ?? '';
      _selectedGradientIndex = prefs.getInt('gradient_index') ?? 0;
      _selectedModel = prefs.getString('selected_model') ?? 'gemini-3.7-flash';

      final historyJson = prefs.getString('chat_sessions');
      if (historyJson != null) {
        final List decoded = jsonDecode(historyJson);
        _sessions = decoded.map((s) => ChatSession.fromJson(s)).toList();
      }

      if (_sessions.isEmpty) {
        _createNewSession();
      } else {
        _currentSessionId = _sessions.first.id;
      }
    });

    if (_apiKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showApiKeyDialog());
    }
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_sessions.map((s) => s.toJson()).toList());
    await prefs.setString('chat_sessions', jsonStr);
  }

  void _createNewSession() {
    final newSession = ChatSession(
      id: const Uuid().v4(),
      title: 'Đoạn chat mới',
      messages: [],
      updatedAt: DateTime.now(),
    );
    setState(() {
      _sessions.insert(0, newSession);
      _currentSessionId = newSession.id;
    });
    _saveSessions();
  }

  ChatSession get _currentSession {
    return _sessions.firstWhere(
      (s) => s.id == _currentSessionId,
      orElse: () => _sessions.first,
    );
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (_apiKey.isEmpty) {
      _showApiKeyDialog();
      return;
    }

    _inputController.clear();
    final userMsg = ChatMessage(
      id: const Uuid().v4(),
      role: 'user',
      text: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _currentSession.messages.add(userMsg);
      _isLoading = true;
      if (_currentSession.messages.length == 1) {
        _currentSession.title = text.length > 25 ? '${text.substring(0, 25)}...' : text;
      }
      _currentSession.updatedAt = DateTime.now();
    });

    _scrollToBottom();
    _saveSessions();

    try {
      final responseText = await _callGeminiApi(text);
      final modelMsg = ChatMessage(
        id: const Uuid().v4(),
        role: 'model',
        text: responseText,
        timestamp: DateTime.now(),
      );

      setState(() {
        _currentSession.messages.add(modelMsg);
        _isLoading = false;
      });
      _scrollToBottom();
      _saveSessions();
    } catch (e) {
      setState(() {
        _currentSession.messages.add(ChatMessage(
          id: const Uuid().v4(),
          role: 'model',
          text: '⚠️ **Lỗi:** ${e.toString()}',
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
      });
      _saveSessions();
    }
  }

  Future<String> _callGeminiApi(String prompt) async {
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_selectedModel:generateContent?key=$_apiKey');

    final contents = _currentSession.messages.map((m) {
      return {
        'role': m.role == 'user' ? 'user' : 'model',
        'parts': [
          {'text': m.text}
        ]
      };
    }).toList();

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': contents,
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 4096,
        }
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['candidates'][0]['content']['parts'][0]['text'];
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['error']?['message'] ?? 'Status: ${response.statusCode}');
    }
  }

  void _scrollToBottom() {
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

  // ---------------------------------------------------------------------------
  // 4. DIALOGS & PANELS
  // ---------------------------------------------------------------------------
  void _showApiKeyDialog() {
    final keyCtrl = TextEditingController(text: _apiKey);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          backgroundColor: const Color(0xFF181A20).withOpacity(0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.vpn_key_rounded, color: Color(0xFF6C92F6)),
              SizedBox(width: 10),
              Text('Bộ Não Gemini API', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nhập Google AI Studio API Key:', style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 12),
              TextField(
                controller: keyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'AIzaSy...',
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _selectedModel,
                dropdownColor: const Color(0xFF1E1F22),
                decoration: InputDecoration(
                  labelText: 'Phiên bản Gemini Model',
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                items: const [
                  DropdownMenuItem(value: 'gemini-3.7-flash', child: Text('Gemini 3.7 Flash (Mới nhất)')),
                  DropdownMenuItem(value: 'gemini-2.5-flash', child: Text('Gemini 2.5 Flash')),
                  DropdownMenuItem(value: 'gemini-1.5-pro', child: Text('Gemini 1.5 Pro')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedModel = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final key = keyCtrl.text.trim();
                if (key.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('gemini_api_key', key);
                  await prefs.setString('selected_model', _selectedModel);
                  setState(() => _apiKey = key);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Lưu Kích Hoạt', style: TextStyle(color: Color(0xFF6C92F6), fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  void _showGradientPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FrostedContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tùy Chỉnh Màu Nền Loang (Gradient)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _gradientPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, idx) {
                  final isSelected = _selectedGradientIndex == idx;
                  return GestureDetector(
                    onTap: () async {
                      setState(() => _selectedGradientIndex = idx);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('gradient_index', idx);
                    },
                    child: Container(
                      width: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _gradientPresets[idx],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.white24,
                          width: isSelected ? 2.5 : 1,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check_circle_rounded, color: Colors.white) : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. GIAO DIỆN CHÍNH
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      drawer: _buildGeminiDrawer(),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _gradientPresets[_selectedGradientIndex],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildTopHeader(),
              Expanded(
                child: _currentSession.messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        itemCount: _currentSession.messages.length,
                        itemBuilder: (context, index) {
                          final msg = _currentSession.messages[index];
                          return ChatBubble(message: msg);
                        },
                      ),
              ),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FrostedContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    borderRadius: BorderRadius.circular(20),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C92F6)),
                        ),
                        SizedBox(width: 8),
                        Text('Gemini 3.7 Flash đang phản hồi...', style: TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              _buildBottomInput(bottomInset),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: FrostedContainer(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
                tooltip: 'Mở Menu Gemini',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              const Expanded(
                child: Text(
                  'Gemini 3.7 Flash',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.palette_outlined, color: Colors.white, size: 22),
                tooltip: 'Đổi màu Gradient',
                onPressed: _showGradientPicker,
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 22),
                tooltip: 'Cài đặt API Key',
                onPressed: _showApiKeyDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomInput(double bottomInset) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: bottomInset > 0 ? bottomInset + 8 : 16,
        top: 4,
      ),
      child: FrostedContainer(
        borderRadius: BorderRadius.circular(26),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                style: const TextStyle(fontSize: 15, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Hỏi Gemini...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFF4285F4), Color(0xFF9B51E0)]),
                ),
                child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white),
              ),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white12),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 36, color: Color(0xFF6C92F6)),
          ),
          const SizedBox(height: 14),
          const Text('Tôi có thể giúp gì cho bạn hôm nay?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildGeminiDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0D1017).withOpacity(0.96),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF6C92F6), size: 22),
                  const SizedBox(width: 10),
                  const Text('Gemini Sessions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                    onPressed: () {
                      _createNewSession();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final s = _sessions[index];
                  final isSelected = s.id == _currentSessionId;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: Colors.white.withOpacity(0.08),
                    leading: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: isSelected ? const Color(0xFF6C92F6) : Colors.white54,
                    ),
                    title: Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white30),
                      onPressed: () {
                        setState(() {
                          _sessions.removeAt(index);
                          if (_sessions.isEmpty) _createNewSession();
                          _currentSessionId = _sessions.first.id;
                        });
                        _saveSessions();
                      },
                    ),
                    onTap: () {
                      setState(() => _currentSessionId = s.id);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 6. GLASSMORPHISM CORE
// -----------------------------------------------------------------------------
class FrostedContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  const FrostedContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: borderRadius ?? BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 7. CHAT BUBBLE WIDGET
// -----------------------------------------------------------------------------
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(5),
              margin: const EdgeInsets.only(right: 8, top: 2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFF4285F4), Color(0xFF9B51E0)]),
              ),
              child: const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
            ),
          ],
          Flexible(
            child: FrostedContainer(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: isUser
                  ? Text(
                      message.text,
                      style: const TextStyle(fontSize: 14.5, color: Colors.white, height: 1.4),
                    )
                  : MarkdownBody(
                      data: message.text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 14.5, color: Colors.white, height: 1.4),
                        code: const TextStyle(backgroundColor: Colors.black45, fontFamily: 'monospace', fontSize: 13),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
