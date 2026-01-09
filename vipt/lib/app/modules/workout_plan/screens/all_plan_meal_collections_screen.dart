import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vipt/app/core/values/asset_strings.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/data/models/meal_collection.dart';
import 'package:vipt/app/global_widgets/app_bar_icon_button.dart';
import 'package:vipt/app/modules/workout_collection/widgets/exercise_in_collection_tile.dart';

class AllPlanMealCollectionsScreen extends StatelessWidget {
  final Map<DateTime, List<MealCollection>> mealCollectionsByDate;
  final Function(MealCollection) onCollectionPressed;
  final DateTime startDate;

  const AllPlanMealCollectionsScreen({
    Key? key,
    required this.startDate,
    required this.mealCollectionsByDate,
    required this.onCollectionPressed,
  }) : super(key: key);

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
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              children: _buildMealCollectionList(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMealCollectionList(BuildContext context) {
    List<Widget> results = [];

    // Sort dates
    final sortedDates = mealCollectionsByDate.keys.toList()..sort();
    int dayNumber = 1;

    for (var date in sortedDates) {
      final dayCollections = mealCollectionsByDate[date]!;

      // Day indicator
      Widget dayIndicator = Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4, left: 24, right: 24),
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
                        color: AppColor.textColor.withOpacity(
                          AppColor.subTextOpacity,
                        ),
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

      // Add all collections for this day
      for (var collection in dayCollections) {
        // Lấy số lượng meals trong collection
        final allMealIDs =
            collection.dateToMealID.values.expand((ids) => ids).toList();
        final mealCount = allMealIDs.length;
        String description = '$mealCount món ăn';

        Widget collectionToWidget = Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
          child: ExerciseInCollectionTile(
              asset: collection.asset.isNotEmpty
                  ? collection.asset
                  : JPGAssetString.nutrition,
              title: collection.title,
              description: description,
              onPressed: () {
                onCollectionPressed(collection);
              }),
        );

        results.add(collectionToWidget);
      }

      dayNumber++;
    }

    return results;
  }
}
