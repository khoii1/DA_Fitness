import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vipt/app/core/values/asset_strings.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/data/models/collection_setting.dart';
import 'package:vipt/app/data/models/meal_nutrition.dart';
// 'nutrition.dart' no longer needed here
import 'package:vipt/app/data/models/plan_exercise.dart';
import 'package:vipt/app/data/models/workout_collection.dart';
import 'package:vipt/app/data/services/data_service.dart';
import 'package:vipt/app/global_widgets/custom_confirmation_dialog.dart';
import 'package:vipt/app/global_widgets/loading_widget.dart';
import 'package:vipt/app/modules/nutrition/nutrition_controller.dart';
import 'package:vipt/app/modules/workout_collection/widgets/exercise_in_collection_tile.dart';
import 'package:vipt/app/modules/workout_collection/workout_collection_controller.dart';
import 'package:vipt/app/modules/workout_plan/screens/all_plan_exercise_screen.dart';
import 'package:vipt/app/modules/workout_plan/screens/all_plan_nutrition.screen.dart';
import 'package:vipt/app/routes/pages.dart';
import 'package:vipt/app/core/utilities/utils.dart';
import 'package:vipt/app/data/providers/meal_provider_api.dart';
import 'package:vipt/app/modules/recommendation_preview/recommendation_preview_controller.dart';

import '../workout_plan_controller.dart';

class PlanTabHolder extends StatefulWidget {
  const PlanTabHolder({Key? key}) : super(key: key);

  @override
  State<PlanTabHolder> createState() => _PlanTabHolderState();
}

class _PlanTabHolderState extends State<PlanTabHolder>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  final _controller = Get.find<WorkoutPlanController>();

  List<WorkoutCollection> workouts = [];
  List<MealNutrition> meals = [];
  List<WorkoutCollection> allWorkouts = [];
  List<MealNutrition> allMeals = [];

  Timer? _reloadWorkoutsTimer;
  Timer? _reloadMealsTimer;

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    super.initState();

    // Lắng nghe thay đổi từ DataService để tự động reload
    _setupDataServiceListeners();

    // Load dữ liệu ban đầu
    _loadInitialData();

    // Đảm bảo loadDailyGoalCalories được gọi lại nếu chưa có workout plan
    ever(_controller.isLoading, (isLoading) {
      if (isLoading == false && mounted) {
        // Kiểm tra lại workout plan sau khi loading xong
        if (_controller.currentWorkoutPlan.value == null) {
          _controller.loadDailyGoalCalories();
        }
        // Reload dữ liệu sau khi controller.onInit() hoàn thành
        // Delay một chút để đảm bảo widget đã mount
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _reloadData();
          }
        });
      }
    });

    // Lắng nghe thay đổi planExerciseCollection với debounce để tránh reload quá nhiều
    ever(_controller.planExerciseCollection, (_) {
      // final collections = _controller.planExerciseCollection;
      _reloadWorkoutsTimer?.cancel();
      _reloadWorkoutsTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          _reloadWorkouts();
        }
      });
    });

    // Lắng nghe thay đổi planMealCollection với debounce để tránh reload quá nhiều
    ever(_controller.planMealCollection, (_) {
      // final collections = _controller.planMealCollection;
      _reloadMealsTimer?.cancel();
      _reloadMealsTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          _reloadMeals();
        }
      });
    });

    // Fallback: Reload sau 2 giây nếu chưa có dữ liệu
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && workouts.isEmpty && meals.isEmpty) {
        _reloadData();
      }
    });
  }

  void _loadInitialData() {
    workouts = _controller.loadWorkoutCollectionToShow(DateTime.now());
    allWorkouts = _controller.loadAllWorkoutCollection();

    _controller.loadMealListToShow(DateTime.now()).then((value) {
      if (mounted) {
        setState(() {
          meals = value;
        });
      }
    });

    // Load allMeals ngay từ đầu
    _controller.loadAllMealList().then((value) async {
      if (!mounted) return;
      if (value.isNotEmpty) {
        setState(() {
          allMeals = value;
          if (meals.isEmpty && allMeals.isNotEmpty) {
            meals = allMeals.take(6).toList();
          }
        });
      } else {
        // Nếu API trả về rỗng, thử build fallback từ DataService.instance.mealList (local cache)
        final cachedMeals = DataService.instance.mealList;
        if (cachedMeals.isNotEmpty) {
          List<MealNutrition> tmp = [];
          int takeCount = cachedMeals.length >= 6 ? 6 : cachedMeals.length;
          for (int i = 0; i < takeCount; i++) {
            final mn = MealNutrition(meal: cachedMeals[i]);
            try {
              await mn.getIngredients();
            } catch (_) {}
            tmp.add(mn);
          }
          if (!mounted) return;
          setState(() {
            allMeals = tmp;
            if (meals.isEmpty && allMeals.isNotEmpty) {
              meals = allMeals.take(6).toList();
            }
          });
        }
      }
    });
  }

  void _reloadData() {
    _reloadWorkouts();
    _reloadMeals();
  }

  void _reloadWorkouts() {
    if (!mounted) return;
    setState(() {
      workouts = _controller.loadWorkoutCollectionToShow(DateTime.now());
      allWorkouts = _controller.loadAllWorkoutCollection();
    });
  }

  void _reloadMeals() {
    if (!mounted) return;

    // Ưu tiên load meals từ plan hiện tại trước
    final currentPlanID = _controller.currentWorkoutPlan.value?.id ?? 0;
    if (currentPlanID > 0) {
      // Load từ plan hiện tại
      _controller.loadWorkoutPlanMealList(currentPlanID, lightLoad: true).then((_) {
        if (!mounted) return;
        // Load today's plan meals từ plan hiện tại
        _controller.loadMealListToShow(DateTime.now()).then((value) {
          if (!mounted) return;
          setState(() {
            meals = value;
          });

          // Load allMeals từ plan hiện tại
          _controller.loadAllMealList().then((allValue) {
            if (!mounted) return;
            setState(() {
              allMeals = allValue;
            });
          });
        });
      });
    } else {
      // Fallback: Load today's plan meals first, then ensure we have a fallback to allMeals
      _controller.loadMealListToShow(DateTime.now()).then((value) {
        if (!mounted) return;
        setState(() {
          meals = value;
        });

        // If today's plan meals empty, try to use allMeals as fallback
        if (meals.isEmpty) {
          _controller.loadAllMealList().then((allValue) async {
            if (!mounted) return;
            if (allValue.isNotEmpty) {
              setState(() {
                allMeals = allValue;
                if (meals.isEmpty && allMeals.isNotEmpty) {
                  meals = allMeals.take(6).toList();
                }
              });
            } else {
              final cachedMeals = DataService.instance.mealList;
              if (cachedMeals.isNotEmpty) {
                List<MealNutrition> tmp = [];
                int takeCount = cachedMeals.length >= 6 ? 6 : cachedMeals.length;
                for (int i = 0; i < takeCount; i++) {
                  final mn = MealNutrition(meal: cachedMeals[i]);
                  try {
                    await mn.getIngredients();
                  } catch (_) {}
                  tmp.add(mn);
                }
                if (!mounted) return;
                setState(() {
                  allMeals = tmp;
                  if (meals.isEmpty && allMeals.isNotEmpty) {
                    meals = allMeals.take(6).toList();
                  }
                });
              }
            }
          });
        } else {
          // still refresh allMeals in background
          _controller.loadAllMealList().then((allValue) {
            if (!mounted) return;
            setState(() {
              allMeals = allValue;
            });
          });
        }
      });
    }
  }

  /// Thiết lập listeners để lắng nghe thay đổi từ DataService
  void _setupDataServiceListeners() {
    // Lắng nghe thay đổi mealList từ DataService
    ever(DataService.instance.mealListRx, (_) {
      _reloadMealsTimer?.cancel();
      _reloadMealsTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _reloadMeals();
        }
      });
    });

    // Lắng nghe thay đổi workoutList từ DataService
    ever(DataService.instance.workoutListRx, (_) {
      _reloadWorkoutsTimer?.cancel();
      _reloadWorkoutsTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _reloadWorkouts();
        }
      });
    });

    // Lắng nghe thay đổi currentWorkoutPlan để reload meals từ plan mới
    ever(_controller.currentWorkoutPlan, (_) {
      _reloadMealsTimer?.cancel();
      _reloadMealsTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          _reloadMeals();
        }
      });
    });

    // Log đã tắt để tăng tốc độ
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            tabAlignment: TabAlignment.fill,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            onTap: (index) {
              setState(() {
                _selectedTabIndex = index;
              });
            },
            labelStyle: Theme.of(context).textTheme.titleSmall!.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
            unselectedLabelStyle:
                Theme.of(context).textTheme.titleSmall!.copyWith(
                      fontSize: 14,
                    ),
            tabs: const [
              Tab(
                text: 'Luyện tập',
              ),
              Tab(
                text: 'Ăn uống',
              ),
            ],
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Builder(builder: (_) {
          if (_selectedTabIndex == 0) {
            return Column(
              children: [
                ..._buildCollectionList(
                  workoutCollectionList: workouts,
                  elementOnPress: (col) async {
                    await _handleSelectExercise(col);
                  },
                ),
                Obx(() {
                  // Hiển thị nút nếu có dữ liệu workout (có thể từ default plan hoặc user plan)
                  if (allWorkouts.isNotEmpty ||
                      _controller.planExerciseCollection.isNotEmpty) {
                    // Lấy startDate từ workout plan nếu có, nếu không thì dùng ngày hiện tại
                    DateTime startDate =
                        _controller.currentWorkoutPlan.value?.startDate ??
                            DateTime.now();

                    return SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        child: Text(
                          'Xem tất cả các ngày',
                          style:
                              Theme.of(context).textTheme.labelLarge!.copyWith(
                                    fontSize: 16,
                                    color: AppColor.primaryColor,
                                  ),
                        ),
                        onPressed: () {
                          // Navigate to full-screen AllPlanExerciseScreen
                          Get.to(() => AllPlanExerciseScreen(
                                startDate: startDate,
                                workoutCollectionList: allWorkouts,
                                elementOnPress: (col) async {
                                  await _handleSelectExercise(col);
                                },
                              ));
                        },
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }),
              ],
            );
          } else {
            return Obx(
              () => _controller.isTodayMealListLoading.value
                  ? const Padding(
                      padding: EdgeInsets.all(24.0), child: LoadingWidget())
                  : Column(
                      children: [
                        ..._buildNutritionList(
                          nutritionList: meals,
                          elementOnPress: (nutri) async {
                            await handleSelectMeal(nutri);
                          },
                        ),
                        Obx(() {
                          // Hiển thị nút nếu có dữ liệu meal (có thể từ default plan hoặc user plan)
                          if (allMeals.isNotEmpty ||
                              _controller.planMealCollection.isNotEmpty) {
                            // Lấy startDate từ workout plan nếu có, nếu không thì dùng ngày hiện tại
                            DateTime startDate = _controller
                                    .currentWorkoutPlan.value?.startDate ??
                                DateTime.now();

                            return SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                child: Text(
                                  'Xem tất cả các ngày',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge!
                                      .copyWith(
                                        fontSize: 16,
                                        color: AppColor.primaryColor,
                                      ),
                                ),
                                onPressed: () async {
                                  int planID = _controller
                                          .currentWorkoutPlan.value?.id ??
                                      0;
                                  // Load full meal collections for this plan (no lightLoad)
                                  // Nếu không có plan hiện tại, thử load từ recommendation data
                                  if (planID == 0) {
                                    try {
                                      final recommendationController = Get.find<RecommendationPreviewController>();
                                      planID = recommendationController.recommendationData['createdPlanID'] as int? ?? 0;
                                    } catch (_) {}
                                  }
                                  try {
                                    await _controller.loadWorkoutPlanMealList(
                                        planID,
                                        lightLoad: false);
                                  } catch (_) {}

                                  if (!mounted) return;

                                  // Show a simple loading dialog while we fetch full data
                                  UIUtils.showLoadingDialog();
                                  // Try to load all meal nutritions from current plan first
                                  List<MealNutrition> nutritionToShow = [];
                                  int currentPlanID = _controller.currentWorkoutPlan.value?.id ?? 0;

                                  if (currentPlanID == 0) {
                                    try {
                                      final recommendationController = Get.find<RecommendationPreviewController>();
                                      currentPlanID = recommendationController.recommendationData['createdPlanID'] as int? ?? 0;
                                    } catch (_) {}
                                  }

                                  try {
                                    if (currentPlanID > 0) {
                                      // Load từ plan hiện tại
                                      await _controller.loadWorkoutPlanMealList(currentPlanID, lightLoad: false);
                                      nutritionToShow = await _controller.loadAllMealList();
                                    } else {
                                      // Fallback: Load từ cache hoặc meals hiện tại
                                      nutritionToShow = await _controller.loadAllMealList();
                                    }
                                  } catch (_) {
                                    nutritionToShow = allMeals.isNotEmpty ? allMeals : meals;
                                  }

                                  // If still empty, try to build nutrition list from controller.planMeal using local cache or API
                                  if (nutritionToShow.isEmpty && _controller.planMeal.isNotEmpty) {
                                    final firebaseMealProvider = MealProvider();
                                    List<MealNutrition> tmp = [];
                                    for (var pm in _controller.planMeal) {
                                      final mealId = pm.mealID;
                                      if (mealId.isEmpty) continue;
                                      try {
                                        // Try in-memory cache first
                                        final existing = DataService.instance.mealList.firstWhereOrNull((m) => m.id == mealId);
                                        if (existing != null) {
                                          final mn = MealNutrition(meal: existing);
                                          try {
                                            await mn.getIngredients();
                                          } catch (_) {}
                                          tmp.add(mn);
                                        } else {
                                          // Fetch from API
                                          final m = await firebaseMealProvider.fetch(mealId);
                                          final mn = MealNutrition(meal: m);
                                          try {
                                            await mn.getIngredients();
                                          } catch (_) {}
                                          tmp.add(mn);
                                        }
                                      } catch (e) {
                                        // ignore individual failures
                                        debugPrint('⚠️ build nutrition from planMeal failed for $mealId: $e');
                                      }
                                    }
                                    if (tmp.isNotEmpty) {
                                      nutritionToShow = tmp;
                                    }
                                  }

                                  // Final fallback: use the local `meals` already loaded in this widget
                                  if (nutritionToShow.isEmpty && meals.isNotEmpty) {
                                    nutritionToShow = meals;
                                  }

                                  // Hide loading and navigate to full-screen AllPlanNutritionScreen
                                  UIUtils.hideLoadingDialog();
                                  if (!mounted) return;
                                  debugPrint(
                                      '🔍 Navigating to AllPlanNutritionScreen: nutritionToShow.length=${nutritionToShow.length}, controller.planMeal.length=${_controller.planMeal.length}, controller.planMealCollection.length=${_controller.planMealCollection.length}');
                                  Get.to(() => AllPlanNutritionScreen(
                                        isLoading: false,
                                        nutritionList: nutritionToShow,
                                        startDate: startDate,
                                        elementOnPress: (nutri) async {
                                          await handleSelectMeal(nutri);
                                        },
                                      ));
                                },
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ],
                    ),
            );
          }
        }),
      ],
    );
  }

  _handleSelectExercise(WorkoutCollection col) async {
    debugPrint('🔍 _handleSelectExercise: col.id = ${col.id}');
    debugPrint(
        '🔍 _handleSelectExercise: col.generatorIDs = ${col.generatorIDs}');
    debugPrint(
        '🔍 _controller.planExerciseCollection.length = ${_controller.planExerciseCollection.length}');
    debugPrint(
        '🔍 currentWorkoutPlan = ${_controller.currentWorkoutPlan.value}');
    debugPrint(
        '🔍 currentWorkoutPlan.id = ${_controller.currentWorkoutPlan.value?.id}');

    // Nếu planExerciseCollection rỗng, load lại trước
    if (_controller.planExerciseCollection.isEmpty) {
      debugPrint('⚠️ planExerciseCollection rỗng, đang load lại...');
      // Luôn load planID = 0 (default plan) trước
      await _controller.loadPlanExerciseCollectionList(0, lightLoad: false);
      debugPrint(
          '✅ Đã load xong, planExerciseCollection.length = ${_controller.planExerciseCollection.length}');
    }

    final _collectionController = Get.put(WorkoutCollectionController());
    _collectionController.useDefaulColSetting = false;

    // Đợi getCollectionSetting vì nó giờ là async
    debugPrint('🔍 Đang gọi getCollectionSetting...');
    CollectionSetting? colSetting =
        await _controller.getCollectionSetting(col.id ?? '');
    debugPrint('🔍 colSetting = $colSetting');

    if (colSetting != null) {
      _collectionController.collectionSetting.value =
          CollectionSetting.fromCollectionSetting(colSetting);

      // LUÔN load exercises từ API để đảm bảo có dữ liệu mới nhất
      if (col.id != null && col.id!.isNotEmpty) {
        debugPrint('🔍 Đang gọi loadPlanExerciseList với listID: ${col.id}');
        await _controller.loadPlanExerciseList(col.id!);
        debugPrint(
            '🔍 planExercise.length = ${_controller.planExercise.length}');

        // Tạo lại WorkoutCollection với generatorIDs đã được load
        List<PlanExercise> exerciseList = _controller.planExercise
            .where((p0) => p0.listID == col.id)
            .toList();
        debugPrint(
            '🔍 exerciseList.length cho col.id ${col.id} = ${exerciseList.length}');

        // Debug: In ra exerciseID của mỗi exercise
        for (var ex in exerciseList) {
          debugPrint(
              '🔍 Exercise: id=${ex.id}, exerciseID="${ex.exerciseID}", listID=${ex.listID}');
        }

        // Nếu có exercises, cập nhật collection
        if (exerciseList.isNotEmpty) {
          final generatorIDs = exerciseList
              .map((e) => e.exerciseID)
              .where((id) => id.isNotEmpty)
              .toList();
          debugPrint('🔍 generatorIDs sau khi map = $generatorIDs');

          col = WorkoutCollection(
            col.id,
            title: col.title,
            description: col.description,
            asset: col.asset,
            generatorIDs: generatorIDs,
            categoryIDs: col.categoryIDs,
          );
          debugPrint('🔍 Đã cập nhật col.generatorIDs = ${col.generatorIDs}');
        }
      }

      // Kiểm tra nếu vẫn không có exercises, hiển thị thông báo
      debugPrint(
          '🔍 Final col.generatorIDs.isEmpty = ${col.generatorIDs.isEmpty}');
      if (col.generatorIDs.isEmpty) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return CustomConfirmationDialog(
              icon: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child:
                    Icon(Icons.warning_rounded, color: Colors.orange, size: 48),
              ),
              label: 'Không có bài tập',
              content:
                  'Bài tập này chưa có danh sách bài tập nào. Vui lòng thử lại sau.',
              showOkButton: false,
              labelCancel: 'Đóng',
              onCancel: () {
                Navigator.of(context).pop();
              },
              buttonsAlignment: MainAxisAlignment.center,
              buttonFactorOnMaxWidth: double.infinity,
            );
          },
        );
        await Get.delete<WorkoutCollectionController>();
        return;
      }

      // Đợi load workout list xong trước khi navigate
      await _collectionController.onSelectUserCollection(col);
      await Get.toNamed(Routes.myWorkoutCollectionDetail);
      await Get.delete<WorkoutCollectionController>();
    } else {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return CustomConfirmationDialog(
            icon: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Icon(Icons.error_rounded,
                  color: AppColor.errorColor, size: 48),
            ),
            label: 'Đã xảy ra lỗi',
            content: 'Không tìm thấy cài đặt bộ luyện tập',
            showOkButton: false,
            labelCancel: 'Đóng',
            onCancel: () {
              Navigator.of(context).pop();
            },
            buttonsAlignment: MainAxisAlignment.center,
            buttonFactorOnMaxWidth: double.infinity,
          );
        },
      );
    }
  }

  handleSelectMeal(MealNutrition nutrition) async {
    Get.put(NutritionController());
    await Get.toNamed(Routes.dishDetail, arguments: nutrition);
    await Get.delete<NutritionController>();
  }

  _buildCollectionList(
      {required List<WorkoutCollection> workoutCollectionList,
      required Function(WorkoutCollection) elementOnPress}) {
    int collectionPerDay = 4;
    List<Widget> results = [];

    int count = workoutCollectionList.length;
    for (int i = 0; i < count; i++) {
      WorkoutCollection collection = workoutCollectionList[i];
      String cateList = DataService.instance.collectionCateList
          .where((item) => collection.categoryIDs.contains(item.id))
          .map((e) => e.name)
          .toString()
          .replaceAll(RegExp(r'\(|\)'), '');

      Widget collectionToWidget = Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ExerciseInCollectionTile(
            asset: collection.asset == ''
                ? JPGAssetString.userWorkoutCollection
                : collection.asset,
            title: collection.title,
            description: cateList,
            onPressed: () {
              elementOnPress(collection);
            }),
      );

      if (i % collectionPerDay == 0) {
        Widget dayIndicator = Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Divider(
                  thickness: 1,
                  color: AppColor.textFieldUnderlineColor,
                ),
              ),
              const SizedBox(
                width: 16,
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // const SizedBox(
                  //   height: 24,
                  // ),
                  Text(
                    'NGÀY ${i ~/ collectionPerDay + 1}',
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(
                    height: 2,
                  ),
                  Text(
                    '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                          color: AppColor.textColor.withOpacity(
                            AppColor.subTextOpacity,
                          ),
                        ),
                  ),
                  // const SizedBox(
                  //   height: 4,
                  // ),
                ],
              ),
              const SizedBox(
                width: 16,
              ),
              Expanded(
                child: Divider(
                  thickness: 1,
                  color: AppColor.textFieldUnderlineColor,
                ),
              ),
            ],
          ),
        );

        results.add(dayIndicator);
      }

      results.add(collectionToWidget);
    }

    return results;
  }

  _buildNutritionList(
      {required List<MealNutrition> nutritionList,
      required Function(MealNutrition) elementOnPress}) {
    // Group nutritionList by planMealCollection dates so main list matches "AllPlanNutritionScreen"
    final controller = Get.find<WorkoutPlanController>();
    Map<DateTime, List<MealNutrition>> mealsByDate = {};

    // Map mealId -> MealNutrition for quick lookup
    final nutritionMap = <String, MealNutrition>{};
    for (var n in nutritionList) {
      nutritionMap[n.meal.id ?? ''] = n;
    }

    // Build mealsByDate using controller.planMealCollection and controller.planMeal
    for (var col in controller.planMealCollection) {
      final dateKey = DateUtils.dateOnly(col.date);
      final planMeals = controller.planMeal.where((pm) => pm.listID == (col.id ?? '')).toList();
      for (var pm in planMeals) {
        final mn = nutritionMap[pm.mealID];
        if (mn != null) {
          mealsByDate.putIfAbsent(dateKey, () => []);
          mealsByDate[dateKey]!.add(mn);
        }
      }
    }

    // If no grouped meals found but nutritionList not empty, fallback to simple grouping by every N items
    if (mealsByDate.isEmpty && nutritionList.isNotEmpty) {
      int collectionPerDay = 3;
      int count = nutritionList.length;
      for (int i = 0; i < count; i++) {
        if (i % collectionPerDay == 0) {
          // attempt to infer day based on index and today's date offset
          DateTime inferredDate = DateTime.now().add(Duration(days: i ~/ collectionPerDay));
          mealsByDate.putIfAbsent(DateUtils.dateOnly(inferredDate), () => []);
        }
        final mn = nutritionList[i];
        final keys = mealsByDate.keys.toList()..sort();
        mealsByDate[keys.last]!.add(mn);
      }
    }

    // Build widgets sorted by date
    final sortedDates = mealsByDate.keys.toList()..sort();
    List<Widget> results = [];
    int dayNumber = 1;
    for (var date in sortedDates) {
      final dayMeals = mealsByDate[date]!;

      Widget dayIndicator = Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Divider(
                thickness: 1,
                color: AppColor.textFieldUnderlineColor,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'NGÀY $dayNumber',
                  style: Theme.of(context).textTheme.titleSmall!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.day}/${date.month}/${date.year}',
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        color: AppColor.textColor.withOpacity(AppColor.subTextOpacity),
                      ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Divider(
                thickness: 1,
                color: AppColor.textFieldUnderlineColor,
              ),
            ),
          ],
        ),
      );

      results.add(dayIndicator);

      for (var nutrition in dayMeals) {
        Widget collectionToWidget = Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ExerciseInCollectionTile(
            asset: nutrition.meal.asset == '' ? JPGAssetString.meal : nutrition.meal.asset,
            title: nutrition.getName(),
            description: nutrition.calories.toStringAsFixed(0) + ' kcal',
            onPressed: () {
              elementOnPress(nutrition);
            },
          ),
        );
        results.add(collectionToWidget);
      }

      dayNumber++;
    }

    return results;
  }

  @override
  void dispose() {
    _reloadWorkoutsTimer?.cancel();
    _reloadMealsTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }
}
