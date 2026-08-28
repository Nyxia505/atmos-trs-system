import 'package:flutter/material.dart';

/// Shimmer-free placeholder blocks for progressive loading.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class SkeletonStatCardsRow extends StatelessWidget {
  const SkeletonStatCardsRow({super.key, this.count = 2});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 4, right: i == count - 1 ? 0 : 4),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(width: 20, height: 20, borderRadius: 4),
                  SizedBox(height: 6),
                  SkeletonBox(width: 44, height: 10),
                  SizedBox(height: 4),
                  SkeletonBox(width: 20, height: 14),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class SkeletonListTiles extends StatelessWidget {
  const SkeletonListTiles({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                SkeletonBox(width: 50, height: 50, borderRadius: 10),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 140, height: 14),
                      SizedBox(height: 8),
                      SkeletonBox(width: 90, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class DashboardContentSkeleton extends StatelessWidget {
  const DashboardContentSkeleton({super.key, this.accent});

  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Colors.grey.shade300;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 28, borderRadius: 8)),
              const SizedBox(width: 12),
              SkeletonBox(width: 100, height: 36, borderRadius: 18),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 12 : 0),
                  child: Container(
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                    ),
                    child: const Center(
                      child: SkeletonBox(width: 48, height: 24, borderRadius: 6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SkeletonBox(height: 200, borderRadius: 12),
          const SizedBox(height: 16),
          const SkeletonListTiles(count: 3),
        ],
      ),
    );
  }
}
