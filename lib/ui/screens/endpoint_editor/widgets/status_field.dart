import 'package:flutter/material.dart';
import '../../../../core/theme/arbiter_tokens.dart';

/// HTTP status-code input with a colored status dot that tracks the value.
class StatusField extends StatelessWidget {
  const StatusField({
    super.key,
    required this.controller,
    this.onChanged,
    this.height = 46,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(t.radius - 1),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final code = int.tryParse(controller.text.trim()) ?? 0;
              return Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: t.statusColor(code),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: TextInputType.number,
              style: t.mono(size: 15, weight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
