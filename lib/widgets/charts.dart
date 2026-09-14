import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Small bar chart without extra packages.
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({super.key, required this.values, required this.labels, this.height = 120});

  final List<double> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final peak = values.fold<double>(0, math.max);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: peak == 0 ? 4 : 4 + (values[i] / peak) * (height - 26),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        colors: [AppColors.teal, AppColors.primary],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(labels[i], style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class DonutProgress extends StatelessWidget {
  const DonutProgress({super.key, required this.value, required this.center, this.size = 104});

  final double value;
  final String center;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value.clamp(0, 1).toDouble(),
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          Text(center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ],
      ),
    );
  }
}
