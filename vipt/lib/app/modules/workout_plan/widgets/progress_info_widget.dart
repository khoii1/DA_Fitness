import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:vipt/app/core/values/asset_strings.dart';
import 'package:vipt/app/core/values/colors.dart';
import 'package:vipt/app/global_widgets/custom_confirmation_dialog.dart';
import 'package:vipt/app/modules/workout_collection/widgets/expandable_widget.dart';
import 'package:vipt/app/modules/workout_plan/workout_plan_controller.dart';

class ProgressInfoWidget extends StatefulWidget {
  final List<bool> completeDays;
  final bool showAction;
  final bool showTitle;
  final String? currentDay;
  final Function? resetPlanFunction;
  final int outtakeCalories;
  final int intakeCalories;
  final int goalCalories;
  const ProgressInfoWidget(
      {Key? key,
      required this.completeDays,
      this.currentDay,
      this.resetPlanFunction,
      this.showAction = true,
      this.showTitle = true,
      required this.outtakeCalories,
      required this.intakeCalories,
      required this.goalCalories})
      : super(key: key);

  @override
  State<ProgressInfoWidget> createState() => _ProgressInfoWidgetState();
}

class _ProgressInfoWidgetState extends State<ProgressInfoWidget> {
  late bool _expand;
  int _visibleFlameCount = 12; // Bắt đầu với 12 flame (2 hàng)
  final ScrollController _scrollController = ScrollController();
  final _controller = Get.find<WorkoutPlanController>();

  @override
  void initState() {
    // Mặc định expand để hiển thị hình lửa
    _expand = true;
    super.initState();

    // Lắng nghe scroll để load thêm khi scroll đến cuối
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Khi scroll gần đến cuối (còn 100 pixels), load thêm 12 flame
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      if (_visibleFlameCount < widget.completeDays.length) {
        setState(() {
          _visibleFlameCount =
              (_visibleFlameCount + 12).clamp(0, widget.completeDays.length);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sử dụng Obx để tự động rebuild khi calories thay đổi
    return Obx(() {
      double _progressValue = _getProgressValue();
      if (_progressValue.isNaN) {
        _progressValue = 0;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTitle)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _expand = !_expand;
                  });
                },
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tiến trình',
                        style:
                            Theme.of(context).textTheme.headlineSmall!.copyWith(
                                  color: AppColor.accentTextColor,
                                ),
                      ),
                      Icon(
                          _expand
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: AppColor.accentTextColor),
                    ],
                  ),
                ),
              ),
            ),
          ExpandableWidget(
            expand: _expand,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              'Ngày ${widget.currentDay}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall!
                                  .copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            if (widget.showAction)
                              const SizedBox(
                                width: 4,
                              ),
                            if (widget.showAction)
                              Material(
                                borderRadius: BorderRadius.circular(5),
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(5),
                                  onTap: () async {
                                    await showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return CustomConfirmationDialog(
                                          label: 'Tự động ghi nhận tiến trình',
                                          content:
                                              'Ngày sẽ tự động được đánh dấu là hoàn thành khi calories trong ngày xấp xỉ bằng calories mục tiêu (không chênh lệch quá 100 calories).',
                                          labelCancel: 'Đóng',
                                          textAlign: TextAlign.left,
                                          onCancel: () {
                                            Navigator.of(context).pop();
                                          },
                                          showOkButton: false,
                                          buttonsAlignment:
                                              MainAxisAlignment.end,
                                        );
                                      },
                                    );
                                  },
                                  child: SvgPicture.asset(
                                    SVGAssetString.question,
                                    height: 20,
                                    color: AppColor.textColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Đã bỏ nút "Bắt đầu lại" - streak sẽ tự động reset khi user bỏ lỡ 1 ngày
                    ],
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  _buildFlameGrid(context),
                  const SizedBox(
                    height: 36,
                  ),
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        child: LinearProgressIndicator(
                          value: _progressValue
                              .abs(), // Sử dụng giá trị tuyệt đối cho progress bar
                          minHeight: 8,
                          backgroundColor: AppColor.textFieldUnderlineColor
                              .withOpacity(AppColor.subTextOpacity),
                          color: _progressValue >= 0
                              ? AppColor.secondaryColor // Màu xanh khi dương
                              : Colors.red, // Màu đỏ khi âm
                        ),
                      ),
                      Align(
                        alignment: _progressValue >= 0
                            ? Alignment.lerp(Alignment.topLeft,
                                Alignment.topRight, _progressValue)!
                            : Alignment.lerp(
                                Alignment.topLeft,
                                Alignment.topRight,
                                _progressValue
                                    .abs())!, // Alignment cho giá trị âm
                        child: Padding(
                          padding: const EdgeInsets.only(top: 18.0),
                          child: Text(
                              '${(_progressValue * 100).toStringAsFixed(0)}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall!
                                  .copyWith(
                                    color: _progressValue >= 0
                                        ? AppColor
                                            .secondaryColor // Màu xanh khi dương
                                        : Colors.red, // Màu đỏ khi âm
                                  )),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  double _getProgressValue() {
    // Tính phần trăm dựa trên calories (logic mới: chỉ tăng khi dư calo)
    // leftValueForCircle = intakeCalories - outtakeCalories (calories hấp thụ - calories tiêu thụ)
    // Ví dụ: nếu tiêu thụ 800 và hấp thụ 500, thì leftValueForCircle = -300 (thiếu 300 calo)
    // progress = leftValueForCircle / dailyOuttakeGoalCalories
    // Logic mới: âm = 0%, dương = tính phần trăm bình thường

    final leftValueForCircle =
        _controller.intakeCalories.value - _controller.outtakeCalories.value;
    final goalCalories = _controller.dailyOuttakeGoalCalories.value;

    // Nếu không có mục tiêu calories, trả về 0
    if (goalCalories <= 0) {
      return 0.0;
    }

    // Logic mới: nếu âm (thiếu calo) thì luôn 0%, nếu dương (dư calo) thì tính phần trăm
    // Ví dụ: -300/1000 = 0% (màu đỏ), 200/1000 = 20% (màu xanh)
    final progress = leftValueForCircle < 0
        ? 0.0
        : (leftValueForCircle / goalCalories).clamp(0.0, 1.0);

    return progress;
  }

  Widget _buildFlameGrid(BuildContext context) {
    // Nếu rỗng, tạo 12 hình lửa mặc định (tất cả inactive)
    final List<bool> allDays = widget.completeDays.isEmpty
        ? List.filled(12, false)
        : widget.completeDays;

    // Chỉ lấy số lượng flame cần hiển thị
    final List<bool> visibleDays = allDays.take(_visibleFlameCount).toList();

    // Chia thành các hàng, mỗi hàng 6 cái
    const int itemsPerRow = 6;
    final int totalVisibleItems = visibleDays.length;
    final int rowCount = (totalVisibleItems / itemsPerRow).ceil();

    // Nếu chỉ có 2 hàng hoặc ít hơn, không cần scroll
    final bool needsScroll = rowCount > 2;
    final double gridHeight = needsScroll
        ? (rowCount * 68.0)
        : (rowCount * 68.0); // 45 + 16 padding + 7 spacing

    Widget gridWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rowCount, (rowIndex) {
        final int startIndex = rowIndex * itemsPerRow;
        final int endIndex = (startIndex + itemsPerRow < totalVisibleItems)
            ? startIndex + itemsPerRow
            : totalVisibleItems;

        return Padding(
          padding: EdgeInsets.only(
            bottom: rowIndex < rowCount - 1 ? 16.0 : 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(endIndex - startIndex, (colIndex) {
              final int index = startIndex + colIndex;
              final bool isCompleted = visibleDays[index];

              // Tính real-time cho ngày hiện tại
              final bool isCurrentDay = widget.currentDay != null &&
                  int.tryParse(widget.currentDay!) == (index + 1);
              final bool realTimeCompleted = isCurrentDay
                  ? (widget.intakeCalories - widget.outtakeCalories) >=
                      widget.goalCalories
                  : isCompleted;

              return Expanded(
                child: Center(
                  child: _buildFlameIcon(context, index + 1, realTimeCompleted),
                ),
              );
            }),
          ),
        );
      }),
    );

    // Nếu cần scroll, wrap trong SingleChildScrollView
    if (needsScroll) {
      return SizedBox(
        height: 136, // Chiều cao cho 2 hàng (68 * 2)
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            height: gridHeight,
            child: gridWidget,
          ),
        ),
      );
    } else {
      return SizedBox(
        height: gridHeight.clamp(0.0, 136.0),
        child: gridWidget,
      );
    }
  }

  Widget _buildFlameIcon(
      BuildContext context, int dayNumber, bool isCompleted) {
    // Màu cam cho completed, màu xám cho inactive
    final Color flameColor = isCompleted ? Colors.orange : Colors.grey.shade300;

    return SizedBox(
      width: 45,
      height: 45,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SvgPicture.asset(
            SVGAssetString.fire,
            width: 45,
            height: 45,
            color: flameColor,
          ),
          Positioned(
            top: 12,
            child: Text(
              '$dayNumber',
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
