import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// ─────────────────────────────────────────────────────────────────────────────
///  AMD Inference Service
///
///  Routes LLM inference to a local Ollama server powered by an AMD GPU
///  (ROCm / Radeon / Instinct). Falls back gracefully to Gemini if the AMD
///  backend is unreachable.
///
///  Quick setup on an AMD machine:
///    # Install Ollama with ROCm support
///    curl -fsSL https://ollama.ai/install.sh | sh
///    ROCR_VISIBLE_DEVICES=0 ollama pull mistral
///    ROCR_VISIBLE_DEVICES=0 ollama serve
///
///  The app will auto-detect the backend and switch to it automatically.
/// ─────────────────────────────────────────────────────────────────────────────
class AmdInferenceService {
  // ── Configuration ─────────────────────────────────────────────────────────
  /// Base URL of the Ollama server. Change to your AMD machine's IP/hostname
  /// if not running locally (e.g. 'http://192.168.1.42:11434').
  static const String baseUrl = 'http://localhost:11434';

  /// Ollama model to use. Supported: mistral, llama3, gemma2, phi3, etc.
  static const String model = 'mistral';

  /// Label shown to users when AMD inference is active.
  static const String providerLabel = '⚡ AMD GPU (ROCm)';

  // ── Availability check ────────────────────────────────────────────────────
  /// Returns true when the Ollama/ROCm backend is reachable.
  static Future<bool> isAvailable() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        // Also verify our target model is installed
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final models = (data['models'] as List?)
                ?.map((m) => (m['name'] as String).split(':').first)
                .toList() ??
            [];
        debugPrint('[AMD] Ollama available. Models: $models');
        return models.contains(model) || models.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  // ── Inference ─────────────────────────────────────────────────────────────
  /// Send a [systemPrompt] + [userText] to the AMD backend.
  /// Returns the response string, or empty string on failure.
  static Future<String> query({
    required String systemPrompt,
    required String userText,
    double temperature = 0.7,
    int maxTokens = 600,
  }) async {
    try {
      final body = jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userText},
        ],
        'stream': false,
        'options': {
          'temperature': temperature,
          'num_predict': maxTokens,
        },
      });

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content =
            (data['message'] as Map<String, dynamic>?)?['content'] as String?;
        debugPrint('[AMD] Response received (${content?.length ?? 0} chars)');
        return content?.trim() ?? '';
      } else {
        debugPrint('[AMD] HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[AMD] Inference error: $e');
    }
    return '';
  }

  // ── List installed models ─────────────────────────────────────────────────
  /// Returns names of all Ollama models installed on the AMD machine.
  static Future<List<String>> listModels() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['models'] as List?)
                ?.map((m) => m['name'] as String)
                .toList() ??
            [];
      }
    } catch (_) {}
    return [];
  }
}
