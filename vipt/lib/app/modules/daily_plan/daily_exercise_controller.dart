import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/data/models/exercise_tracker.dart';
import 'package:vipt/app/data/others/tab_refesh_controller.dart';
import 'package:vipt/app/data/providers/exercise_track_provider.dart';
import 'package:vipt/app/data/providers/meal_nutrition_track_provider.dart';
import 'package:vipt/app/global_widgets/custom_confirmation_dialog.dart';
import 'package:vipt/app/modules/daily_plan/tracker_controller.dart';
import 'package:vipt/app/modules/workout_plan/workout_plan_controller.dart';
import 'dart:async';

class DailyExerciseController extends GetxController
    with TrackerController, WidgetsBindingObserver {
  final _provider = ExerciseTrackProvider();
  Rx<int> calories = 0.obs;
  Rx<int> sessions = 0.obs;
  Rx<double> time = 0.0.obs;
  Rx<int> intakeCalo = 0.obs;
  Rx<int> dailyGoalCalories = 0.obs;
  DateTime? _lastDate;
  Timer? _dailyResetTimer;

  @override
  void onInit() async {
    super.onInit();

    // Register as observer for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    isLoading.value = true;
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    // Check if it's a new day compared to last stored date
    if (_lastDate == null || !_isSameDate(_lastDate!, today)) {
      // New day - reset and fetch fresh data
      await fetchTracksByDate(today);
      _lastDate = today;
    } else {
      // Same day - just fetch existing data
      await fetchTracksByDate(_lastDate!);
    }

    // Schedule daily reset check
    _scheduleDailyResetCheck();

    // Load daily goal calories from workout plan
    try {
      final workoutController = Get.find<WorkoutPlanController>();
      dailyGoalCalories.value = workoutController.dailyGoalCalories.value;
    } catch (e) {
      // Fallback to default value if workout controller not found
      dailyGoalCalories.value = 690; // Default goal
    }

    isLoading.value = false;
  }

  @override
  fetchTracksByDate(DateTime date) async {
    this.date = date;
    tracks = await _provider.fetchByDate(date);
    calories.value = 0;
    sessions.value = 0;
    time.value = 0;
    tracks.map((e) {
      e = e as ExerciseTracker;
      calories.value += e.outtakeCalories;
      time.value += e.totalTime;
      sessions.value += e.sessionNumber;
    }).toList();

    // Also load nutrition tracks for this date to compute intake calories (net = intake - outtake)
    try {
      final mealProvider = MealNutritionTrackProvider();
      final mealTracks = await mealProvider.fetchByDate(date);
      intakeCalo.value = 0;
      mealTracks.map((m) {
        try {
          final mt = m;
          intakeCalo.value += mt.intakeCalories;
        } catch (_) {}
      }).toList();
    } catch (_) {
      intakeCalo.value = 0;
    }

    // Update last date when fetching data
    _lastDate = DateTime(date.year, date.month, date.day);

    update();
  }

  Future<void> addTrack(int newCalories) async {
    // Chỉ cho phép thêm calo dương (calo tiêu thụ phải > 0)
    if (newCalories <= 0) return;

    calories.value += newCalories;
    ExerciseTracker et = ExerciseTracker(
        date: date,
        outtakeCalories: newCalories,
        sessionNumber: 0,
        totalTime: 0);
    et = await _provider.add(et);
    tracks.add(et);
    update();

    _markRelevantTabToUpdate();
  }

  Future<void> deleteTrack(ExerciseTracker et) async {
    final result = await showDialog(
      context: Get.context!,
      builder: (BuildContext context) {
        return CustomConfirmationDialog(
          label: 'Xóa log luyện tập',
          content:
              'Bạn có chắc chắn muốn xóa log này? Bạn sẽ không thể hoàn tác lại thao tác này.',
          labelCancel: 'Không',
          labelOk: 'Có',
          onCancel: () {
            Navigator.of(context).pop();
          },
          onOk: () {
            Navigator.of(context).pop(OkCancelResult.ok);
          },
          primaryButtonColor: AppColor.exerciseBackgroundColor,
          buttonFactorOnMaxWidth: 0.32,
          buttonsAlignment: MainAxisAlignment.spaceEvenly,
        );
      },
    );

    if (result == OkCancelResult.ok) {
      calories.value -= et.outtakeCalories;
      tracks.remove(et);
      await _provider.delete(et.id ?? 0);
      update();

      _markRelevantTabToUpdate();
    }
  }

  bool _isSameDate(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  void _markRelevantTabToUpdate() {
    if (!RefeshTabController.instance.isProfileTabNeedToUpdate) {
      RefeshTabController.instance.toggleProfileTabUpdate();
    }

    if (!RefeshTabController.instance.isPlanTabNeedToUpdate) {
      RefeshTabController.instance.togglePlanTabUpdate();
    }
  }

  void _scheduleDailyResetCheck() {
    // Calculate time until next midnight
    DateTime now = DateTime.now();
    DateTime nextMidnight = DateTime(now.year, now.month, now.day + 1);
    Duration timeUntilMidnight = nextMidnight.difference(now);

    // Schedule timer to check at midnight
    _dailyResetTimer?.cancel();
    _dailyResetTimer = Timer(timeUntilMidnight, () {
      _checkAndResetForNewDay();
      // Schedule next check
      _scheduleDailyResetCheck();
    });
  }

  void _checkAndResetForNewDay() async {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    // Check if it's a new day
    if (_lastDate == null || !_isSameDate(_lastDate!, today)) {
      debugPrint('🔄 New day detected! Resetting exercise calories to 0');

      // Reset to new day
      await fetchTracksByDate(today);
      _lastDate = today;

      // Schedule next daily check
      _scheduleDailyResetCheck();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _dailyResetTimer?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkAndResetForNewDay();
    }
  }
}
