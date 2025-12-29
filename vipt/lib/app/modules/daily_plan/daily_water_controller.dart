import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/data/models/water_tracker.dart';
import 'package:vipt/app/data/others/tab_refesh_controller.dart';
import 'package:vipt/app/data/providers/water_track_provider.dart';
import 'package:vipt/app/global_widgets/custom_confirmation_dialog.dart';
import 'package:vipt/app/modules/daily_plan/tracker_controller.dart';
import 'dart:async';

class DailyWaterController extends GetxController
    with TrackerController, WidgetsBindingObserver {
  final _provider = WaterTrackProvider();
  Rx<int> waterVolume = 0.obs;

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

    isLoading.value = false;
  }

  @override
  fetchTracksByDate(DateTime date) async {
    this.date = date;
    tracks = await _provider.fetchByDate(date);
    waterVolume.value = 0;
    tracks.map((e) {
      e = e as WaterTracker;
      waterVolume.value += e.waterVolume;
    }).toList();

    // Update last date when fetching data
    _lastDate = DateTime(date.year, date.month, date.day);

    update();
  }

  addTrack(int volume) async {
    waterVolume.value += volume;
    WaterTracker wt = WaterTracker(
        date: DateUtils.isSameDay(date, DateTime.now()) ? DateTime.now() : date,
        waterVolume: volume);
    wt = await _provider.add(wt);
    tracks.add(wt);
    update();

    _markRelevantTabToUpdate();
  }

  void _markRelevantTabToUpdate() {
    if (!RefeshTabController.instance.isProfileTabNeedToUpdate) {
      RefeshTabController.instance.toggleProfileTabUpdate();
    }
  }

  deleteTrack(WaterTracker wt) async {
    final result = await showDialog(
      context: Get.context!,
      builder: (BuildContext context) {
        return CustomConfirmationDialog(
          label: 'Xóa log nước uống',
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
          primaryButtonColor: AppColor.waterBackgroundColor,
          buttonFactorOnMaxWidth: 0.32,
          buttonsAlignment: MainAxisAlignment.spaceEvenly,
        );
      },
    );

    if (result == OkCancelResult.ok) {
      waterVolume.value -= wt.waterVolume;
      tracks.remove(wt);
      await _provider.delete(wt.id ?? 0);
      update();

      _markRelevantTabToUpdate();
    }
  }

  bool _isSameDate(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
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
      debugPrint('🔄 New day detected! Resetting water volume to 0');

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
