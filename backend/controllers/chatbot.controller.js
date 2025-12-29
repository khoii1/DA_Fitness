import dotenv from "dotenv";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load .env từ thư mục backend
dotenv.config({ path: join(__dirname, "..", ".env"), override: true });

/**
 * @desc    Send message to chatbot
 * @route   POST /api/chatbot/send-message
 * @access  Private (requires authentication)
 */
export const sendMessage = async (req, res) => {
  try {
    const { message, conversationHistory = [] } = req.body;

    if (!message || message.trim() === "") {
      return res.status(400).json({
        success: false,
        message: "Message không được để trống",
      });
    }

    // Lấy API key từ environment variables
    const geminiApiKey = process.env.GEMINI_API_KEY;

    if (!geminiApiKey) {
      console.error("GEMINI_API_KEY not found in environment variables");
      return res.status(500).json({
        success: false,
        message: "Cấu hình API key chưa đúng",
      });
    }

    // Tìm model khả dụng
    let availableModels = [];
    try {
      const modelsResponse = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models?key=${geminiApiKey}`
      );

      if (modelsResponse.ok) {
        const modelsData = await modelsResponse.json();
        if (modelsData.models) {
          for (const model of modelsData.models) {
            const name = model.name;
            const supportedMethods = model.supportedGenerationMethods;
            const supportsGenerateContent =
              supportedMethods?.includes("generateContent");

            if (
              supportsGenerateContent &&
              name.toLowerCase().includes("gemini")
            ) {
              const shortName = name.startsWith("models/")
                ? name.substring(7)
                : name;
              availableModels.push(shortName);
            }
          }
        }
      }
    } catch (error) {
      console.warn("Không thể lấy danh sách models:", error.message);
    }

    // Sắp xếp models ưu tiên Flash và Latest
    const sortedModels = availableModels.length > 0 ? [...availableModels] : [];
    sortedModels.sort((a, b) => {
      const lowerA = a.toLowerCase();
      const lowerB = b.toLowerCase();

      const aIsFlash = lowerA.includes("flash");
      const bIsFlash = lowerB.includes("flash");
      if (aIsFlash && !bIsFlash) return -1;
      if (!aIsFlash && bIsFlash) return 1;

      const aIsLatest = lowerA.includes("latest");
      const bIsLatest = lowerB.includes("latest");
      if (aIsLatest && !bIsLatest) return -1;
      if (!aIsLatest && bIsLatest) return 1;

      return 0;
    });

    // Danh sách endpoints
    const endpoints = [];
    const addedModels = new Set();

    // Thêm models khả dụng
    for (const model of sortedModels) {
      if (!addedModels.has(model)) {
        endpoints.push(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiApiKey}`
        );
        addedModels.add(model);
      }
    }

    // Models backup
    const backupModels = [
      "gemini-1.5-flash-latest",
      "gemini-1.5-flash",
      "gemini-1.5-pro-latest",
      "gemini-1.5-pro",
      "gemini-pro",
    ];

    for (const model of backupModels) {
      if (!addedModels.has(model)) {
        endpoints.push(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiApiKey}`
        );
        addedModels.add(model);
      }
    }

    let lastError = null;

    // Thử từng endpoint
    for (const endpoint of endpoints) {
      try {
        const result = await trySendMessage(
          endpoint,
          message,
          conversationHistory
        );
        return res.status(200).json({
          success: true,
          message: "Tin nhắn đã được gửi thành công",
          data: {
            response: result,
          },
        });
      } catch (error) {
        lastError = error;
        console.warn(
          `Endpoint failed: ${endpoint.substring(0, 100)}... - ${error.message}`
        );

        // Nếu là lỗi API key hoặc quota, không thử tiếp
        if (
          error.message.includes("API key") ||
          error.message.includes("quota") ||
          error.message.includes("permission") ||
          error.message.includes("403")
        ) {
          break;
        }
        continue;
      }
    }

    // Nếu tất cả endpoints đều fail
    let errorMessage = "Không thể kết nối với AI service. ";
    if (lastError) {
      if (lastError.message.includes("not found")) {
        errorMessage +=
          "Không tìm thấy model phù hợp. Vui lòng kiểm tra API key.";
      } else if (lastError.message.includes("timeout")) {
        errorMessage += "Kết nối quá chậm. Vui lòng thử lại sau.";
      } else {
        errorMessage += lastError.message;
      }
    }

    return res.status(500).json({
      success: false,
      message: errorMessage,
    });
  } catch (error) {
    console.error("Chatbot error:", error);
    return res.status(500).json({
      success: false,
      message: "Đã có lỗi xảy ra khi xử lý tin nhắn",
    });
  }
};

/**
 * Thử gửi message đến một endpoint cụ thể
 */
async function trySendMessage(apiUrl, userMessage, conversationHistory) {
  try {
    // Chuẩn bị contents
    const contents = [];

    // Thêm lịch sử cuộc trò chuyện
    for (const msg of conversationHistory) {
      if (!msg.role || !msg.content || msg.content.trim() === "") continue;

      if (msg.role !== "user" && msg.role !== "assistant") continue;

      const role = msg.role === "user" ? "user" : "model";
      contents.push({
        role: role,
        parts: [{ text: msg.content }],
      });
    }

    // Thông tin ngày tháng
    const now = new Date();
    const currentDate = `${now.getDate()}/${
      now.getMonth() + 1
    }/${now.getFullYear()}`;
    const daysOfWeek = [
      "Chủ nhật",
      "Thứ hai",
      "Thứ ba",
      "Thứ tư",
      "Thứ năm",
      "Thứ sáu",
      "Thứ bảy",
    ];
    const currentDay = daysOfWeek[now.getDay()];
    const currentDayFull = `$currentDay, ngày ${now.getDate()} tháng ${
      now.getMonth() + 1
    } năm ${now.getFullYear()}`;

    // Thêm message hiện tại
    contents.push({
      role: "user",
      parts: [{ text: userMessage }],
    });

    // System instruction
    const systemInstruction = `Bạn là trợ lý AI của ViPT về tập luyện và dinh dưỡng.

THÔNG TIN QUAN TRỌNG VỀ NGÀY THÁNG:
- Hôm nay là: ${currentDayFull}
- Ngày hiện tại: ${currentDate}

HƯỚNG DẪN TRẢ LỜI CÂU HỎI VỀ NGÀY THÁNG:
- Khi người dùng hỏi "hôm nay là ngày mấy", "hôm nay thứ mấy", "ngày hôm nay": Trả lời trực tiếp như "Hôm nay là ${currentDayFull}"
- Khi người dùng hỏi "ngày bao nhiêu", "tháng mấy": Trả lời trực tiếp như "Hôm nay là ngày ${now.getDate()} tháng ${
      now.getMonth() + 1
    } năm ${now.getFullYear()}"
- KHÔNG trả lời theo kiểu "theo thông tin trên" hoặc "theo dữ liệu có sẵn"

QUY TẮC TRẢ LỜI:
- Trả lời chính xác, ngắn gọn bằng tiếng Việt
- KHÔNG dùng markdown formatting như **, *, _, #, \`, []
- KHÔNG dùng ký tự đặc biệt như \$1, \$2, #1, #2
- Trả lời tự nhiên và dễ hiểu
- Khi liệt kê, HÃY DÙNG dấu gạch đầu dòng (-) để dễ đọc. Ví dụ:
  - Điểm 1
  - Điểm 2
  - Điểm 3
- Có thể dùng số thường (1, 2, 3) nhưng ưu tiên dùng gạch đầu dòng (-)`;

    const requestBody = {
      contents: contents,
    };

    // Thêm system instruction nếu là v1beta
    if (apiUrl.includes("/v1beta/")) {
      requestBody.systemInstruction = {
        parts: [{ text: systemInstruction }],
      };
    }

    // Gọi API
    const response = await fetch(apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
    });

    if (response.ok) {
      const data = await response.json();

      if (
        data.candidates &&
        data.candidates.length > 0 &&
        data.candidates[0].content &&
        data.candidates[0].content.parts &&
        data.candidates[0].content.parts.length > 0
      ) {
        return data.candidates[0].content.parts[0].text;
      } else {
        throw new Error(`Invalid response format: ${JSON.stringify(data)}`);
      }
    } else {
      let errorMsg = `HTTP ${response.status}`;
      try {
        const errorData = await response.json();
        errorMsg =
          errorData.error?.message || errorData.error?.toString() || errorMsg;
      } catch (e) {
        const responseText = await response.text();
        errorMsg = `HTTP ${response.status}: ${responseText.substring(0, 200)}`;
      }
      throw new Error(`API Error: ${errorMsg}`);
    }
  } catch (error) {
    throw error;
  }
}
