import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:math' as math;
import 'package:vipt/app/modules/recommendation_preview/recommendation_preview_controller.dart';
import 'package:vipt/app/modules/workout_collection/widgets/exercise_in_collection_tile.dart';
import 'package:vipt/app/routes/pages.dart';

class PlanSchedule extends StatelessWidget {
  final RecommendationPreviewController controller;
  const PlanSchedule({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // derive start/end date
    DateTime start;
    DateTime end;
    try {
      start = recommendationDateFromString(
              controller.recommendationData['startDate']) ??
          DateTime.now();
    } catch (_) {
      start = DateTime.now();
    }
    try {
      end = recommendationDateFromString(
              controller.recommendationData['endDate']) ??
          start.add(const Duration(days: 6));
    } catch (_) {
      end = start.add(const Duration(days: 6));
    }

    final totalDays = end.difference(start).inDays + 1;
    // Ensure we only render up to 7 days in the UI regardless of server data.
    final displayDays = math.min(totalDays, 7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(displayDays, (index) {
        final date = DateUtils.dateOnly(start.add(Duration(days: index)));
        final key = controller.dateKey(date);
        final dayLabel = 'Ngày ${index + 1}';
        final dateLabel = controller.formatDate(date.toIso8601String());
        final meals = controller.scheduleMealsByDate[key] ?? [];
        final exercises = controller.scheduleExercisesByDate[key] ?? [];

        return Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(dayLabel,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(dateLabel,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 8),
                if (exercises.isNotEmpty) ...[
                  Text('${exercises.where((e) => e != null).length} bài tập',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  ...exercises.where((e) => e != null).map((e) =>
                      ExerciseInCollectionTile(
                        asset: e.thumbnail ?? '',
                        title: e.name ?? 'Unknown Exercise',
                        description:
                            (e.metValue ?? 0) > 0 ? 'MET: ${e.metValue}' : '',
                        onPressed: () {
                          if (e != null) {
                            Get.toNamed(Routes.exerciseDetail, arguments: e);
                          }
                        },
                      )),
                ],
                if (meals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('${meals.where((m) => m != null).length} bữa ăn',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  ...meals.where((m) => m != null).map((m) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(
                          width: 56,
                          height: 56,
                          child: m.asset.contains('http')
                              ? Image.network(m.asset,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                      'assets/images/nutrition_1.png'))
                              : Image.asset('assets/images/nutrition_1.png'),
                        ),
                        title: Text(m.name),
                        subtitle:
                            m.cookTime > 0 ? Text('${m.cookTime} phút') : null,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            Get.toNamed(Routes.dishDetail, arguments: m),
                      )),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }

  DateTime? recommendationDateFromString(String? s) {
    if (s == null) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }
}
