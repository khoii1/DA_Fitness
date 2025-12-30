import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';
import 'package:vipt/app/core/values/asset_strings.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/data/models/workout_collection.dart';
import 'package:vipt/app/global_widgets/app_bar_icon_button.dart';
import 'package:vipt/app/global_widgets/asset_image_background_container.dart';
import 'package:vipt/app/global_widgets/exercise_list_widget.dart';
import 'package:vipt/app/global_widgets/indicator_display_widget.dart';
import 'package:vipt/app/global_widgets/intro_collection_widget.dart';
import 'package:vipt/app/modules/workout_collection/widgets/collection_setting_widget.dart';
import 'package:vipt/app/modules/workout_collection/workout_collection_controller.dart';
import 'package:vipt/app/routes/pages.dart';

class MyWorkoutCollectionDetailScreen extends StatelessWidget {
  MyWorkoutCollectionDetailScreen({Key? key}) : super(key: key);

  final _controller = Get.find<WorkoutCollectionController>();

  void handleBackAction() {
    _controller.updateCollectionSetting();
    _controller.resetCaloAndTime();
  }

  void init() {
    // Check if WorkoutCollection is passed via arguments
    final args = Get.arguments;
    if (args is WorkoutCollection) {
      _controller.selectedCollection = args;
    }
    _controller.loadCollectionSetting();
  }

  @override
  Widget build(BuildContext context) {
    init();

    // Return loading or error if selectedCollection is null
    if (_controller.selectedCollection == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Lỗi'),
        ),
        body: Center(
          child: Text('Không tìm thấy bộ luyện tập'),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        handleBackAction();
        return true;
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        floatingActionButton: GetBuilder<WorkoutCollectionController>(
          builder: (_) => FloatingActionButton.extended(
            backgroundColor: _controller.generatedWorkoutList.isEmpty
                ? AppColor.disableButtonColor
                : Theme.of(context).primaryColor,
            onPressed: _controller.generatedWorkoutList.isEmpty
                ? null
                : () {
                    Get.toNamed(Routes.previewExerciseList);
                  },
            isExtended: true,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            label: SizedBox(
              width: MediaQuery.of(context).size.width * 0.75,
              child: Text(
                'Bắt đầu luyện tập'.tr,
                style: Theme.of(context).textTheme.labelLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: AppBarIconButton(
              padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
              hero: 'leadingButtonAppBar',
              iconData: Icons.arrow_back_ios_new_rounded,
              onPressed: () {
                handleBackAction();
                Navigator.of(context).pop();
              }),
          actions: [],
        ),
        body: AssetImageBackgroundContainer(
          imageURL: JPGAssetString.userWorkoutCollection,
          child: Column(
            children: [
              IntroCollectionWidget(
                  title: _controller.selectedCollection?.title.tr ??
                      'Không có tiêu đề',
                  description: _controller.selectedCollection?.description.tr ??
                      'Không có mô tả'),
              const SizedBox(
                height: 8,
              ),
              Obx(() {
                return IndicatorDisplayWidget(
                  displayTime: '${_controller.displayTime}'.tr,
                  displayCaloValue:
                      '${_controller.caloValue.value.toInt()} calo'.tr,
                );
              }),
              const SizedBox(
                height: 16,
              ),
              GetBuilder<WorkoutCollectionController>(
                builder: (_) => CollectionSettingWidget(
                  controller: _controller,
                  showShuffleTile: true,
                  enabled: _controller.workoutList.isNotEmpty,
                ),
              ),
              const SizedBox(
                height: 24,
              ),
              GetBuilder<WorkoutCollectionController>(
                builder: (_) => ExerciseListWidget(
                    workoutList: _controller.generatedWorkoutList,
                    displayExerciseTime:
                        '${_controller.collectionSetting.value.exerciseTime} giây'),
              ),
              SizedBox(
                height:
                    (Theme.of(context).textTheme.labelLarge?.fontSize ?? 14) *
                        4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
