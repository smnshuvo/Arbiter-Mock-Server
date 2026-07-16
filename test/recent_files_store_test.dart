import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:arbiter_mock_server/ui/screens/json_docs/recent_files_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  RecentFile mk(String path, {int openedAt = 0}) => RecentFile(
        path: path,
        name: path.split('/').last,
        size: 100,
        modified: 111,
        openedAt: openedAt,
      );

  test('RecentFile JSON round-trips', () {
    const f = RecentFile(
        path: 'content://x/1',
        name: 'a.json',
        size: 42,
        modified: 999,
        openedAt: 1234);
    final back = RecentFile.fromJson(f.toJson());
    expect(back.path, f.path);
    expect(back.name, 'a.json');
    expect(back.size, 42);
    expect(back.modified, 999);
    expect(back.openedAt, 1234);
  });

  test('add then list returns the entry', () async {
    final store = RecentFilesStore.instance;
    await store.add(mk('/a.json'));
    final items = await store.list();
    expect(items, hasLength(1));
    expect(items.first.name, 'a.json');
  });

  test('most-recent-first ordering', () async {
    final store = RecentFilesStore.instance;
    await store.add(mk('/a.json', openedAt: 1));
    await store.add(mk('/b.json', openedAt: 2));
    final items = await store.list();
    expect(items.map((e) => e.path), ['/b.json', '/a.json']);
  });

  test('re-adding the same path de-dupes and moves to front', () async {
    final store = RecentFilesStore.instance;
    await store.add(mk('/a.json'));
    await store.add(mk('/b.json'));
    await store.add(mk('/a.json')); // touch again
    final items = await store.list();
    expect(items, hasLength(2));
    expect(items.first.path, '/a.json');
  });

  test('caps the list length', () async {
    final store = RecentFilesStore.instance;
    for (var i = 0; i < 50; i++) {
      await store.add(mk('/f$i.json', openedAt: i));
    }
    final items = await store.list();
    expect(items.length, lessThanOrEqualTo(40));
    // Newest kept, oldest evicted.
    expect(items.first.path, '/f49.json');
    expect(items.any((e) => e.path == '/f0.json'), isFalse);
  });

  test('remove drops the entry', () async {
    final store = RecentFilesStore.instance;
    await store.add(mk('/a.json'));
    await store.add(mk('/b.json'));
    await store.remove('/a.json');
    final items = await store.list();
    expect(items.map((e) => e.path), ['/b.json']);
  });

  test('list tolerates corrupt storage', () async {
    SharedPreferences.setMockInitialValues({'json_recent_files': 'not json'});
    expect(await RecentFilesStore.instance.list(), isEmpty);
  });
}
