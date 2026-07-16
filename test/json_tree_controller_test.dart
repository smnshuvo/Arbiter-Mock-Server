import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:arbiter_mock_server/ui/screens/endpoint_editor/widgets/json_tree_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late JsonTreeController c;
  setUp(() => c = JsonTreeController());

  JsonNode childNamed(JsonNode parent, String key) =>
      parent.children.firstWhere((n) => n.key == key);

  group('parse + flatten', () {
    test('flat object yields one row per key plus a root add row', () async {
      await c.parse('{"a":1,"b":"x"}');
      expect(c.rows.where((r) => r.kind == JsonRowKind.node).length, 2);
      expect(c.rows.last.kind, JsonRowKind.rootAdd);
      expect(c.isDirty, isFalse);
    });

    test('nested containers add an inline addChild row when expanded', () async {
      await c.parse('{"o":{"k":1}}');
      final kinds = c.rows.map((r) => r.kind).toList();
      // o (node), k (node), addChild for o, rootAdd
      expect(kinds, [
        JsonRowKind.node,
        JsonRowKind.node,
        JsonRowKind.addChild,
        JsonRowKind.rootAdd,
      ]);
    });

    test('depth is tracked for guides/indent', () async {
      await c.parse('{"o":{"p":{"q":1}}}');
      final q = c.rows.firstWhere((r) => r.node.key == 'q');
      expect(q.depth, 2);
    });

    test('array children are marked as array items with indices', () async {
      await c.parse('{"list":[10,20]}');
      final items =
          c.rows.where((r) => r.kind == JsonRowKind.node && r.isArrayItem).toList();
      expect(items.map((e) => e.index), [0, 1]);
    });

    test('collapsed subtrees are not emitted', () async {
      await c.parse('{"o":{"k":1}}');
      final o = childNamed(c.root, 'o');
      c.toggleCollapse(o);
      expect(c.rows.any((r) => r.node.key == 'k'), isFalse);
      c.toggleCollapse(o);
      expect(c.rows.any((r) => r.node.key == 'k'), isTrue);
    });

    test('invalid JSON falls back to an empty object', () async {
      await c.parse('not json');
      expect(c.root.type, JsonType.object);
      expect(c.root.children, isEmpty);
    });

    test('row keys are stable and unique per kind+node', () async {
      await c.parse('{"o":{"k":1}}');
      final keys = c.rows.map((r) => r.widgetKey).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  group('serialize on demand', () {
    test('round-trips types', () async {
      const src = '{"s":"x","n":2,"b":true,"nil":null,"o":{"k":1},"a":[1,2]}';
      await c.parse(src);
      expect(jsonDecode(c.toJsonSync()), jsonDecode(src));
    });

    test('reflects edits', () async {
      await c.parse('{"a":1}');
      c.setValue(childNamed(c.root, 'a'), '5');
      expect(jsonDecode(c.toJsonSync()), {'a': 5});
    });

    test('async toJson matches sync', () async {
      await c.parse('{"a":[1,{"b":"c"}]}');
      expect(await c.toJson(), c.toJsonSync());
    });

    test('numbers coerce, invalid numbers become 0', () async {
      await c.parse('{"n":1}');
      c.setValue(childNamed(c.root, 'n'), 'abc');
      expect(jsonDecode(c.toJsonSync()), {'n': 0});
    });
  });

  group('dirty tracking', () {
    test('onDirty fires once, not per keystroke', () async {
      await c.parse('{"a":1}');
      var fired = 0;
      c.onDirty = () => fired++;
      final a = childNamed(c.root, 'a');
      c.setValue(a, '1');
      c.setValue(a, '12');
      c.setValue(a, '123');
      expect(fired, 1);
      expect(c.isDirty, isTrue);
    });

    test('markSaved clears dirty and re-arms onDirty', () async {
      await c.parse('{"a":1}');
      var fired = 0;
      c.onDirty = () => fired++;
      c.setValue(childNamed(c.root, 'a'), '2');
      c.markSaved();
      expect(c.isDirty, isFalse);
      c.setValue(childNamed(c.root, 'a'), '3');
      expect(fired, 2);
    });

    test('text edits do not notify listeners (no list rebuild)', () async {
      await c.parse('{"a":1}');
      var notified = 0;
      c.addListener(() => notified++);
      c.setValue(childNamed(c.root, 'a'), '9');
      c.setKey(childNamed(c.root, 'a'), 'aa');
      expect(notified, 0);
    });

    test('structural edits notify', () async {
      await c.parse('{"a":1}');
      var notified = 0;
      c.addListener(() => notified++);
      c.addChild(c.root);
      expect(notified, 1);
    });

    test('collapsing does not dirty the document', () async {
      await c.parse('{"o":{"k":1}}');
      c.toggleCollapse(childNamed(c.root, 'o'));
      expect(c.isDirty, isFalse);
    });

    test('setKey invalidates the cached key width', () async {
      await c.parse('{"a":1}');
      final a = childNamed(c.root, 'a');
      a.keyWidthCache = 42;
      c.setKey(a, 'abc');
      expect(a.keyWidthCache, isNull);
    });
  });

  group('structural edits', () {
    test('addChild appends a string node and expands the parent', () async {
      await c.parse('{"o":{"k":1}}');
      final o = childNamed(c.root, 'o');
      c.toggleCollapse(o);
      c.addChild(o);
      expect(o.collapsed, isFalse);
      expect(o.children, hasLength(2));
      expect(o.children.last.type, JsonType.string);
    });

    test('duplicate deep-copies with fresh ids, inserted after the original',
        () async {
      await c.parse('{"a":{"x":1}}');
      final a = childNamed(c.root, 'a');
      c.duplicate(c.root, a);
      expect(c.root.children, hasLength(2));
      final copy = c.root.children[1];
      expect(copy.id, isNot(a.id));
      expect(copy.children.first.key, 'x');
      expect(copy.children.first.id, isNot(a.children.first.id));
    });

    test('remove drops the node', () async {
      await c.parse('{"a":1,"b":2}');
      c.remove(c.root, childNamed(c.root, 'a'));
      expect(c.root.children.map((e) => e.key), ['b']);
    });

    test('changing a container to a scalar drops its children', () async {
      await c.parse('{"o":{"k":1}}');
      final o = childNamed(c.root, 'o');
      c.changeType(o, JsonType.string);
      expect(o.children, isEmpty);
      expect(c.rows.any((r) => r.node.key == 'k'), isFalse);
    });

    test('changing to bool defaults a non-bool value to true', () async {
      await c.parse('{"a":"hello"}');
      final a = childNamed(c.root, 'a');
      c.changeType(a, JsonType.boolean);
      expect(a.value, 'true');
      expect(jsonDecode(c.toJsonSync()), {'a': true});
    });
  });

  group('smart collapse', () {
    test('small documents stay expanded', () async {
      await c.parse('{"o":{"k":1}}');
      expect(childNamed(c.root, 'o').collapsed, isFalse);
    });

    test('large documents collapse below the root', () async {
      // > largeDocNodes nodes: each entry is an object with one key.
      final big = {
        for (var i = 0; i < JsonTreeController.largeDocNodes; i++)
          'k$i': {'inner': i}
      };
      await c.parse(jsonEncode(big));
      expect(c.root.collapsed, isFalse, reason: 'root itself stays open');
      expect(c.root.children.every((n) => n.collapsed), isTrue);
      // Only the root's keys (+ root add row) are visible.
      expect(c.rows.where((r) => r.kind == JsonRowKind.node).length,
          JsonTreeController.largeDocNodes);
    });
  });
}
