import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vipt/app/core/values/asset_strings.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/data/models/meal_nutrition.dart';
import 'package:vipt/app/global_widgets/app_bar_icon_button.dart';
import 'package:vipt/app/modules/workout_collection/widgets/exercise_in_collection_tile.dart';
import 'package:vipt/app/modules/workout_plan/workout_plan_controller.dart';

class AllPlanNutritionScreen extends StatelessWidget {
  final List<MealNutrition> nutritionList;
  final Function(MealNutrition) elementOnPress;
  final DateTime startDate;
  final bool isLoading;
  const AllPlanNutritionScreen(
      {Key? key,
      required this.startDate,
      required this.nutritionList,
      required this.elementOnPress,
      required this.isLoading})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Container(
      margin: const EdgeInsets.only(top: 48),
      height: screenHeight * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: Row(
              children: [
                AppBarIconButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  iconData: Icons.close,
                  hero: '',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'DANH SÁCH BỮA ĂN',
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          // When loading, show skeleton placeholders (matching exercise layout) instead of empty day headers
          if (isLoading)
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                children: _buildSkeletonList(context, startDate: startDate),
              ),
            )
          else
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                children: _buildNutritionList(
                  context,
                  startDate: startDate,
                  nutritionList: nutritionList,
                  elementOnPress: elementOnPress,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Build simple skeleton placeholders that mimic day headers + tiles (7 days)
  _buildSkeletonList(context, {required DateTime startDate}) {
    List<Widget> results = [];
    const int days = 7;
    for (int d = 0; d < days; d++) {
      // day indicator (skeleton)
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
                // day label skeleton
                Container(
                  width: 120,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
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

      // add 2 placeholder tiles per day
      for (int t = 0; t < 2; t++) {
        Widget placeholder = Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        );
        results.add(placeholder);
      }
    }
    return results;
  }

  _buildNutritionList(context,
      {required DateTime startDate,
      required List<MealNutrition> nutritionList,
      required Function(MealNutrition) elementOnPress}) {
    List<Widget> results = [];

    // Nh�m meals theo ng�y t? controller
    final controller = Get.find<WorkoutPlanController>();
    debugPrint(
        '?? AllPlanNutritionScreen._buildNutritionList called: nutritionList.length=${nutritionList.length}, planMeal.length=${controller.planMeal.length}, planMealCollection.length=${controller.planMealCollection.length}');
    Map<DateTime, List<MealNutrition>> mealsByDate = {};

    // Normalize input: create a defensive copy of provided list to avoid mutating caller list.
    final List<MealNutrition> normalizedNutritionList =
        List<MealNutrition>.from(nutritionList);

    // Ch? l?y admin collections (planID = 0) trong kho?ng 7 ng�y t? startDate
    final allCollections = controller.planMealCollection
        .where((col) =>
            col.planID == 0 &&
            col.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
            col.date.isBefore(startDate.add(const Duration(days: 7))))
        .toList();

    // N?u kh�ng c� planMealCollection (v� d? khi ngu?i d�ng chua t?o plan),
    // hi?n th? nutritionList th?ng h�ng (fallback) thay v� nh�m theo ng�y r?ng.
    if (allCollections.isEmpty) {
      // Th�m m?t ti�u d? ng?n d? b�o l� dang hi?n th? g?i �/kh�ng theo ng�y
      if (normalizedNutritionList.isNotEmpty) {
        results.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'G?i � m�n an',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ));
      }

      for (var nutrition in normalizedNutritionList) {
        Widget collectionToWidget = Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ExerciseInCollectionTile(
              asset: nutrition.meal.asset == ''
                  ? JPGAssetString.meal
                  : nutrition.meal.asset,
              title: nutrition.getName(),
              description: nutrition.calories.toStringAsFixed(0) + ' kcal',
              onPressed: () {
                elementOnPress(nutrition);
              }),
        );

        results.add(collectionToWidget);
      }

      return results;
    }

    final nutritionMap = <String, MealNutrition>{};
    for (var nutri in normalizedNutritionList) {
      try {
        final key = (nutri.meal.id ?? '');
        if (key.isNotEmpty) {
          nutritionMap[key] = nutri;
        }
      } catch (_) {
        // skip malformed nutrition entries
      }
    }

    // Nh�m theo ng�y t? plan collections
    for (var planCol in allCollections) {
      if (planCol.id == null || planCol.id!.isEmpty) continue;
      final planMeals =
          controller.planMeal.where((pm) => pm.listID == planCol.id).toList();
      final dateKey = DateUtils.dateOnly(planCol.date);
      for (var planMeal in planMeals) {
        final nutrition = nutritionMap[planMeal.mealID];
        if (nutrition != null) {
          mealsByDate.putIfAbsent(dateKey, () => []);
          mealsByDate[dateKey]!.add(nutrition);
        }
      }
    }

    // Ch? hi?n th? c�c ng�y c� data th?c s?
    final sortedDates = mealsByDate.keys.toList()..sort();

    int dayNumber = 1;
    for (var dateKey in sortedDates) {
      final dayMeals = mealsByDate[dateKey]!;
      if (dayMeals.isEmpty) continue;

      // Th�m day indicator
      Widget dayIndicator = Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
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
                Text(
                  'NGÀY $dayNumber',
                  style: Theme.of(context).textTheme.titleSmall!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  '${dateKey.day}/${dateKey.month}/${dateKey.year}',
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        color: AppColor.textColor.withOpacity(
                          AppColor.subTextOpacity,
                        ),
                      ),
                ),
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

      // Hi?n th? meals cho ng�y n�y
      for (var nutrition in dayMeals) {
        Widget collectionToWidget = Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ExerciseInCollectionTile(
              asset: nutrition.meal.asset == ''
                  ? JPGAssetString.meal
                  : nutrition.meal.asset,
              title: nutrition.getName(),
              description: nutrition.calories.toStringAsFixed(0) + ' kcal',
              onPressed: () {
                elementOnPress(nutrition);
              }),
        );

        results.add(collectionToWidget);
      }

      dayNumber++;
    }

    return results;
  }
}
