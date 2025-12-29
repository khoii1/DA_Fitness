import 'package:get/get.dart';
import 'package:vipt/app/modules/recommendation_preview/recommendation_preview_controller.dart';

class RecommendationPreviewBinding extends Bindings {
  @override
  void dependencies() {
    // Keep controller instance persistent so preview data does not change
    // every time the screen is entered. Use permanent put to retain state
    // until app is closed.
    Get.put(RecommendationPreviewController(), permanent: true);
  }
}

