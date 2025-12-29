import 'package:flutter/material.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/modules/recommendation_preview/recommendation_preview_controller.dart';

class CalorieSummaryCard extends StatelessWidget {
  final RecommendationPreviewController controller;

  const CalorieSummaryCard({Key? key, required this.controller})
      : super(key: key);

  Widget _buildRow(BuildContext context, String label, String value,
      {bool highlighted = false}) {
    final textStyle = highlighted
        ? Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontWeight: FontWeight.w700, color: Colors.white)
        : Theme.of(context).textTheme.bodyLarge;

    final valueWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColor.primaryColor
            : AppColor.primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(value,
          style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.4),
              child: valueWidget,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bmr = controller.bmr;
    final tdee = controller.tdee;
    final intake = controller.dailyIntakeCalories;
    final outtake = controller.dailyOuttakeCalories;
    final net = controller.dailyGoalCalories;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department,
                    color: AppColor.primaryColor, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Calories hàng ngày',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildRow(context, 'BMR (Chuyển hóa cơ bản)', '$bmr cal'),
            const Divider(),
            _buildRow(context, 'TDEE (Tổng năng lượng tiêu hao)', '$tdee cal'),
            const Divider(),
            _buildRow(context, 'Calories cần nạp', '$intake cal'),
            _buildRow(context, 'Calories cần đốt', '$outtake cal'),
            const SizedBox(height: 8),
            _buildRow(context, 'Mục tiêu net calories', '$net cal',
                highlighted: true),
          ],
        ),
      ),
    );
  }
}
