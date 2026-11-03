import 'package:flutter/material.dart';

import '../data.dart';

Future<bool> confirmAdminBulkDelete(
  BuildContext context, {
  required int count,
  required String nounSingular,
  required String nounPlural,
}) async {
  if (count <= 0) return false;
  final noun = count == 1 ? nounSingular : nounPlural;
  final label = 'Delete $count $noun';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$label?'),
      content: Text(
        'Are you sure you want to delete these $count selected $noun? '
        'This action cannot be undone.',
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade500,
            foregroundColor: Colors.white,
          ),
          child: Text(label),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class AdminBulkSelectionBar extends StatelessWidget {
  const AdminBulkSelectionBar({
    super.key,
    required this.selectedCount,
    required this.totalVisible,
    required this.nounPlural,
    required this.onSelectAllVisible,
    required this.onClear,
    required this.onDelete,
    this.deleting = false,
    this.selectAllChecked = false,
    this.selectAllTristate,
    this.alignEnd = false,
    this.compact = false,
  });

  final int selectedCount;
  final int totalVisible;
  final String nounPlural;
  final VoidCallback onSelectAllVisible;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final bool deleting;
  final bool selectAllChecked;
  final bool? selectAllTristate;
  final bool alignEnd;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final allLabel = compact
        ? 'Select all'
        : totalVisible == 0
            ? 'Select all'
            : 'Select all ($totalVisible on this list)';
    final bar = Container(
      width: alignEnd ? null : double.infinity,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
          : const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: compact
          ? null
          : BoxDecoration(
              color: selectedCount > 0
                  ? const Color(0xFFFFF1E6)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selectedCount > 0
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : const Color(0xFFE2E8F0),
              ),
            ),
      child: Wrap(
        alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                tristate: true,
                value: selectAllTristate ?? (selectAllChecked ? true : false),
                onChanged: totalVisible == 0
                    ? null
                    : (_) => onSelectAllVisible(),
              ),
              Text(
                allLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (!compact || selectedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$selectedCount $nounPlural selected',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.textDark,
                ),
              ),
            ),
          if (!compact || selectedCount > 0)
            TextButton(onPressed: onClear, child: const Text('Clear selection')),
          if (!compact || selectedCount > 0)
            FilledButton.icon(
              onPressed: selectedCount == 0 || deleting ? null : onDelete,
              icon: deleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_outline, size: 18),
              label: Text(deleting ? 'Deleting...' : 'Delete selected'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade500,
                minimumSize: const Size(44, 40),
              ),
            ),
        ],
      ),
    );
    if (!alignEnd) return bar;
    return Align(alignment: Alignment.centerRight, child: bar);
  }
}
