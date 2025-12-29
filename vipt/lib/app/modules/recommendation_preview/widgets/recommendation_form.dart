import 'package:flutter/material.dart';
// ignore: unused_import
import 'package:get/get.dart';
import 'package:vipt/app/core/values/colors.dart';
// ignore: unused_import
import 'package:vipt/app/core/values/values.dart';
import 'package:vipt/app/modules/recommendation_preview/recommendation_preview_controller.dart';

class RecommendationForm extends StatefulWidget {
  final RecommendationPreviewController controller;
  const RecommendationForm({Key? key, required this.controller})
      : super(key: key);

  @override
  State<RecommendationForm> createState() => _RecommendationFormState();
}

class _RecommendationFormState extends State<RecommendationForm> {
  int _planDays = 7;
  int _mealsPerDay = 3;
  int _exercisesPerDay = 3;
  DateTime? _startDate;
  String _goal = 'Duy trì';

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColor.primaryColor.withOpacity(0.18),
          width: 1.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: AppColor.primaryColor, size: 22),
                const SizedBox(width: 12),
                Text(
                  'Tùy chỉnh lộ trình',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Plan days selector
            _buildLabeledRow(
              context,
              'Số ngày',
              _styledDropdown<int>(
                context: context,
                value: _planDays,
                items: [7, 14, 21, 28],
                onChanged: (v) => setState(() => _planDays = v ?? 7),
              ),
            ),
            const SizedBox(height: 8),

            // Meals per day & Exercises per day
            Row(
              children: [
                Expanded(
                  child: _buildLabeledRow(
                    context,
                    'Bữa / ngày',
                    _styledDropdown<int>(
                      context: context,
                      value: _mealsPerDay,
                      items: [1, 2, 3, 4, 5],
                      onChanged: (v) => setState(() => _mealsPerDay = v ?? 3),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildLabeledRow(
                    context,
                    'Bài / ngày',
                    _styledDropdown<int>(
                      context: context,
                      value: _exercisesPerDay,
                      items: [1, 2, 3, 4, 5],
                      onChanged: (v) => setState(() => _exercisesPerDay = v ?? 3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Start date and goal
            Row(
              children: [
                Expanded(
                  child: _buildLabeledRow(
                    context,
                    'Bắt đầu',
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _startDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _startDate = picked);
                      },
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                              color: AppColor.primaryColor.withOpacity(0.06)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _startDate == null
                              ? 'Tự động'
                              : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildLabeledRow(
                    context,
                    'Mục tiêu',
                    _styledDropdown<String>(
                      context: context,
                      value: _goal,
                      items: ['Giảm cân', 'Duy trì', 'Tăng cân'],
                      onChanged: (v) => setState(() => _goal = v ?? 'Duy trì'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // Reset to defaults
                      setState(() {
                        _planDays = 7;
                        _mealsPerDay = 3;
                        _exercisesPerDay = 3;
                        _startDate = null;
                        _goal = 'Duy trì';
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColor.primaryColor, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: AppColor.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Hủy', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      // Create or extend plan using selected options
                      // Always create default 7-day plan per requirement.
                      await widget.controller.deleteAndCreateNew7DayPlan(
                          mealsPerDay: _mealsPerDay,
                          exercisesPerDay: _exercisesPerDay,
                          navigateHome: false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Tạo lộ trình'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Reusable styled dropdown container + DropdownButton
  Widget _styledDropdown<T>({
    required BuildContext context,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColor.primaryColor.withOpacity(0.06)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<T>(
        value: value,
        items: items
            .map((v) => DropdownMenuItem(value: v, child: Text('$v', style: TextStyle(fontWeight: FontWeight.w600))))
            .toList(),
        onChanged: onChanged,
        underline: const SizedBox.shrink(),
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        iconEnabledColor: AppColor.primaryColor,
      ),
    );
  }

  Widget _buildLabeledRow(BuildContext context, String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}


