import 'package:flutter/foundation.dart' show kDebugMode;
import '../../data/services/api_client.dart';

class ChatbotService {
  final ApiClient _apiClient;

  ChatbotService(this._apiClient);

  // Method này không còn cần thiết vì backend sẽ xử lý
  Future<List<String>> getAvailableModels() async {
    // Trả về danh sách models mặc định
    return [
      'gemini-1.5-flash-latest',
      'gemini-1.5-flash',
      'gemini-1.5-pro-latest',
      'gemini-1.5-pro',
    ];
  }

  Future<String> sendMessage(
      String userMessage, List<Map<String, String>> conversationHistory) async {
    try {
      if (kDebugMode) {
        print('📤 Đang gửi tin nhắn: $userMessage');
      }

      final response = await _apiClient.post('/chatbot/send-message', {
        'message': userMessage,
        'conversationHistory': conversationHistory,
      });

      if (response['success'] == true && response['data'] != null) {
        final botResponse = response['data']['response'];
        if (kDebugMode) {
          print('Nhận phản hồi từ chatbot');
        }
        return botResponse;
      } else {
        throw Exception(response['message'] ?? 'Unknown error from server');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Lỗi khi gửi tin nhắn: $e');
      }

      String errorMessage = 'Không thể kết nối với chatbot. ';
      if (e.toString().contains('timeout')) {
        errorMessage += 'Kết nối quá chậm. Vui lòng thử lại sau.';
      } else if (e.toString().contains('network')) {
        errorMessage += 'Vui lòng kiểm tra kết nối mạng.';
      } else {
        errorMessage += e.toString();
      }

      throw Exception(errorMessage);
    }
  }
}
