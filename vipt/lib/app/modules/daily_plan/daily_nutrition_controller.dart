import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/data/models/exercise_tracker.dart';
import 'package:vipt/app/data/models/local_meal_nutrition.dart';
import 'package:vipt/app/data/models/meal_nutrition.dart';
import 'package:vipt/app/data/models/meal_nutrition_tracker.dart';
import 'package:vipt/app/data/models/nutrition.dart';
import 'package:vipt/app/data/models/tracker.dart';
import 'package:vipt/app/data/others/tab_refesh_controller.dart';
import 'package:vipt/app/data/providers/exercise_track_provider.dart';
import 'package:vipt/app/data/providers/local_meal_provider.dart';
import 'package:vipt/app/data/providers/meal_nutrition_track_provider.dart';
import 'package:vipt/app/data/services/data_service.dart';
import 'package:vipt/app/data/services/api_service.dart';
import 'package:vipt/app/global_widgets/custom_confirmation_dialog.dart';
import 'package:vipt/app/modules/daily_plan/tracker_controller.dart';
import 'package:vipt/app/modules/daily_plan/widgets/change_amount_nutrition_widget.dart';
import 'dart:async';

class DailyNutritionController extends GetxController with TrackerController, WidgetsBindingObserver {
  TextEditingController searchTextController = TextEditingController();

  final _nutriTrackProvider = MealNutritionTrackProvider();
  final _exerciseTrackProvider = ExerciseTrackProvider();
  final _localMealProvider = LocalMealProvider();

  List<MealNutrition> firebaseFoodList = [];
  RxList<MealNutrition> firebaseSearchResult = <MealNutrition>[].obs;
  RxList<LocalMealNutrition> localFoodList = <LocalMealNutrition>[].obs;
  RxList<LocalMealNutrition> localSearchResult = <LocalMealNutrition>[].obs;

  RxList<Nutrition> selectedList = <Nutrition>[].obs;
  Map<String, double> selectedAmountList = {};

  Rx<int> intakeCalo = 0.obs;
  Rx<int> outtakeCalo = 0.obs;
  Rx<int> diffCalo = 0.obs;
  Rx<int> carbs = 0.obs;
  Rx<int> protein = 0.obs;
  Rx<int> fat = 0.obs;

  Rx<bool> finishFetchFoodList = false.obs;

  List<Tracker> exerciseTracks = [];

  TextEditingController firebaseListSearchController = TextEditingController();
  Rx<String> firebaseSearchText = ''.obs;
  TextEditingController localListSearchController = TextEditingController();
  Rx<String> localSearchText = ''.obs;

  Rx<int> activeTabIndex = 0.obs;

  DateTime? _lastDate;
  Timer? _dailyResetTimer;

  @override
  void onInit() async {
    super.onInit();

    // Register as observer for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    isLoading.value = true;

    await fetchLocalFoodList();

    await fetchFirebaseFoodList();

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    // Check if it's a new day compared to last stored date
    if (_lastDate == null || !_isSameDate(_lastDate!, today)) {
      // New day - reset and fetch fresh data
      diffCalo.value = intakeCalo.value - outtakeCalo.value;
      await fetchTracksByDate(today);
      _lastDate = today;
    } else {
      // Same day - just fetch existing data
      diffCalo.value = intakeCalo.value - outtakeCalo.value;
      await fetchTracksByDate(_lastDate!);
    }

    // Schedule daily reset check
    _scheduleDailyResetCheck();

    isLoading.value = false;

    initDebounceForSearching();
  }

  initDebounceForSearching() {
    firebaseListSearchController.addListener(() {
      firebaseSearchText.value = firebaseListSearchController.text;
    });

    localListSearchController.addListener(() {
      localSearchText.value = localListSearchController.text;
    });

    debounce(firebaseSearchText, (_) {
      handleSearch(
          sourceList: firebaseFoodList,
          searchList: firebaseSearchResult,
          textController: firebaseListSearchController);
    }, time: const Duration(seconds: 1));

    debounce(localSearchText, (_) {
      handleSearch(
          sourceList: localFoodList,
          searchList: localSearchResult,
          textController: localListSearchController);
    }, time: const Duration(seconds: 1));
  }

  handleSearch(
      {required List<Nutrition> sourceList,
      required List<Nutrition> searchList,
      required TextEditingController textController}) {
    searchList.clear();
    var key = textController.text.toLowerCase();
    var temptList = sourceList
        .where((food) => food.getName().toLowerCase().contains(key))
        .toList();
    searchList.addAll(temptList);
  }

  void handleSelect(Nutrition nutrition) async {
    if (nutrition is MealNutrition) {
      if (selectedList.contains(nutrition)) {
        selectedList.remove(nutrition);
        selectedAmountList.remove(nutrition.id);
      } else {
        final result = await Get.bottomSheet(
          Container(
            margin: const EdgeInsets.only(top: 64),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10.0),
                topRight: Radius.circular(10.0),
              ),
              child: ChangeAmountNutritionWidget(
                nutrition: nutrition,
              ),
            ),
          ),
          isScrollControlled: true,
        );

        if (result != null) {
          selectedList.add(nutrition);
          selectedAmountList[nutrition.id ?? ''] = result;
        }
      }
    } else if (nutrition is LocalMealNutrition) {
      if (selectedList.contains(nutrition)) {
        selectedList.remove(nutrition);
      } else {
        selectedList.add(nutrition);
      }
    }
  }

  Future<void> fetchLocalFoodList() async {
    localFoodList.value = await _localMealProvider.fetchAll();
  }

  Future<void> fetchFirebaseFoodList() async {
    if (firebaseFoodList.isNotEmpty) firebaseFoodList.clear();

    try {
      // Prefer global meal list from DataService
      if (DataService.instance.mealList.isNotEmpty) {
        var results = await Future.wait(
          DataService.instance.mealList.map((mealItem) async {
            try {
              if (mealItem.id == null || mealItem.name.isEmpty) {
                return null;
              }

              var meal = MealNutrition(meal: mealItem);
              await meal.getIngredients();
              return meal;
            } catch (e) {
              return null;
            }
          }).toList(),
        );

        firebaseFoodList = results.whereType<MealNutrition>().toList();
        finishFetchFoodList.value = true;
        return;
      }

      // Fallback: try to read user's current plan and fetch plan meals for today,
      // then fetch full meal details from server so UI can show complete info.
      try {
        final api = ApiService.instance;
        final serverPlan = await api.getMyPlan();
        int? planID;
        try {
          planID = serverPlan['planID'] is int
              ? serverPlan['planID'] as int
              : (serverPlan['plan']?['planID'] as int?);
        } catch (_) {
          planID = null;
        }

        if (planID != null) {
          // Get collections for the plan and pick the one matching today if any
          final collections = await api.getPlanMealCollections(planID: planID);
          String? chosenListID;
          DateTime today = DateUtils.dateOnly(DateTime.now());
          for (var col in collections) {
            if (col.id == null) continue;
            final colDate = col.date;
            if (DateUtils.isSameDay(DateUtils.dateOnly(colDate), today)) {
              chosenListID = col.id;
              break;
            }
          }
          // If none match today, pick earliest collection
          if (chosenListID == null && collections.isNotEmpty) {
            collections.sort((a, b) => a.date.compareTo(b.date));
            chosenListID = collections.first.id;
          }

          if (chosenListID != null) {
            final planMeals = await api.getPlanMeals(listID: chosenListID);
            // fetch meal details in parallel
            final mealFetchFutures = planMeals.map((pm) async {
              try {
                final id = pm.mealID;
                if (id.isEmpty) return null;
                final meal = await api.getMeal(id);
                final mn = MealNutrition(meal: meal);
                await mn.getIngredients();
                return mn;
              } catch (_) {
                return null;
              }
            }).toList();

            final fetched = await Future.wait(mealFetchFutures);
            firebaseFoodList = fetched.whereType<MealNutrition>().toList();
            finishFetchFoodList.value = true;
            return;
          }
        }
      } catch (_) {
        // ignore and fall through to finish with empty list
      }

      // If all else fails, mark finished so UI won't hang
      finishFetchFoodList.value = true;
    } catch (e) {
      finishFetchFoodList.value = true;
      rethrow;
    }
  }

  @override
  fetchTracksByDate(DateTime date) async {
    this.date = date;
    tracks = await _nutriTrackProvider.fetchByDate(date);
    exerciseTracks = await _exerciseTrackProvider.fetchByDate(date);

    outtakeCalo.value = 0;
    exerciseTracks.map((e) {
      e as ExerciseTracker;
      outtakeCalo.value += e.outtakeCalories;
    }).toList();

    intakeCalo.value = 0;
    diffCalo.value = 0;
    carbs.value = 0;
    protein.value = 0;
    fat.value = 0;

    tracks.map((e) {
      e as MealNutritionTracker;
      carbs.value += e.carbs;
      protein.value += e.protein;
      fat.value += e.fat;
      intakeCalo.value += e.intakeCalories;
    }).toList();

    diffCalo.value = intakeCalo.value - outtakeCalo.value;

    // Update last date when fetching data
    _lastDate = DateTime(date.year, date.month, date.day);
  }

  resetSelectedList() {
    selectedList.clear();
    selectedAmountList.clear();
  }

  handleLogTrack() async {
    for (var track in selectedList) {
      double amount = selectedAmountList[track.id ?? ''] ?? 1;

      await addTrack(
          name: track.getName(),
          intakeCalo: (track.calories * amount).toInt(),
          carbs: (track.carbs * amount).toInt(),
          fat: (track.fat * amount).toInt(),
          protein: (track.protein * amount).toInt());
    }

    resetSelectedList();

    _markRelevantTabToUpdate();

    Get.back();
  }

  void _markRelevantTabToUpdate() {
    if (!RefeshTabController.instance.isPlanTabNeedToUpdate) {
      RefeshTabController.instance.togglePlanTabUpdate();
    }

    if (!RefeshTabController.instance.isProfileTabNeedToUpdate) {
      RefeshTabController.instance.toggleProfileTabUpdate();
    }
  }

  addTrack(
      {int intakeCalo = 0,
      int carbs = 0,
      int protein = 0,
      int fat = 0,
      required String name}) async {
    this.carbs.value += carbs;
    this.protein.value += protein;
    this.fat.value += fat;
    this.intakeCalo.value += intakeCalo;
    diffCalo.value = this.intakeCalo.value - outtakeCalo.value;

    MealNutritionTracker tracker = MealNutritionTracker(
        date: DateUtils.isSameDay(date, DateTime.now()) ? DateTime.now() : date,
        name: name,
        intakeCalories: intakeCalo,
        carbs: carbs,
        protein: protein,
        fat: fat);

    tracker = await _nutriTrackProvider.add(tracker);
    tracks.add(tracker);
    update();
  }

  deleteTrack(MealNutritionTracker tracker) async {
    final result = await showDialog(
      context: Get.context!,
      builder: (BuildContext context) {
        return CustomConfirmationDialog(
          label: 'Xóa log thức ăn',
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
          primaryButtonColor: AppColor.nutriBackgroundColor,
          buttonFactorOnMaxWidth: 0.32,
          buttonsAlignment: MainAxisAlignment.spaceEvenly,
        );
      },
    );

    if (result == OkCancelResult.ok) {
      carbs.value -= tracker.carbs;
      protein.value -= tracker.protein;
      fat.value -= tracker.fat;
      intakeCalo.value -= tracker.intakeCalories;
      diffCalo.value = intakeCalo.value - outtakeCalo.value;
      tracks.remove(tracker);
      await _nutriTrackProvider.delete(tracker.id ?? 0);
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
      debugPrint('🔄 New day detected! Resetting nutrition data to 0');

      // Reset to new day
      diffCalo.value = intakeCalo.value - outtakeCalo.value;
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
