import 'package:flutter/material.dart';

import '../../../../core/theme/arbiter_tokens.dart';
import 'json_row_tile.dart';
import 'json_tree_controller.dart';

/// Builds one visible line of the tree. Shared by the box and sliver renderers
/// so both stay in lockstep.
Widget _buildRow(
    BuildContext context, JsonTreeController controller, JsonRow row) {
  final t = ArbTokens.of(context);
  switch (row.kind) {
    case JsonRowKind.node:
      return JsonRowTile(
        key: row.widgetKey,
        row: row,
        controller: controller,
        isRoot: row.node == controller.root,
      );
    case JsonRowKind.addChild:
      return Padding(
        key: row.widgetKey,
        padding: EdgeInsets.only(left: 14.0 * row.depth + 8, top: 2, bottom: 2),
        child: CustomPaint(
          painter:
              JsonGuidesPainter(depth: row.depth, colorFor: (i) => t.depthColor(i)),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => controller.addChild(row.node),
              icon: Icon(Icons.add, size: 14, color: t.textSecondary),
              label: Text(
                row.node.type == JsonType.array ? 'Add item' : 'Add field',
                style: t.sans(
                    size: 11, weight: FontWeight.w700, color: t.textSecondary),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
      );
    case JsonRowKind.rootAdd:
      return Padding(
        key: row.widgetKey,
        padding: const EdgeInsets.only(top: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusSm),
          onTap: () => controller.addChild(row.node),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radiusSm),
              border: Border.all(color: t.border, width: 1.5),
            ),
            child: Center(
              child: Text(
                row.node.type == JsonType.array ? '＋ Add item' : '＋ Add field',
                style: t.sans(
                    size: 12, weight: FontWeight.w700, color: t.textSecondary),
              ),
            ),
          ),
        ),
      );
  }
}

BoxDecoration _frame(ArbTokens t) => BoxDecoration(
      color: t.surface,
      border: Border.all(color: t.border),
      borderRadius: BorderRadius.circular(t.radius),
    );

/// A visual JSON tree editor over a [JsonTreeController].
///
/// Renders only the rows currently on screen (`ListView.builder` over the
/// controller's flattened row list), so document size no longer drives build
/// cost. Expects a bounded height — put it in an `Expanded`. Inside a
/// `CustomScrollView`, use [JsonFormEditorSliver] instead.
class JsonFormEditor extends StatelessWidget {
  const JsonFormEditor({super.key, required this.controller});

  final JsonTreeController controller;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final rows = controller.rows;
        return Container(
          decoration: _frame(t),
          padding: const EdgeInsets.all(11),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            itemBuilder: (context, i) => _buildRow(context, controller, rows[i]),
          ),
        );
      },
    );
  }
}

/// Sliver form of [JsonFormEditor], so the endpoint editor's page can scroll as
/// one surface while still building only the visible rows.
class JsonFormEditorSliver extends StatelessWidget {
  const JsonFormEditorSliver({super.key, required this.controller});

  final JsonTreeController controller;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final rows = controller.rows;
        return DecoratedSliver(
          decoration: _frame(t),
          sliver: SliverPadding(
            padding: const EdgeInsets.all(11),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) =>
                  _buildRow(context, controller, rows[i]),
            ),
          ),
        );
      },
    );
  }
}
