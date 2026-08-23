import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../database/db_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool _obscureText = true;
  String _selectedModel = 'auto';

  final Map<String, String> _availableModels = {
    'auto': 'Tự động (Tối ưu nhất + Auto Fallback)',
    'gemini-2.0-flash': 'Gemini 2.0 Flash (Siêu nhanh, Mới nhất)',
    'gemini-2.0-flash-thinking-exp-01-21': 'Gemini 2.0 Flash Thinking (Suy luận sâu)',
    'gemini-2.0-pro-exp-02-05': 'Gemini 2.0 Pro (Mạnh nhất)',
    'gemini-1.5-pro-latest': 'Gemini 1.5 Pro',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final key = await GeminiService.getApiKey();
    final model = await GeminiService.getSelectedModel();
    setState(() {
      if (key != null) _keyController.text = key;
      _selectedModel = model;
    });
  }

  void _saveSettings() async {
    await GeminiService.saveApiKey(_keyController.text);
    await GeminiService.saveSelectedModel(_selectedModel);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã lưu cấu hình thành công!'),
        backgroundColor: Color(0xFF5c1d1d),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài Đặt Google Studio'),
        backgroundColor: const Color(0xFF080808),
        elevation: 0,
      ),
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF080808),
          gradient: RadialGradient(
            center: Alignment(0.8, -0.6),
            radius: 1.3,
            colors: [Color(0xFF3a0f0f), Color(0xFF080808)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Google AI Studio API Key",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF5c1d1d).withOpacity(0.6)),
                ),
                child: TextField(
                  controller: _keyController,
                  obscureText: _obscureText,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Dán mã API Key (AIzaSy...)',
                    hintStyle: const TextStyle(color: Colors.white24),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off, color: Colors.white54),
                      onPressed: () => setState(() => _obscureText = !_obscureText),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Chọn Mô Hình AI Hoạt Động",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3a0f0f)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedModel,
                    dropdownColor: const Color(0xFF1A1A1A),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF5c1d1d)),
                    items: _availableModels.entries.map((e) {
                      return DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedModel = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5c1d1d),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Lưu Thay Đổi', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
              const Divider(color: Colors.white12),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                title: const Text('Xóa toàn bộ lịch sử trò chuyện', style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('Xóa sạch database SQLite trên thiết bị', style: TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () async {
                  await DBHelper.instance.clearChatHistory();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xóa sạch dữ liệu trên máy!')),
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}
