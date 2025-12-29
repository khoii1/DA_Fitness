import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vipt/app/core/utilities/utils.dart';
import 'package:vipt/app/data/models/workout.dart';
import 'package:vipt/app/data/models/meal.dart';
import 'package:vipt/app/data/models/plan_meal_collection.dart';
import 'package:vipt/app/data/models/plan_exercise_collection.dart';
import 'package:vipt/app/data/models/workout_plan.dart';
import 'package:vipt/app/data/services/api_service.dart';
import 'package:vipt/app/data/services/data_service.dart';
import 'package:vipt/app/routes/pages.dart';
import 'package:vipt/app/modules/home/home_controller.dart';
import 'package:vipt/app/modules/workout_plan/workout_plan_controller.dart';
import 'package:vipt/app/data/providers/workout_plan_provider.dart';
import 'dart:math' as math;
import 'package:vipt/app/data/providers/plan_meal_collection_provider_api.dart';
import 'package:vipt/app/data/providers/plan_exercise_collection_provider_api.dart';
import 'package:vipt/app/data/models/meal_nutrition.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Tắt log để tăng tốc độ - chỉ bật khi cần debug
const bool _enableLogging = false;
const int _maxPreviewDays = 7;
void _log(String message) {
  if (_enableLogging && kDebugMode) {
    print(message);
  }
}

class RecommendationPreviewController extends GetxController {
  final apiService = ApiService.instance;

  RxBool isLoading = true.obs;
  RxBool isCreatingPlan = false.obs;
  RxBool isExtending = false.obs;
  RxMap<String, dynamic> recommendationData = <String, dynamic>{}.obs;
  RxList<Workout> recommendedExercises = <Workout>[].obs;
  RxList<Meal> recommendedMeals = <Meal>[].obs;
  // per-day maps: dayIndex (1-based) -> list of items
  RxMap<int, List<Workout>> planExercisesByDay = <int, List<Workout>>{}.obs;
  RxMap<int, List<Meal>> planMealsByDay = <int, List<Meal>>{}.obs;
  // schedule keyed by date string 'yyyy-MM-dd'
  RxMap<String, List<Workout>> scheduleExercisesByDate =
      <String, List<Workout>>{}.obs;
  RxMap<String, List<Meal>> scheduleMealsByDate = <String, List<Meal>>{}.obs;

  /// Cache để tăng tốc độ load
  final Map<String, Workout> _workoutCache = {};
  final Map<String, Meal> _mealCache = {};

  /// Prevent automatic refresh when switching tabs — keep the last loaded preview
  /// until the user explicitly regenerates or a plan is created/deleted.
  bool _loadedOnce = false;
  int? _lastSyncedCreatedPlanId;

  String? errorMessage;

  // Keys for SharedPreferences
  static const String _recommendationDataKey = 'recommendation_data';
  static const String _recommendedExercisesKey = 'recommended_exercises';
  static const String _recommendedMealsKey = 'recommended_meals';
  static const String _userIdKey = 'recommendation_user_id';

  @override
  void onInit() {
    super.onInit();
    _restorePersistentData();
    loadRecommendation();
  }

  @override
  void onClose() {
    // Clear caches to free memory
    _workoutCache.clear();
    _mealCache.clear();
    _savePersistentData();
    super.onClose();
  }

  /// Lưu dữ liệu recommendation vào SharedPreferences để duy trì khi đăng xuất/chuyển tab
  Future<void> _savePersistentData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = DataService.currentUser?.id ?? '';

      // Chỉ lưu nếu có dữ liệu và user ID
      if (recommendationData.isNotEmpty && userId.isNotEmpty) {
        // Lưu recommendationData
        final dataJson = json.encode(recommendationData);
        await prefs.setString('${_recommendationDataKey}_$userId', dataJson);

        // Lưu danh sách exercises
        final exercisesData =
            recommendedExercises.map((e) => e.toMap()).toList();
        final exercisesJson = json.encode(exercisesData);
        await prefs.setString(
            '${_recommendedExercisesKey}_$userId', exercisesJson);

        // Lưu danh sách meals
        final mealsData = recommendedMeals.map((m) => m.toMap()).toList();
        final mealsJson = json.encode(mealsData);
        await prefs.setString('${_recommendedMealsKey}_$userId', mealsJson);

        // Lưu user ID để theo dõi
        await prefs.setString(_userIdKey, userId);

        _log('💾 Đã lưu dữ liệu recommendation persistent cho user $userId');
      }
    } catch (e) {
      _log('❌ Lỗi khi lưu dữ liệu persistent: $e');
    }
  }

  /// Khôi phục dữ liệu recommendation từ SharedPreferences
  Future<void> _restorePersistentData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = DataService.currentUser?.id ?? '';
      final savedUserId = prefs.getString(_userIdKey);

      // Chỉ khôi phục nếu user ID khớp
      if (currentUserId.isNotEmpty && currentUserId == savedUserId) {
        // Khôi phục recommendationData
        final dataJson =
            prefs.getString('${_recommendationDataKey}_$currentUserId');
        if (dataJson != null) {
          final data = json.decode(dataJson);
          recommendationData.assignAll(data);
          _log('📦 Đã khôi phục recommendationData từ persistent storage');
        }

        // Khôi phục danh sách exercises
        final exercisesJson =
            prefs.getString('${_recommendedExercisesKey}_$currentUserId');
        if (exercisesJson != null) {
          final exercisesData = json.decode(exercisesJson) as List;
          final exercises =
              exercisesData.map((e) => Workout.fromMap('', e)).toList();
          recommendedExercises.assignAll(exercises);
          // Cache exercises for faster access
          for (var exercise in exercises) {
            if (exercise.id != null) {
              _workoutCache[exercise.id!] = exercise;
            }
          }
          _log(
              '📦 Đã khôi phục ${exercises.length} exercises từ persistent storage');
        }

        // Khôi phục danh sách meals
        final mealsJson =
            prefs.getString('${_recommendedMealsKey}_$currentUserId');
        if (mealsJson != null) {
          final mealsData = json.decode(mealsJson) as List;
          final meals = mealsData.map((m) => Meal.fromMap('', m)).toList();
          recommendedMeals.assignAll(meals);
          // Cache meals for faster access
          for (var meal in meals) {
            if (meal.id != null) {
              _mealCache[meal.id!] = meal;
            }
          }
          _log('📦 Đã khôi phục ${meals.length} meals từ persistent storage');
        }
      }
    } catch (e) {
      _log('❌ Lỗi khi khôi phục dữ liệu persistent: $e');
    }
  }

  /// Load dữ liệu từ plan hiện có trên server thay vì tạo recommendation mới
  Future<void> _loadDataFromExistingPlan(WorkoutPlan plan) async {
    try {
      _log('📥 Loading data from existing plan ID: ${plan.id}');

      // Set basic plan info
      recommendationData['createdPlanID'] = plan.id;
      recommendationData['createdPlanDays'] =
          plan.endDate.difference(plan.startDate).inDays + 1;
      recommendationData['dailyGoalCalories'] = plan.dailyGoalCalories;
      recommendationData['startDate'] = plan.startDate.toIso8601String();
      recommendationData['endDate'] = plan.endDate.toIso8601String();

      // Load exercises và meals từ plan collections
      await _refreshRecommendedListsFromServerPlan(plan.id ?? 0);

      // Lưu dữ liệu vừa load vào persistent storage để tránh load lại
      await _savePersistentData();

      _log('✅ Đã load dữ liệu từ plan hiện có');
    } catch (e) {
      _log('❌ Lỗi khi load data từ existing plan: $e');
      throw e;
    }
  }

  /// Load workout từ cache hoặc API với tối ưu parallel
  Future<List<Workout>> _loadWorkoutsWithCache(List<String> workoutIds) async {
    if (workoutIds.isEmpty) return [];

    final cached = workoutIds
        .where((id) => _workoutCache.containsKey(id))
        .map((id) => _workoutCache[id]!)
        .toList();

    final uncachedIds =
        workoutIds.where((id) => !_workoutCache.containsKey(id)).toList();

    if (uncachedIds.isEmpty) return cached;

    // Load uncached workouts in parallel
    final futures = uncachedIds.map((id) async {
      try {
        return await apiService.getWorkout(id);
      } catch (e) {
        _log('⚠️ Failed to load workout $id: $e');
        return null;
      }
    });

    final results = await Future.wait(futures);
    final loaded = results.whereType<Workout>().toList();

    // Cache loaded workouts
    for (var workout in loaded) {
      if (workout.id != null) {
        _workoutCache[workout.id!] = workout;
      }
    }

    return [...cached, ...loaded];
  }

  /// Load meals từ cache hoặc API với tối ưu parallel
  Future<List<Meal>> _loadMealsWithCache(List<String> mealIds,
      {int? limit}) async {
    if (mealIds.isEmpty) return [];

    var idsToLoad = mealIds;
    if (limit != null && limit > 0) {
      idsToLoad = mealIds.take(limit).toList();
    }

    final cached = idsToLoad
        .where((id) => _mealCache.containsKey(id))
        .map((id) => _mealCache[id]!)
        .toList();

    final uncachedIds =
        idsToLoad.where((id) => !_mealCache.containsKey(id)).toList();

    if (uncachedIds.isEmpty) return cached;

    // Load uncached meals in parallel
    final futures = uncachedIds.map((id) async {
      try {
        return await apiService.getMeal(id);
      } catch (e) {
        _log('⚠️ Failed to load meal $id: $e');
        return null;
      }
    });

    final results = await Future.wait(futures);
    final loaded = results.whereType<Meal>().toList();

    // Cache loaded meals
    for (var meal in loaded) {
      if (meal.id != null) {
        _mealCache[meal.id!] = meal;
      }
    }

    return [...cached, ...loaded];
  }

  /// Xóa dữ liệu persistent của user hiện tại (sử dụng khi đăng xuất)
  Future<void> clearPersistentData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = DataService.currentUser?.id ?? '';

      if (userId.isNotEmpty) {
        await prefs.remove('${_recommendationDataKey}_$userId');
        await prefs.remove('${_recommendedExercisesKey}_$userId');
        await prefs.remove('${_recommendedMealsKey}_$userId');
        await prefs.remove(_userIdKey);

        _log('🗑️ Đã xóa dữ liệu persistent cho user $userId');
      }
    } catch (e) {
      _log('❌ Lỗi khi xóa dữ liệu persistent: $e');
    }
  }

  Future<void> loadRecommendation({bool forceGenerate = false}) async {
    try {
      isLoading.value = true;
      errorMessage = null;

      _log('📥 Loading recommendation preview...');

      // Nếu user đã có plan lưu trên profile (currentPlanID), ưu tiên load từ server để đảm bảo chính xác
      try {
        final userPlanId = DataService.currentUser?.currentPlanID;
        if (!forceGenerate && userPlanId != null) {
          recommendationData['createdPlanID'] = userPlanId;
          _log(
              'ℹ️ User has currentPlanID $userPlanId — loading plan from server');

          // Force refresh nếu chưa có meals data (case user vừa đăng ký)
          if (recommendedMeals.isEmpty) {
            _log('🔄 Force refresh because recommendedMeals is empty');
            await _refreshRecommendedListsFromServerPlan(userPlanId);
          } else {
            await _refreshRecommendedListsFromServerPlan(userPlanId);
          }

          isLoading.value = false;
          _loadedOnce = true;
          _lastSyncedCreatedPlanId = userPlanId;
          return;
        }
      } catch (e) {
        _log('⚠️ Error while checking user currentPlanID: $e');
      }

      // Nếu không force generate và đã có dữ liệu persistent, ưu tiên sử dụng dữ liệu đó
      if (!forceGenerate &&
          recommendationData.isNotEmpty &&
          (recommendedExercises.isNotEmpty || recommendedMeals.isNotEmpty)) {
        _log('ℹ️ Using persistent recommendation data, skipping server load');
        isLoading.value = false;
        return;
      }

      // Avoid reloading automatically if we've already loaded once and caller
      // didn't ask for a forced generation. If there is an existing created
      // plan, only refresh from the server when we haven't already synced that
      // specific plan (prevents changes on simple tab switch).
      if (!forceGenerate) {
        final createdPlanId = recommendationData['createdPlanID'] as int?;
        if (createdPlanId != null) {
          if (_loadedOnce && _lastSyncedCreatedPlanId == createdPlanId) {
            _log(
                'ℹ️ Already synced createdPlanID $createdPlanId, skipping refresh');
            isLoading.value = false;
            return;
          }
          _log(
              'ℹ️ Existing createdPlanID found ($createdPlanId), refreshing from server plan');
          await _refreshRecommendedListsFromServerPlan(createdPlanId);
          isLoading.value = false;
          _loadedOnce = true;
          _lastSyncedCreatedPlanId = createdPlanId;
          return;
        }

        if (_loadedOnce && recommendationData.isNotEmpty) {
          _log(
              'ℹ️ Preview already loaded and not forcing regenerate — keeping cached data');
          isLoading.value = false;
          return;
        }
      }

      // If we get here, either forceGenerate==true or we haven't loaded yet.
      Map<String, dynamic> data;

      if (!forceGenerate) {
        // Trước khi tạo recommendation mới, kiểm tra xem user đã có plan trên server chưa
        try {
          final userId = DataService.currentUser?.id ?? '';
          if (userId.isNotEmpty) {
            final planProvider = WorkoutPlanProvider();
            final WorkoutPlan? existingPlan =
                await planProvider.fetchByUserID(userId);
            if (existingPlan != null) {
              // User đã có plan, load dữ liệu từ plan thay vì tạo mới
              _log(
                  'ℹ️ User đã có plan trên server (ID: ${existingPlan.id}), load dữ liệu từ plan');
              await _loadDataFromExistingPlan(existingPlan);
              isLoading.value = false;
              _loadedOnce = true;
              _lastSyncedCreatedPlanId = existingPlan.id;
              return;
            }
          }
        } catch (e) {
          _log('⚠️ Lỗi khi kiểm tra plan hiện có: $e');
          // Tiếp tục với logic cũ nếu có lỗi
        }
      }

      data = forceGenerate
          ? await apiService.generatePlanRecommendation()
          : await apiService.getPlanPreview();
      _log('📦 Recommendation data received: ${data.keys.toList()}');

      recommendationData.assignAll(data);
      _loadedOnce = true;

      // If a workout plan already exists locally for the user, show createdPlanDays
      try {
        final userId = DataService.currentUser?.id ?? '';
        if (userId.isNotEmpty) {
          final planProvider = WorkoutPlanProvider();
          final WorkoutPlan? existingPlan =
              await planProvider.fetchByUserID(userId);
          if (existingPlan != null) {
            final days =
                existingPlan.endDate.difference(existingPlan.startDate).inDays +
                    1;
            recommendationData['createdPlanDays'] = days;
            recommendationData['createdPlanID'] = existingPlan.id;
          }
        }
      } catch (e) {
        _log('⚠️ Error checking existing local plan: $e');
      }

      // If there is already a created plan, refresh preview lists to reflect the
      // actual plan contents (so the "Bữa ăn được đề xuất" / "Bài tập được đề xuất"
      // show the items used in the user's plan rather than the generic preview).
      try {
        final createdPlanId = recommendationData['createdPlanID'] as int?;
        if (createdPlanId != null) {
          await _refreshRecommendedListsFromServerPlan(createdPlanId);
        }
      } catch (e) {
        _log('⚠️ Failed to refresh preview from existing plan: $e');
      }

      // Load exercises
      if (data['exercises'] != null && (data['exercises'] as List).isNotEmpty) {
        final exercisesList = (data['exercises'] as List).map((e) {
          final map =
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e);
          final workout = Workout.fromMap(map['_id'] ?? map['id'] ?? '', map);
          // Cache workout for faster future access
          if (workout.id != null) {
            _workoutCache[workout.id!] = workout;
          }
          return workout;
        }).toList();
        recommendedExercises.assignAll(exercisesList);
        _log('✅ Loaded ${exercisesList.length} exercises');
      }

      // Load meals
      if (data['meals'] != null && (data['meals'] as List).isNotEmpty) {
        final mealsList = (data['meals'] as List).map((e) {
          final map =
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e);
          final meal = Meal.fromMap(map['_id'] ?? map['id'] ?? '', map);
          // Cache meal for faster future access
          if (meal.id != null) {
            _mealCache[meal.id!] = meal;
          }
          return meal;
        }).toList();
        recommendedMeals.assignAll(mealsList);
        _log('✅ Loaded ${mealsList.length} meals');
      }

      isLoading.value = false;
    } catch (e) {
      errorMessage = 'Không thể tải đề xuất: ${e.toString()}';
      isLoading.value = false;
      _log('❌ Lỗi khi load recommendation: $e');
    }
  }

  Future<void> regenerateRecommendation() async {
    // Force server to generate a fresh recommendation
    await loadRecommendation(forceGenerate: true);
  }

  // --- Helpers for building meal/exercise pools for plan creation ---
  /// Build a pool of meal IDs for [days] x [mealsPerDay], avoiding same meal on consecutive days when possible.
  List<String> _buildMealSchedulePool({
    required int days,
    required int mealsPerDay,
    required List<String> availableMealIDs,
  }) {
    if (availableMealIDs.isEmpty) return [];

    final rnd = math.Random();
    List<List<String>> schedule = List.generate(days, (_) => <String>[]);

    for (int d = 0; d < days; d++) {
      final prevDay = d > 0 ? schedule[d - 1] : <String>[];
      final dayPool = List<String>.from(availableMealIDs)..shuffle(rnd);
      int idx = 0;
      while (schedule[d].length < mealsPerDay && idx < dayPool.length) {
        final candidate = dayPool[idx++];
        if (!prevDay.contains(candidate) && !schedule[d].contains(candidate)) {
          schedule[d].add(candidate);
        }
      }
      // fallback: if still not enough, allow repeats within day but avoid duplicates in same day
      idx = 0;
      while (schedule[d].length < mealsPerDay && idx < dayPool.length) {
        final candidate = dayPool[idx++];
        if (!schedule[d].contains(candidate)) schedule[d].add(candidate);
      }
    }

    // Flatten and return unique pool (server may accept pool of possible meals)
    final flat = schedule.expand((e) => e).toList();
    return flat.toSet().toList();
  }

  /// Build exercise pool (prefer variety). Returns a list of exercise IDs.
  List<String> _buildExercisePool({
    required int days,
    required int exercisesPerDay,
    required List<String> availableExerciseIDs,
  }) {
    if (availableExerciseIDs.isEmpty) return [];
    final rnd = math.Random();
    final needed =
        math.min(availableExerciseIDs.length, days * exercisesPerDay);
    final shuffled = List<String>.from(availableExerciseIDs)..shuffle(rnd);
    return shuffled.take(needed).toList();
  }

  /// Delete plan-related collections for a given planID (meals and exercises).
  Future<void> _deleteExistingPlanCollections(int planID) async {
    try {
      await apiService.deletePlanMealCollectionsByPlanID(planID);
    } catch (e) {
      _log('⚠️ deletePlanMealCollections failed: $e');
    }
    try {
      await apiService.deletePlanExerciseCollectionsByPlanID(planID);
    } catch (e) {
      _log('⚠️ deletePlanExerciseCollections failed: $e');
    }
  }

  /// Delete any existing plan (collections) and create a fresh 7-day plan using recommended pools.
  /// Each day will have randomly 3-5 exercises (handled by backend).
  Future<void> deleteAndCreateNew7DayPlan(
      {int mealsPerDay = 3,
      int exercisesPerDay = 4, // Average of 3-5 exercises per day
      bool navigateHome = true}) async {
    int? existingPlanId;
    final Set<String> prevPlanMealIDs = {};
    final Set<String> prevPlanExerciseIDs = {};

    try {
      isCreatingPlan.value = true;
      UIUtils.showLoadingDialog();

      // Ensure we have a freshly generated recommendation from server so newly
      // added exercises/meals are included when rebuilding the plan.
      try {
        await loadRecommendation(forceGenerate: true);
      } catch (e) {
        _log('⚠️ Failed to refresh recommendations before creating plan: $e');
      }

      existingPlanId = recommendationData['createdPlanID'] as int?;
      if (existingPlanId == null) {
        // try fetch from server
        try {
          final serverPlan = await apiService.getMyPlan();
          if (serverPlan['planID'] != null) {
            existingPlanId = serverPlan['planID'] as int;
            recommendationData['createdPlanID'] = existingPlanId;
          }
        } catch (_) {}
      }

      // Try to fetch previous plan details so we can avoid reusing the exact same items.
      try {
        final serverPlan = await apiService.getMyPlan();
        // various shapes: recommendedExerciseIDs, exercises, plan.exercises, etc.
        try {
          final prevExercises = serverPlan['recommendedExerciseIDs'] ??
              serverPlan['exerciseIDs'] ??
              serverPlan['exercises'] ??
              serverPlan['plan']?['recommendedExerciseIDs'] ??
              serverPlan['plan']?['exerciseIDs'];
          if (prevExercises is List) {
            for (var id in prevExercises) {
              final s = id?.toString() ?? '';
              if (s.isNotEmpty) prevPlanExerciseIDs.add(s);
            }
          }
        } catch (_) {}
        try {
          final prevMeals = serverPlan['recommendedMealIDs'] ??
              serverPlan['mealIDs'] ??
              serverPlan['meals'] ??
              serverPlan['plan']?['recommendedMealIDs'] ??
              serverPlan['plan']?['mealIDs'];
          if (prevMeals is List) {
            for (var id in prevMeals) {
              final s = id?.toString() ?? '';
              if (s.isNotEmpty) prevPlanMealIDs.add(s);
            }
          }
        } catch (_) {}
      } catch (_) {}

      if (existingPlanId != null) {
        await _deleteExistingPlanCollections(existingPlanId);
      }

      // Start with recommended items, but if pool is small or doesn't include
      // newer library items, augment with full workout/meal library so we can
      // randomly mix across everything.
      final List<String> availableMealIDs = recommendedMeals
          .map((m) => m.id ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      final List<String> availableExerciseIDs = recommendedExercises
          .map((e) => e.id ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      // If recommended pool is small, try to augment from full library to
      // increase randomness and include newly added items (e.g., hít đất).
      try {
        // target needed items ~ days * average exercises per day (7 * 4)
        final int neededExerciseCount = 7 * 4;
        if (availableExerciseIDs.length < neededExerciseCount) {
          _log('ℹ️ Augmenting exercise pool from full library');
          final allWorkouts = await apiService.getWorkouts();
          for (var w in allWorkouts) {
            final id = w.id ?? '';
            if (id.isNotEmpty && !availableExerciseIDs.contains(id)) {
              availableExerciseIDs.add(id);
            }
          }
        }

        final int neededMealCount = 7 * mealsPerDay;
        if (availableMealIDs.length < neededMealCount) {
          _log('ℹ️ Augmenting meal pool from full library');
          final allMeals = await apiService.getMeals();
          for (var m in allMeals) {
            final id = m.id ?? '';
            if (id.isNotEmpty && !availableMealIDs.contains(id)) {
              availableMealIDs.add(id);
            }
          }
        }
      } catch (e) {
        _log('⚠️ Failed to augment pools from library: $e');
      }

      // Prefer items that were NOT in previous plan to create a fresh version.
      final freshMealCandidates = availableMealIDs
          .where((id) => !prevPlanMealIDs.contains(id))
          .toList();
      final freshExerciseCandidates = availableExerciseIDs
          .where((id) => !prevPlanExerciseIDs.contains(id))
          .toList();

      // If there are enough fresh candidates, use them; otherwise fallback to full pool.
      final poolMealSource = freshMealCandidates.length >= (mealsPerDay)
          ? freshMealCandidates
          : availableMealIDs;
      final poolExerciseSource =
          freshExerciseCandidates.length >= (exercisesPerDay)
              ? freshExerciseCandidates
              : availableExerciseIDs;

      final mealPool = _buildMealSchedulePool(
          days: 7, mealsPerDay: mealsPerDay, availableMealIDs: poolMealSource);
      final exercisePool = _buildExercisePool(
          days: 7,
          exercisesPerDay: exercisesPerDay,
          availableExerciseIDs: poolExerciseSource);

      // Persist the chosen pools into recommendationData so preview UI can use them
      // immediately (before server responds).
      recommendationData['recommendedMealIDs'] =
          mealPool.map((e) => e.toString()).toList();
      recommendationData['recommendedExerciseIDs'] =
          exercisePool.map((e) => e.toString()).toList();

      // Populate `recommendedMeals` / `recommendedExercises` immediately from
      // the chosen pools so the preview cards reflect the plan about to be
      // created (this makes the outside lists match the plan even before server
      // finishes).
      try {
        final List<Meal> quickMeals = [];
        final uniqueMealIDs = mealPool.toSet().toList();
        for (var id in uniqueMealIDs) {
          if (id.isEmpty) continue;
          try {
            final m = await apiService.getMeal(id);
            quickMeals.add(m);
          } catch (e) {
            _log('⚠️ quick fetch meal $id failed: $e');
          }
        }
        if (quickMeals.isNotEmpty) recommendedMeals.assignAll(quickMeals);
      } catch (e) {
        _log('⚠️ populate recommendedMeals failed: $e');
      }

      try {
        final List<Workout> quickExercises = [];
        final uniqueExIDs = exercisePool.toSet().toList();
        for (var id in uniqueExIDs) {
          if (id.isEmpty) continue;
          try {
            final w = await apiService.getWorkout(id);
            quickExercises.add(w);
          } catch (e) {
            _log('⚠️ quick fetch workout $id failed: $e');
          }
        }
        if (quickExercises.isNotEmpty)
          recommendedExercises.assignAll(quickExercises);
      } catch (e) {
        _log('⚠️ populate recommendedExercises failed: $e');
      }

      // Create base plan first to obtain planID
      final created = await apiService.createPlanFromRecommendation(
        planLengthInDays: 7,
        dailyGoalCalories: recommendationData['dailyGoalCalories'] ?? 0,
        dailyIntakeCalories: recommendationData['dailyIntakeCalories'] ?? 0,
        dailyOuttakeCalories: recommendationData['dailyOuttakeCalories'] ?? 0,
        recommendedExerciseIDs: exercisePool,
        recommendedMealIDs: mealPool,
        startDate: DateTime.now(),
        endDate: DateTime.now().add(Duration(days: 6)),
      );

      try {
        final planIdTop = created['planID'];
        if (planIdTop != null) {
          recommendationData['createdPlanID'] = planIdTop;
        } else {
          final plan = created['plan'];
          if (plan != null && plan['planID'] != null) {
            recommendationData['createdPlanID'] = plan['planID'];
          }
        }
        recommendationData['createdPlanDays'] = 7;
      } catch (_) {}

      // Notify WorkoutPlanController to reload plan data so "Luyện tập" / "Ăn uống" syncs
      try {
        final planController = Get.find<WorkoutPlanController>();
        // Try to refresh currentWorkoutPlan from server/provider
        try {
          final wp = await WorkoutPlanProvider()
              .fetchByUserID(DataService.currentUser?.id ?? '');
          if (wp != null) {
            planController.currentWorkoutPlan.value = wp;
          }
        } catch (_) {}

        await planController.refreshAllData();
      } catch (_) {}

      // TEMPORARILY DISABLE: Let backend handle all collections with random exercises
      // After plan creation, backend already created collections with random exercises
      final int? newPlanId = recommendationData['createdPlanID'] as int?;
      if (newPlanId != null) {
        // Just refresh recommended lists from server plan - no need to recreate collections
        if (false) { // TEMPORARILY DISABLE collection recreation
        // DISABLED: Build MealNutrition list (with calories) for selection.
        // Use availableMealIDs (augmented pool) rather than only recommendedMeals
        final List<MealNutrition> mealNutritions = [];
        final uniqueMealIDsForNut = availableMealIDs.toSet().toList();
        for (var mid in uniqueMealIDsForNut) {
          if (mid.isEmpty) continue;
          try {
            Meal meal;
            // Try to use cached meal if present
            if (_mealCache.containsKey(mid)) {
              meal = _mealCache[mid]!;
            } else {
              meal = await apiService.getMeal(mid);
              if (meal.id != null) _mealCache[meal.id!] = meal;
            }
            final mn = MealNutrition(meal: meal);
            await mn.getIngredients();
            mealNutritions.add(mn);
          } catch (e) {
            _log('⚠️ Failed to build MealNutrition for $mid: $e');
          }
        }

        // Determine daily target calories (fallback to 740)
        final int targetDaily =
            (recommendationData['dailyGoalCalories'] ?? 740).toInt();

        final mealProvider = PlanMealCollectionProvider();
        final exerciseProvider = PlanExerciseCollectionProvider();

        // Keep previous day selections to avoid consecutive duplicates
        List<String> prevDayMeals = [];
        // Track globally used meals across the whole plan to avoid repeats when possible
        final Set<String> usedMealIDs = {};
        // Track all meal combinations used in previous days to ensure each day has unique 3-meal combination
        final Set<String> usedMealCombinations = {};
        List<String> prevDayExercises = [];

        for (int d = 0; d < 7; d++) {
          final date = DateTime.now().add(Duration(days: d));

          // Select meals for the day with unique 3-meal combination
          List<String> dayMealIDs = [];

          // Shuffle available meals for randomness
          final shuffledMeals = List<MealNutrition>.from(mealNutritions)..shuffle();

          // Try to find a unique combination
          bool foundUniqueCombination = false;

          // First pass: try to find 3 meals that form a unique combination
          for (int i = 0; i < shuffledMeals.length - 2 && !foundUniqueCombination; i++) {
            for (int j = i + 1; j < shuffledMeals.length - 1 && !foundUniqueCombination; j++) {
              for (int k = j + 1; k < shuffledMeals.length && !foundUniqueCombination; k++) {
                final candidateIds = [
                  shuffledMeals[i].meal.id ?? '',
                  shuffledMeals[j].meal.id ?? '',
                  shuffledMeals[k].meal.id ?? ''
                ].where((id) => id.isNotEmpty).toList();

                if (candidateIds.length == 3) {
                  candidateIds.sort();
                  final combinationKey = candidateIds.join(',');
                  if (!usedMealCombinations.contains(combinationKey)) {
                    dayMealIDs = candidateIds;
                    usedMealCombinations.add(combinationKey);
                    foundUniqueCombination = true;
                  }
                }
              }
            }
          }

          // If still not found unique combination, use fallback: pick 3 different meals
          if (!foundUniqueCombination) {
            final availableMeals = shuffledMeals.where((mn) => mn.meal.id?.isNotEmpty ?? false).toList();

            if (availableMeals.length >= 3) {
              // Take first 3 meals, but shuffle them to ensure variety
              final fallbackMeals = availableMeals.take(3).toList()..shuffle();
              dayMealIDs = fallbackMeals.map((mn) => mn.meal.id!).toList();

              // Add to combinations to avoid future duplicates if possible
              final sortedIds = List<String>.from(dayMealIDs)..sort();
              final combinationKey = sortedIds.join(',');
              if (!usedMealCombinations.contains(combinationKey)) {
                usedMealCombinations.add(combinationKey);
              }
            } else if (availableMeals.length >= mealsPerDay) {
              // If we have at least mealsPerDay meals, use them
              dayMealIDs = availableMeals.take(mealsPerDay).map((mn) => mn.meal.id!).toList();
            } else {
              // Emergency fallback: use all available meals (may have duplicates across days)
              dayMealIDs = availableMeals.map((mn) => mn.meal.id!).toList();
              _log('⚠️ Warning: Not enough unique meals available for day ${d + 1}');
            }
          }

          // If still less than mealsPerDay (rare), fill with random from pool
          if (dayMealIDs.length < mealsPerDay && mealNutritions.isNotEmpty) {
            for (var mn in mealNutritions) {
              final id = mn.meal.id ?? '';
              if (!dayMealIDs.contains(id)) {
                dayMealIDs.add(id);
              }
              if (dayMealIDs.length >= mealsPerDay) break;
            }
          }

          // Log selection for debugging
          _log(
              '🔍 Day ${d + 1} selection: meals=${dayMealIDs.length} ids=$dayMealIDs');

          // If still not enough meals selected, try to fill from availableMealIDs avoiding usedMealIDs
          if (dayMealIDs.length < mealsPerDay && availableMealIDs.isNotEmpty) {
            // First pass: try to fill with meals that haven't been used in other days
            for (var id in availableMealIDs) {
              if (dayMealIDs.length >= mealsPerDay) break;
              if (usedMealIDs.contains(id)) continue;
              if (!dayMealIDs.contains(id)) dayMealIDs.add(id);
            }

            // Second pass: if still not enough, allow meals that may have been used before but not in this day
            if (dayMealIDs.length < mealsPerDay) {
              for (var id in availableMealIDs) {
                if (dayMealIDs.length >= mealsPerDay) break;
                if (!dayMealIDs.contains(id)) dayMealIDs.add(id);
              }
            }

            // Final fallback: allow duplicates within day (should be rare)
            int idxFill = 0;
            while (dayMealIDs.length < mealsPerDay &&
                availableMealIDs.isNotEmpty) {
              dayMealIDs
                  .add(availableMealIDs[idxFill % availableMealIDs.length]);
              idxFill++;
            }

            _log(
                '🔁 Day ${d + 1} after fallback meals=${dayMealIDs.length} ids=$dayMealIDs');
          }

          // Log the selected combination for debugging
          if (dayMealIDs.length == mealsPerDay) {
            final sortedIds = List<String>.from(dayMealIDs)..sort();
            final combinationKey = sortedIds.join(',');
            _log('🔍 Day ${d + 1} final meals: ${dayMealIDs.length} ids=$dayMealIDs (combination: $combinationKey)');
          }

          // Create meal collection for this day, then ensure PlanMeal entries exist
          try {
            final collection = await mealProvider.createWithMeals(
                date: date,
                planID: newPlanId,
                mealRatio: 1.0,
                mealIDs: dayMealIDs);
            // If server didn't create PlanMeal entries automatically, create them explicitly
            if (collection.id != null) {
              for (var mealId in dayMealIDs) {
                try {
                  await apiService.createPlanMeal(
                      listID: collection.id!, mealID: mealId);
                } catch (e) {
                  _log(
                      '⚠️ createPlanMeal failed for list ${collection.id} meal $mealId: $e');
                }
              }
            }
          } catch (e) {
            _log('⚠️ createWithMeals failed for date $date: $e');
          }

          // Mark selected meals as used globally to reduce repeats across days
          for (var mId in dayMealIDs) {
            if (mId.isNotEmpty) usedMealIDs.add(mId);
          }

          // Select exercises for the day by sampling randomly from the generated
          // exercisePool. Each day gets 3-5 exercises randomly (matching backend logic).
          List<String> dayExerciseIDs = [];

          if (exercisePool.isNotEmpty) {
            final rnd = math.Random();
            final shuffled = List<String>.from(exercisePool)..shuffle(rnd);

            // Randomly select 3-5 exercises per day (same as backend)
            final int randomExercisesPerDay = 3 + rnd.nextInt(3); // 3, 4, or 5

            // First pass: pick candidates not used in previous day
            int idx = 0;
            while (dayExerciseIDs.length < randomExercisesPerDay &&
                idx < shuffled.length) {
              final candidate = shuffled[idx++];
              if (!dayExerciseIDs.contains(candidate) &&
                  !prevDayExercises.contains(candidate)) {
                dayExerciseIDs.add(candidate);
              }
            }

            // Second pass: allow using items even if used in previous day (to fill slots)
            idx = 0;
            while (dayExerciseIDs.length < randomExercisesPerDay &&
                idx < shuffled.length) {
              final candidate = shuffled[idx++];
              if (!dayExerciseIDs.contains(candidate))
                dayExerciseIDs.add(candidate);
            }

            // Final fallback: if pool smaller than needed, repeat items (avoid duplicates within day)
            int seq = 0;
            while (dayExerciseIDs.length < randomExercisesPerDay &&
                exercisePool.isNotEmpty) {
              final cand = exercisePool[seq % exercisePool.length];
              if (!dayExerciseIDs.contains(cand)) dayExerciseIDs.add(cand);
              seq++;
              if (seq > exercisePool.length * 3) break;
            }
          }

          _log(
              '🔍 Day ${d + 1} selection: exercises=${dayExerciseIDs.length} ids=$dayExerciseIDs');

          // Create exercise collection for this day with defaults, then ensure plan-exercise links exist
          try {
            final collection = await exerciseProvider.createWithExercises(
              date: date,
              planID: newPlanId,
              round: 1,
              exerciseTime: 45,
              numOfWorkoutPerRound: dayExerciseIDs.length,
              exerciseIDs: dayExerciseIDs,
            );
            if (collection.id != null) {
              for (var exId in dayExerciseIDs) {
                try {
                  await apiService.createPlanExercise(
                      listID: collection.id!, exerciseID: exId);
                } catch (e) {
                  _log(
                      '⚠️ createPlanExercise failed for list ${collection.id} ex $exId: $e');
                }
              }
            }
          } catch (e) {
            _log('⚠️ createWithExercises failed for date $date: $e');
          }

          prevDayMeals = List<String>.from(dayMealIDs);
          prevDayExercises = List<String>.from(dayExerciseIDs);
        }
        // Refresh recommended lists shown in preview from server plan so UI
        // reflects the actual created plan's items (meals & exercises).
        try {
          await _refreshRecommendedListsFromServerPlan(newPlanId);
          // Also refresh local caches so other screens read updated data.
          await DataService.instance.loadMealList();
          await DataService.instance.loadWorkoutList();
        } catch (e) {
          _log('⚠️ _refreshRecommendedListsFromServerPlan failed: $e');
        }
        } // END TEMPORARILY DISABLED

        // Just refresh recommended lists from server plan
        try {
          await _refreshRecommendedListsFromServerPlan(newPlanId);
          // Also refresh local caches so other screens read updated data.
          await DataService.instance.loadMealList();
          await DataService.instance.loadWorkoutList();
        } catch (e) {
          _log('⚠️ _refreshRecommendedListsFromServerPlan failed: $e');
        }
      }

      DataService.instance.startListeningToStreams();
      DataService.instance.startListeningToUserCollections();

      // Lưu dữ liệu mới vào persistent storage sau khi tạo plan thành công
      await _savePersistentData();

      UIUtils.hideLoadingDialog();
      isCreatingPlan.value = false;
      Get.snackbar('Thành công', 'Đã xóa và tạo lộ trình 7 ngày',
          snackPosition: SnackPosition.BOTTOM);
      if (navigateHome) {
        Get.offAllNamed(Routes.home);
      } else {
        // keep user on preview screen; recommendationData already updated above
        // refresh preview lists to reflect created plan
        try {
          final createdPlanId = recommendationData['createdPlanID'] as int?;
          if (createdPlanId != null) {
            await _refreshRecommendedListsFromServerPlan(createdPlanId);
            await DataService.instance.loadMealList();
            await DataService.instance.loadWorkoutList();
            try {
              final planController = Get.find<WorkoutPlanController>();
              await planController.refreshAllData();
            } catch (_) {}
          }
        } catch (_) {}
      }
    } catch (e) {
      UIUtils.hideLoadingDialog();
      isCreatingPlan.value = false;
      Get.snackbar('Lỗi', 'Không thể xóa/tạo lộ trình: ${e.toString()}',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
      _log('❌ deleteAndCreateNew7DayPlan error: $e');
    }
  }

  /// Tạo 7 ngày plan chạy ẩn (không hiển thị UI) - sử dụng sau khi đăng ký tài khoản
  Future<bool> create7DayPlanSilently() async {
    try {
      // Kiểm tra xem đã có recommendation data chưa
      if (recommendationData.isEmpty) {
        // Tạo recommendation data từ user profile
        await loadRecommendation();
      }

      final data = Map<String, dynamic>.from(recommendationData);

      // Create plan for next 7 days only
      final created = await apiService.createPlanFromRecommendation(
        planLengthInDays: 7,
        dailyGoalCalories: data['dailyGoalCalories'] as num,
        dailyIntakeCalories: data['dailyIntakeCalories'] as num,
        dailyOuttakeCalories: data['dailyOuttakeCalories'] as num,
        recommendedExerciseIDs: (data['recommendedExerciseIDs'] as List)
            .map((e) => e.toString())
            .toList(),
        recommendedMealIDs: (data['recommendedMealIDs'] as List)
            .map((e) => e.toString())
            .toList(),
        startDate: data['startDate'] != null
            ? DateTime.parse(data['startDate'])
            : DateTime.now(),
        endDate:
            data['endDate'] != null ? DateTime.parse(data['endDate']) : null,
      );

      // Save created planID for later extend operations
      try {
        final planIdTop = created['planID'];
        if (planIdTop != null) {
          recommendationData['createdPlanID'] = planIdTop;
        } else {
          final plan = created['plan'];
          if (plan != null && plan['planID'] != null) {
            recommendationData['createdPlanID'] = plan['planID'];
          }
        }
        final cDays = created['createdDays'] ?? created['createdDays'];
        recommendationData['createdPlanDays'] = cDays ?? 7;
        _log('📝 Created plan with ID: ${recommendationData['createdPlanID']}, days: $cDays');
      } catch (_) {}

      // Start listening to real-time streams (data will be updated automatically)
      DataService.instance.startListeningToStreams();
      DataService.instance.startListeningToUserCollections();

      // Refresh preview lists to match created plan (and refresh local caches)
      try {
        final createdPlanId = recommendationData['createdPlanID'] as int?;
        _log('🔄 Refreshing data for plan ID: $createdPlanId');
        if (createdPlanId != null) {
          await _refreshRecommendedListsFromServerPlan(createdPlanId);
          await DataService.instance.loadMealList();
          await DataService.instance.loadWorkoutList();
          try {
            final planController = Get.find<WorkoutPlanController>();
            try {
              final wp = await WorkoutPlanProvider()
                  .fetchByUserID(DataService.currentUser?.id ?? '');
              if (wp != null) planController.currentWorkoutPlan.value = wp;
            } catch (_) {}
            await planController.refreshAllData();
          } catch (_) {}
        }
      } catch (e) {
        _log('⚠️ Failed to refresh preview lists after silent create: $e');
      }

      // Update user profile với currentPlanID mới
      try {
        final createdPlanId = recommendationData['createdPlanID'] as int?;
        if (createdPlanId != null && DataService.currentUser?.id != null) {
          final userId = DataService.currentUser!.id!;
          final updateResult = await apiService.updateUser(userId, {
            'currentPlanID': createdPlanId,
          });

          if (updateResult['success'] == true) {
            // Update local user data
            if (DataService.currentUser != null) {
              DataService.currentUser!.currentPlanID = createdPlanId;
            }
            _log('✅ Updated user profile with currentPlanID: $createdPlanId');
          } else {
            _log('⚠️ Failed to update user profile with currentPlanID');
          }
        }
      } catch (e) {
        _log('⚠️ Error updating user profile with currentPlanID: $e');
      }

      // Lưu dữ liệu mới vào persistent storage sau khi tạo plan thành công
      await _savePersistentData();

      _log('✅ Tạo 7 ngày plan thành công (chạy ẩn)');
      return true;
    } catch (e) {
      _log('❌ Lỗi khi tạo 7 ngày plan (chạy ẩn): $e');
      return false;
    }
  }

  Future<void> confirmAndCreatePlan() async {
    try {
      isCreatingPlan.value = true;
      UIUtils.showLoadingDialog();

      final data = Map<String, dynamic>.from(recommendationData);

      // Create plan for next 7 days only
      final created = await apiService.createPlanFromRecommendation(
        planLengthInDays: 7,
        dailyGoalCalories: data['dailyGoalCalories'] as num,
        dailyIntakeCalories: data['dailyIntakeCalories'] as num,
        dailyOuttakeCalories: data['dailyOuttakeCalories'] as num,
        recommendedExerciseIDs: (data['recommendedExerciseIDs'] as List)
            .map((e) => e.toString())
            .toList(),
        recommendedMealIDs: (data['recommendedMealIDs'] as List)
            .map((e) => e.toString())
            .toList(),
        startDate: data['startDate'] != null
            ? DateTime.parse(data['startDate'])
            : DateTime.now(),
        endDate:
            data['endDate'] != null ? DateTime.parse(data['endDate']) : null,
      );

      // Save created planID for later extend operations (if present)
      try {
        // prefer top-level planID from server response, fallback to nested plan object
        final planIdTop = created['planID'];
        if (planIdTop != null) {
          recommendationData['createdPlanID'] = planIdTop;
        } else {
          final plan = created['plan'];
          if (plan != null && plan['planID'] != null) {
            recommendationData['createdPlanID'] = plan['planID'];
          }
        }
        // createdDays
        final cDays = created['createdDays'] ?? created['createdDays'];
        recommendationData['createdPlanDays'] = cDays ?? 7;
      } catch (_) {}

      // Start listening to real-time streams (data will be updated automatically)
      DataService.instance.startListeningToStreams();
      DataService.instance.startListeningToUserCollections();

      // After creating explicitly from preview data, ensure preview lists match
      // created plan (and refresh local caches)
      try {
        final createdPlanId = recommendationData['createdPlanID'] as int?;
        if (createdPlanId != null) {
          await _refreshRecommendedListsFromServerPlan(createdPlanId);
          await DataService.instance.loadMealList();
          await DataService.instance.loadWorkoutList();
          try {
            final planController = Get.find<WorkoutPlanController>();
            try {
              final wp = await WorkoutPlanProvider()
                  .fetchByUserID(DataService.currentUser?.id ?? '');
              if (wp != null) planController.currentWorkoutPlan.value = wp;
            } catch (_) {}
            await planController.refreshAllData();
          } catch (_) {}
        }
      } catch (e) {
        _log('⚠️ Failed to refresh preview lists after confirm create: $e');
      }

      UIUtils.hideLoadingDialog();
      isCreatingPlan.value = false;

      // Navigate to home
      Get.offAllNamed(Routes.home);
    } catch (e) {
      UIUtils.hideLoadingDialog();
      isCreatingPlan.value = false;

      Get.snackbar(
        'Lỗi',
        'Không thể tạo lộ trình: ${e.toString()}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );

      _log('❌ Lỗi khi tạo plan: $e');
    }
  }

  /// Quick create plan: delete existing and create new plan immediately
  /// If [forceDays] provided, use it as planLengthInDays; otherwise use recommendationData
  Future<void> quickCreateAndReplacePlan({int? forceDays}) async {
    try {
      isCreatingPlan.value = true;

      UIUtils.showLoadingDialog();

      final data = Map<String, dynamic>.from(recommendationData);

      // Force plan to 7 days by default unless caller explicitly provides forceDays
      final planLength = forceDays ?? 7;

      final created = await apiService.createPlanFromRecommendation(
        planLengthInDays: planLength,
        dailyGoalCalories: data['dailyGoalCalories'] as num,
        dailyIntakeCalories: data['dailyIntakeCalories'] as num,
        dailyOuttakeCalories: data['dailyOuttakeCalories'] as num,
        recommendedExerciseIDs: (data['recommendedExerciseIDs'] as List)
            .map((e) => e.toString())
            .toList(),
        recommendedMealIDs: (data['recommendedMealIDs'] as List)
            .map((e) => e.toString())
            .toList(),
        startDate: data['startDate'] != null
            ? DateTime.parse(data['startDate'])
            : DateTime.now(),
        endDate:
            data['endDate'] != null ? DateTime.parse(data['endDate']) : null,
      );

      // Save created planID for later extend operations (if present)
      try {
        final plan = created['plan'];
        if (plan != null && plan['planID'] != null) {
          recommendationData['createdPlanID'] = plan['planID'];
          // record how many days were actually created (we create 7 by default)
          recommendationData['createdPlanDays'] = planLength;
        }
      } catch (_) {}

      // Start listening to real-time streams (data will be updated automatically)
      DataService.instance.startListeningToStreams();
      DataService.instance.startListeningToUserCollections();

      // After creation, refresh preview lists from server so the outside
      // recommendation sections show the new meals/exercises, and notify
      // the WorkoutPlanController to reload its data so "Luyện tập"/"Ăn uống"
      // reflect the created plan.
      try {
        final createdPlanId = recommendationData['createdPlanID'] as int?;
        if (createdPlanId != null) {
          await _refreshRecommendedListsFromServerPlan(createdPlanId);
          await DataService.instance.loadMealList();
          await DataService.instance.loadWorkoutList();
          try {
            final planController = Get.find<WorkoutPlanController>();
            // Refresh planController current plan and collections
            try {
              final wp = await WorkoutPlanProvider()
                  .fetchByUserID(DataService.currentUser?.id ?? '');
              if (wp != null) planController.currentWorkoutPlan.value = wp;
            } catch (_) {}
            await planController.refreshAllData();
          } catch (_) {}
        }
      } catch (e) {
        _log('⚠️ Failed to refresh preview lists after quick create: $e');
      }

      UIUtils.hideLoadingDialog();
      isCreatingPlan.value = false;

      // Navigate home and show snackbar. After navigation, ensure plan tab selected
      // Attempt to refresh workout plan controller so Home screen shows updated plan
      try {
        final planController = Get.find<WorkoutPlanController>();
        planController.onInit();
      } catch (_) {}

      await Get.offAllNamed(Routes.home);
      try {
        final home = Get.find<HomeController>();
        home.tabController.index = HomeController.workoutPlanTabIndex;
      } catch (_) {}
      Get.snackbar('Thành công', 'Đã tạo lại lộ trình',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      UIUtils.hideLoadingDialog();
      isCreatingPlan.value = false;
      Get.snackbar(
        'Lỗi',
        'Không thể tạo lộ trình: ${e.toString()}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      _log('❌ Lỗi quick create plan: $e');
    }
  }

  /// Extend current created plan by 7 days
  Future<void> extendCreatedPlanBy7() async {
    final createdPlanID = recommendationData['createdPlanID'];
    final data = Map<String, dynamic>.from(recommendationData);
    int? planIdToUse;
    if (createdPlanID != null) {
      planIdToUse = createdPlanID as int;
    } else {
      // Try to fetch latest plan from server
      try {
        final serverPlan = await apiService.getMyPlan();
        if (serverPlan['planID'] != null) {
          planIdToUse = serverPlan['planID'] as int;
          // save for future
          recommendationData['createdPlanID'] = planIdToUse;
          // also compute createdPlanDays from server plan dates if present
          try {
            final sd = DateTime.parse(serverPlan['startDate']);
            final ed = DateTime.parse(serverPlan['endDate']);
            recommendationData['createdPlanDays'] =
                ed.difference(sd).inDays + 1;
          } catch (_) {}
        }
      } catch (e) {
        _log('⚠️ getMyPlan failed: $e');
      }
    }

    if (planIdToUse == null) {
      Get.snackbar('Lỗi', 'Không tìm thấy plan để mở rộng',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    try {
      isExtending.value = true;
      UIUtils.showLoadingDialog();
      final data = Map<String, dynamic>.from(recommendationData);
      await apiService.extendPlan(
        planID: planIdToUse,
        daysToAdd: 7,
        recommendedExerciseIDs: (data['recommendedExerciseIDs'] as List)
            .map((e) => e.toString())
            .toList(),
        recommendedMealIDs: (data['recommendedMealIDs'] as List)
            .map((e) => e.toString())
            .toList(),
      );
      UIUtils.hideLoadingDialog();
      isExtending.value = false;
      Get.snackbar('Thành công', 'Đã thêm 7 ngày',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      UIUtils.hideLoadingDialog();
      final err = e.toString().toLowerCase();
      // If server reports plan not found, fallback to create a new 7-day plan
      if (err.contains('plan not found') || err.contains('404')) {
        Get.snackbar('Thông báo',
            'Plan không tồn tại trên server, sẽ tạo lại 7 ngày mới',
            snackPosition: SnackPosition.BOTTOM);
        try {
          await quickCreateAndReplacePlan();
        } catch (createErr) {
          Get.snackbar(
              'Lỗi', 'Không thể tạo lộ trình thay thế: ${createErr.toString()}',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.red,
              colorText: Colors.white);
        }
      } else if (err.contains('being extended') ||
          err.contains('is being extended')) {
        // If plan is being extended by another request, retry a few times with backoff
        const int maxRetries = 3;
        int attempt = 0;
        bool succeeded = false;
        while (attempt < maxRetries && !succeeded) {
          final waitMs = (1000 * math.pow(2, attempt)).toInt();
          await Future.delayed(Duration(milliseconds: waitMs));
          try {
            await apiService.extendPlan(
              planID: planIdToUse,
              daysToAdd: 7,
              recommendedExerciseIDs: (data['recommendedExerciseIDs'] as List)
                  .map((e) => e.toString())
                  .toList(),
              recommendedMealIDs: (data['recommendedMealIDs'] as List)
                  .map((e) => e.toString())
                  .toList(),
            );
            succeeded = true;
            Get.snackbar('Thành công', 'Đã thêm 7 ngày',
                snackPosition: SnackPosition.BOTTOM);
          } catch (_) {
            attempt++;
          }
        }
        if (!succeeded) {
          Get.snackbar('Lỗi',
              'Plan đang được mở rộng bởi request khác. Vui lòng thử lại sau.',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.red,
              colorText: Colors.white);
        }
      } else {
        Get.snackbar('Lỗi', 'Không thể mở rộng lộ trình: ${e.toString()}',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white);
      }
      isExtending.value = false;
    }
  }

  String formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  /// Fetch the user's current plan from server and update the preview lists
  /// (`recommendedExercises` and `recommendedMeals`) to match the plan's items.
  Future<void> _refreshRecommendedListsFromServerPlan(int planID) async {
    try {
      // Use plan collections to discover actual meals/exercises assigned to the plan.
      // We'll also build per-day maps so UI can render "Day 1..7 -> meals/exercises".
      planMealsByDay.clear();
      planExercisesByDay.clear();
      final Set<String> mealIDs = {};
      final Set<String> exerciseIDs = {};

      try {
        final mealCollections =
            await apiService.getPlanMealCollections(planID: planID);
        _log('🍽️ Found ${mealCollections.length} meal collections for plan $planID');
        final limitedMealCollections = _limitCollectionsByDate(
          mealCollections,
          _maxPreviewDays,
          (PlanMealCollection col) => col.date,
        );

        // Map collection id -> list of mealIDs and keep date mapping
        final Map<String, List<String>> mealIDsByCollection = {};
        final Map<String, DateTime> collectionDate = {};

        for (var col in limitedMealCollections) {
          try {
            final listID = col.id ?? '';
            if (listID.isEmpty) continue;
            final colDate = col.date ?? DateTime.now();
            collectionDate[listID] = DateUtils.dateOnly(colDate);
            final planMeals = await apiService.getPlanMeals(listID: listID);
            final List<String> idsForCol = [];
            for (var pm in planMeals) {
              try {
                final id = (pm.mealID ?? '').toString();
                if (id.isNotEmpty) idsForCol.add(id);
              } catch (_) {}
            }
            if (idsForCol.isNotEmpty) mealIDsByCollection[listID] = idsForCol;
          } catch (e) {
            _log('⚠️ Failed to read plan meals for collection ${col.id}: $e');
          }
        }

        // Choose a single collection to represent today's meals in preview:
        // prefer collection matching plan start date, otherwise nearest to today,
        // otherwise fall back to flattening all meals.
        if (mealIDsByCollection.isNotEmpty) {
          // Try to pick collection on or nearest to plan start / today
          DateTime today = DateUtils.dateOnly(DateTime.now());
          String? chosenListID;
          // prefer exact today's collection
          for (var entry in collectionDate.entries) {
            if (DateUtils.isSameDay(entry.value, today)) {
              chosenListID = entry.key;
              break;
            }
          }
          // else prefer earliest collection (day 1)
          if (chosenListID == null) {
            String? earliest;
            DateTime? minDate;
            for (var entry in collectionDate.entries) {
              if (minDate == null || entry.value.isBefore(minDate)) {
                minDate = entry.value;
                earliest = entry.key;
              }
            }
            chosenListID = earliest;
          }

          if (chosenListID != null &&
              mealIDsByCollection.containsKey(chosenListID)) {
            mealIDs.addAll(mealIDsByCollection[chosenListID]!);
            // persist recommendedMealIDs for preview data consistency
            recommendationData['recommendedMealIDs'] =
                mealIDsByCollection[chosenListID]!
                    .map((e) => e.toString())
                    .toList();
          } else {
            // fallback: flatten all meal ids
            for (var v in mealIDsByCollection.values) {
              mealIDs.addAll(v);
            }
          }

          // Build per-day meal lists. Determine earliest collection date as day 1.
          if (collectionDate.isNotEmpty) {
            DateTime minDate =
                collectionDate.values.reduce((a, b) => a.isBefore(b) ? a : b);

            // Collect all meal IDs that need to be loaded
            final allMealIds = <String>{};
            for (var entry in mealIDsByCollection.entries) {
              allMealIds.addAll(entry.value);
            }

            // Load all meals in parallel first
            await _loadMealsWithCache(allMealIds.toList());

            // Then assign to days
            for (var entry in mealIDsByCollection.entries) {
              final listID = entry.key;
              final date = collectionDate[listID] ?? minDate;
              final dayIndex = DateUtils.dateOnly(date)
                      .difference(DateUtils.dateOnly(minDate))
                      .inDays +
                  1;
              final ids = entry.value;

              // Get meals from cache (should all be cached now)
              final List<Meal> dayMeals =
                  ids.map((id) => _mealCache[id]).whereType<Meal>().toList();

              if (dayMeals.isNotEmpty) planMealsByDay[dayIndex] = dayMeals;
            }
          }
        }
      } catch (e) {
        _log('⚠️ getPlanMealCollections failed: $e');
      }

      try {
        final exerciseCollections =
            await apiService.getPlanExerciseCollections(planID: planID);
        _log('💪 Found ${exerciseCollections.length} exercise collections for plan $planID');
        final limitedExerciseCollections = _limitCollectionsByDate(
          exerciseCollections,
          _maxPreviewDays,
          (PlanExerciseCollection col) => col.date,
        );

        for (var col in limitedExerciseCollections) {
          try {
            final listID = col.id ?? '';
            if (listID.isEmpty) continue;
            final planExercises =
                await apiService.getPlanExercises(listID: listID);
            for (var pe in planExercises) {
              try {
                final id = (pe.exerciseID ?? '').toString();
                if (id.isNotEmpty) exerciseIDs.add(id);
              } catch (_) {}
            }
          } catch (e) {
            _log(
                '⚠️ Failed to read plan exercises for collection ${col.id}: $e');
          }
        }
        // Build per-day exercise lists similar to meals
        try {
          final Map<String, DateTime> exCollectionDate = {};
          final Map<String, List<String>> exIDsByCollection = {};
          for (var col in limitedExerciseCollections) {
            try {
              final lid = col.id ?? '';
              if (lid.isEmpty) continue;
              final colDate = col.date ?? DateTime.now();
              exCollectionDate[lid] = DateUtils.dateOnly(colDate);
              final planExercises =
                  await apiService.getPlanExercises(listID: lid);
              final List<String> ids = [];
              for (var pe in planExercises) {
                final id = (pe.exerciseID ?? '').toString();
                if (id.isNotEmpty) ids.add(id);
              }
              if (ids.isNotEmpty) exIDsByCollection[lid] = ids;
            } catch (e) {
              _log('⚠️ Failed reading exercise collection ${col.id}: $e');
            }
          }

          if (exIDsByCollection.isNotEmpty && exCollectionDate.isNotEmpty) {
            DateTime minExDate =
                exCollectionDate.values.reduce((a, b) => a.isBefore(b) ? a : b);

            // Collect all exercise IDs that need to be loaded
            final allExerciseIds = <String>{};
            for (var entry in exIDsByCollection.entries) {
              allExerciseIds.addAll(entry.value);
            }

            // Load all exercises in parallel first
            await _loadWorkoutsWithCache(allExerciseIds.toList());

            // Then assign to days
            for (var entry in exIDsByCollection.entries) {
              final lid = entry.key;
              final date = exCollectionDate[lid] ?? minExDate;
              final dayIndex = DateUtils.dateOnly(date)
                      .difference(DateUtils.dateOnly(minExDate))
                      .inDays +
                  1;

              // Get exercises from cache (should all be cached now)
              final List<Workout> dayExercises = entry.value
                  .map((id) => _workoutCache[id])
                  .whereType<Workout>()
                  .toList();

              if (dayExercises.isNotEmpty)
                planExercisesByDay[dayIndex] = dayExercises;
            }
          }
        } catch (_) {}
      } catch (e) {
        _log('⚠️ getPlanExerciseCollections failed: $e');
      }

      // Fetch details and update preview lists using parallel loading and cache
      final exerciseList = await _loadWorkoutsWithCache(exerciseIDs.toList());
      if (exerciseList.isNotEmpty) recommendedExercises.assignAll(exerciseList);

      // Load all meals from plan (don't limit to 3 when loading from existing plan)
      _log('🔍 Found ${mealIDs.length} meal IDs from plan collections: $mealIDs');
      final mealList = await _loadMealsWithCache(mealIDs.toList());
      _log('✅ Loaded ${mealList.length} meals from cache');
      if (mealList.isNotEmpty) recommendedMeals.assignAll(mealList);
      // After fetching per-collection meals/exercises, build date-keyed schedule
      await _buildDateKeyedSchedule();
    } catch (e) {
      _log('⚠️ _refreshRecommendedListsFromServerPlan error: $e');
    }
  }

  Future<void> _buildDateKeyedSchedule() async {
    try {
      scheduleMealsByDate.clear();
      scheduleExercisesByDate.clear();

      // Determine plan start/end from recommendationData if present
      DateTime? start;
      DateTime? end;
      try {
        if (recommendationData['startDate'] != null) {
          start = DateTime.tryParse(recommendationData['startDate']);
        }
        if (recommendationData['endDate'] != null) {
          end = DateTime.tryParse(recommendationData['endDate']);
        }
      } catch (_) {}

      // If missing, infer from planMealsByDay / planExercisesByDay min dates (we used day indices)
      int days = recommendationData['createdPlanDays'] ??
          recommendationData['planLengthInDays'] ??
          7;
      if (start == null) {
        // fallback to today
        start = DateTime.now();
      }
      if (end == null) {
        end = start.add(Duration(days: days - 1));
      }

      // Build mapping dayIndex -> date
      final totalDays = end.difference(start).inDays + 1;
      for (int i = 0; i < totalDays; i++) {
        final date = DateUtils.dateOnly(start.add(Duration(days: i)));
        final key = dateKey(date);

        // meals: prefer planMealsByDay[dayIndex], otherwise take from recommendedMeals to fill 3 meals
        final dayIndex = i + 1;
        final List<Meal> meals = [];
        if (planMealsByDay.containsKey(dayIndex)) {
          meals.addAll(planMealsByDay[dayIndex]!);
        }
        // Ensure exactly 3 meals per day
        int needed = 3 - meals.length;
        if (needed > 0) {
          // Use recommendedMeals as pool, no need to fetch from API since we already have them
          List<Meal> pool = recommendedMeals.toList();
          if (pool.isEmpty) {
            // Fallback: load from cache if available
            pool = _mealCache.values.toList();
          }

          // shuffle for randomness
          pool.shuffle();
          int added = 0;
          for (var m in pool) {
            if (added >= needed) break;
            if (!meals.any((x) => x.id == m.id)) {
              meals.add(m);
              added++;
            }
          }
          // fallback: allow duplicates if still not enough
          int idx = 0;
          while (meals.length < 3 && pool.isNotEmpty) {
            meals.add(pool[idx % pool.length]);
            idx++;
          }
        } else if (meals.length > 3) {
          // trim to 3 if server returned more
          meals.removeRange(3, meals.length);
        }

          // exercises: take planExercisesByDay[dayIndex] if exists, else use recommendedExercises sample
        final List<Workout> exercises = [];
        if (planExercisesByDay.containsKey(dayIndex)) {
          exercises.addAll(planExercisesByDay[dayIndex]!);
        } else {
          // Use recommendedExercises as pool, no need to fetch from API since we already have them
          List<Workout> poolEx = recommendedExercises.toList();
          if (poolEx.isEmpty) {
            // Fallback: use cache if available
            poolEx = _workoutCache.values.toList();
          }

          poolEx.shuffle();
          // Take all exercises from plan (backend already randomized 3-5 per day)
          exercises.addAll(poolEx);
          // if still empty, leave empty (shouldn't happen if library exists)
        }

        scheduleMealsByDate[key] = meals;
        scheduleExercisesByDate[key] = exercises;
      }
    } catch (e) {
      _log('⚠️ _buildDateKeyedSchedule failed: $e');
    }
  }

  List<T> _limitCollectionsByDate<T>(
      List<T> collections, int maxDays, DateTime? Function(T) getDate) {
    if (collections.length <= maxDays) {
      return collections;
    }

    final sorted = List<T>.from(collections)
      ..sort((a, b) {
        final dateA = getDate(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = getDate(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateA.compareTo(dateB);
      });

    final today = DateUtils.dateOnly(DateTime.now());
    final List<T> result = [];

    for (var item in sorted) {
      final date = getDate(item);
      if (date != null && !date.isBefore(today)) {
        result.add(item);
        if (result.length >= maxDays) break;
      }
    }

    if (result.length < maxDays) {
      for (var item in sorted) {
        if (result.contains(item)) continue;
        result.add(item);
        if (result.length >= maxDays) break;
      }
    }

    return result;
  }

  String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int get planLengthInDays => recommendationData['planLengthInDays'] ?? 0;
  int get bmr => (recommendationData['bmr'] ?? 0).toInt();
  int get tdee => (recommendationData['tdee'] ?? 0).toInt();
  int get dailyIntakeCalories =>
      (recommendationData['dailyIntakeCalories'] ?? 0).toInt();
  int get dailyOuttakeCalories =>
      (recommendationData['dailyOuttakeCalories'] ?? 0).toInt();
  int get dailyGoalCalories =>
      (recommendationData['dailyGoalCalories'] ?? 0).toInt();

  DateTime _computedStartDate() {
    try {
      if (recommendationData['startDate'] != null) {
        final parsed = DateTime.tryParse(recommendationData['startDate']);
        if (parsed != null) return DateUtils.dateOnly(parsed);
      }
    } catch (_) {}
    return DateUtils.dateOnly(DateTime.now());
  }

  DateTime _computedEndDate() {
    final start = _computedStartDate();
    // prefer createdPlanDays or planLengthInDays from recommendationData, fallback to 7
    int days = recommendationData['createdPlanDays'] ??
        recommendationData['planLengthInDays'] ??
        7;
    // clamp to max preview days
    if (days > _maxPreviewDays) days = _maxPreviewDays;

    // if server provided an explicit endDate, use it but clamp to [start, start+6]
    try {
      if (recommendationData['endDate'] != null) {
        final parsedEnd = DateTime.tryParse(recommendationData['endDate']);
        if (parsedEnd != null) {
          final endOnly = DateUtils.dateOnly(parsedEnd);
          final maxEnd = start.add(Duration(days: days - 1));
          if (endOnly.isBefore(start)) return maxEnd;
          return endOnly.isAfter(maxEnd) ? maxEnd : endOnly;
        }
      }
    } catch (_) {}

    return start.add(Duration(days: days - 1));
  }

  String get startDate {
    final dt = _computedStartDate();
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String get endDate {
    final dt = _computedEndDate();
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
