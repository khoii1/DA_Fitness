import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/core/values/values.dart';
import 'package:vipt/app/modules/recommendation_preview/recommendation_preview_controller.dart';
import 'package:vipt/app/modules/recommendation_preview/widgets/plan_info_card.dart';
import 'package:vipt/app/modules/recommendation_preview/widgets/recommendation_form.dart';
import 'package:vipt/app/modules/recommendation_preview/widgets/plan_schedule.dart';

class RecommendationPreviewScreen extends StatelessWidget {
  const RecommendationPreviewScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Ensure controller is registered. Sometimes this screen is navigated to
    // directly (not via HomeScreen) so HomeController's lazyPut might not have
    // run; register controller if missing to avoid null-check errors inside GetX.
    if (!Get.isRegistered<RecommendationPreviewController>()) {
      Get.put(RecommendationPreviewController(), permanent: true);
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Lộ trình đề xuất',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: GetX<RecommendationPreviewController>(
        builder: (controller) {
          if (controller.isLoading.value) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (controller.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColor.errorColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    controller.errorMessage!,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => controller.loadRecommendation(),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: AppDecoration.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Dựa trên thông tin của bạn, chúng tôi đã tạo một lộ trình phù hợp:',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),

                // Show form only when no created plan exists. After creation we
                // display only plan info + recommended exercises/meals.
                if (controller.recommendationData['createdPlanID'] == null) ...[
                  RecommendationForm(controller: controller),
                  const SizedBox(height: 16),
                ],

                // Plan Info Card
                PlanInfoCard(controller: controller),
                const SizedBox(height: 16),

                // If a plan exists, show full 7-day schedule (meals + exercises)
                if (controller.recommendationData['createdPlanID'] != null) ...[
                  PlanSchedule(controller: controller),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 16),

                // (Removed calorie card and preview lists as requested)
                const SizedBox(height: 16),

                // Single action button: create 7 days if no plan, otherwise extend by 7 days
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: Obx(() {
                    final hasPlan = controller.recommendationData['createdPlanID'] != null;
                    final isBusy = controller.isCreatingPlan.value || controller.isExtending.value;
                    final background = hasPlan ? Colors.green : Colors.transparent;
                    final foreground = hasPlan ? Colors.white : Colors.red;

                    return ElevatedButton(
                      onPressed: isBusy
                          ? null
                          : () async {
                              if (hasPlan) {
                                // Confirm delete + recreate
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Xóa và tạo lại'),
                                    content: const Text(
                                        'Bạn muốn xóa lộ trình hiện tại và tạo một lộ trình 7 ngày mới chứ?'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Hủy')),
                                      ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColor.primaryColor,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Xác nhận')),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await controller.deleteAndCreateNew7DayPlan();
                                }
                              } else {
                                await controller.deleteAndCreateNew7DayPlan();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: background,
                        elevation: hasPlan ? 2 : 0,
                        side: hasPlan ? null : BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        hasPlan ? 'Xóa và tạo 7 ngày mới' : 'Tạo lộ trình (7 ngày)',
                        style: TextStyle(
                          fontSize: 16,
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

 
}

