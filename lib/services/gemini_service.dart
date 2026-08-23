import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';

class ModelResponse {
  final String text;
  final String usedModel;

  ModelResponse({required this.text, required this.usedModel});
}

class GeminiService {
  // Chuỗi Model tự động đổi nếu model trước bị nghẽn
  static const List<String> defaultFallbackChain = [
    'gemini-2.0-flash',
    'gemini-2.0-flash-thinking-exp-01-21',
    'gemini-2.0-pro-exp-02-05',
    'gemini-1.5-pro-latest',
    'gemini-1.5-flash-latest',
  ];

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('gemini_api_key');
  }

  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
  }

  static Future<String> getSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_model') ?? 'auto';
  }

  static Future<void> saveSelectedModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_model', model);
  }

  static Future<ModelResponse> sendMessage(String prompt, List<MessageModel> history) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception("Chưa cài API Key. Hãy vào góc phải màn hình chọn 'Cài đặt' để thêm key.");
    }

    final selectedModel = await getSelectedModel();
    List<String> modelsToTry = [];
    if (selectedModel == 'auto') {
      modelsToTry = List.from(defaultFallbackChain);
    } else {
      modelsToTry = [selectedModel, ...defaultFallbackChain.where((m) => m != selectedModel)];
    }

    final contents = history.map((msg) {
      return {
        'role': msg.role == 'user' ? 'user' : 'model',
        'parts': [{'text': msg.content}]
      };
    }).toList();

    contents.add({
      'role': 'user',
      'parts': [{'text': prompt}]
    });

    List<String> errorLogs = [];

    for (String model in modelsToTry) {
      try {
        final result = await _callApi(model, apiKey, contents);
        if (result != null && result.isNotEmpty) {
          return ModelResponse(text: result, usedModel: model);
        }
      } catch (e) {
        errorLogs.add("[$model: $e]");
        continue;
      }
    }

    throw Exception("Mọi mô hình AI đều lỗi:\n${errorLogs.join('\n')}");
  }

  static Future<String?> _callApi(String model, String apiKey, List<Map<String, dynamic>> contents) async {
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');

    final payload = {
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 8192,
      },
    };

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 35));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts = candidates[0]['content']['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text'].toString().trim();
        }
      }
      return null;
    } else {
      final errorData = jsonDecode(response.body);
      final msg = errorData['error']?['message'] ?? 'Mã lỗi: ${response.statusCode}';
      throw Exception(msg);
    }
  }
}
