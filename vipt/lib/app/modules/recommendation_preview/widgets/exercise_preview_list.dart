import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vipt/app/data/models/workout.dart';
import 'package:vipt/app/data/models/collection_setting.dart';
import 'package:vipt/app/modules/recommendation_preview/recommendation_preview_controller.dart';
import 'package:vipt/app/modules/workout_collection/widgets/exercise_in_collection_tile.dart';
import 'package:vipt/app/routes/pages.dart';
// Import ApiClient
import 'package:vipt/app/data/services/api_client.dart';

class ExercisePreviewList extends StatelessWidget {
  final RecommendationPreviewController controller;

  const ExercisePreviewList({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        if (controller.recommendedExercises.isEmpty) {
          return const SizedBox.shrink();
        }

        final exercisesToShow = controller.recommendedExercises.toList();

        return Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${controller.recommendedExercises.length} bài tập',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    // show full list inline — no "Xem tất cả"
                  ],
                ),
              ),
              const Divider(height: 1),
              ...exercisesToShow.map((exercise) {
                // 1. Dùng Thumbnail (ảnh tĩnh)
                String assetToShow = exercise.thumbnail;

                // 2. Nếu đường dẫn là tương đối (/uploads...), ghép với serverUrl động
                if (assetToShow.startsWith('/uploads')) {
                  // Dùng biến serverUrl từ ApiClient thay vì hardcode IP
                  assetToShow = '${ApiClient.instance.serverUrl}$assetToShow';
                }

                return ExerciseInCollectionTile(
                  asset: assetToShow,
                  title: exercise.name,
                  description:
                      exercise.metValue > 0 ? 'MET: ${exercise.metValue}' : '',
                  onPressed: () {
                    _showQuickSettingsAndStart(context, exercise);
                  },
                );
              }).toList(),
              // show everything inline
            ],
          ),
        );
      },
    );
  }

  void _showQuickSettingsAndStart(BuildContext context, Workout exercise) {
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
                    _startWorkoutSession(exercise, selectedDuration, selectedRounds, selectedRestTime);
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

  void _startWorkoutSession(Workout exercise, int duration, int rounds, int restTime) {
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
