import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:math' as math;
import 'package:vipt/app/data/models/workout.dart';
import 'package:vipt/app/data/models/collection_setting.dart';
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
                            _showQuickSettingsAndStartForSchedule(context, e);
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

  void _showQuickSettingsAndStartForSchedule(BuildContext context, Workout exercise) {
    // Default settings
    int selectedDuration = 45; // seconds
    int selectedRounds = 1;
    int selectedRestTime = 15; // seconds

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'Cài đặt nhanh'.tr,
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thời gian tập
                  Text(
                    'Thời gian tập'.tr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [30, 45, 60, 90].map((duration) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${duration}s'),
                            selected: selectedDuration == duration,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => selectedDuration = duration);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Số vòng
                  Text(
                    'Số vòng'.tr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [1, 2, 3].map((rounds) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('$rounds vòng'),
                            selected: selectedRounds == rounds,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => selectedRounds = rounds);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Rest time
                  Text(
                    'Thời gian nghỉ'.tr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [0, 15, 30, 45].map((rest) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(rest == 0 ? 'Không' : '${rest}s'),
                            selected: selectedRestTime == rest,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => selectedRestTime = rest);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[600], // Màu chữ xám đậm
                  ),
                  child: Text('Hủy'.tr),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _startWorkoutSessionFromSchedule(exercise, selectedDuration, selectedRounds, selectedRestTime);
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white, // Màu chữ trắng
                  ),
                  child: Text('Bắt đầu'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _startWorkoutSessionFromSchedule(Workout exercise, int duration, int rounds, int restTime) {
    // Create a single-workout collection for this session
    final singleWorkoutList = [exercise];

    // Create collection settings
    final settings = CollectionSetting(
      round: rounds,
      numOfWorkoutPerRound: 1, // Always 1 workout per round for single workout
      isStartWithWarmUp: false,
      isShuffle: false,
      exerciseTime: duration,
      transitionTime: 0,
      restTime: restTime,
      restFrequency: 1, // Rest after every exercise
    );

    // Navigate to workout session with single workout
    Get.toNamed(
      Routes.workoutSession,
      arguments: {
        'workouts': singleWorkoutList,
        'settings': settings,
        'title': exercise.name,
      },
    );
  }
}
