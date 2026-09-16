import 'package:arbiter_mock_server/data/repositories/saved_base_url_repository_impl.dart';
import 'package:arbiter_mock_server/domain/entities/saved_base_url.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SavedBaseUrlRepositoryImpl repo;
  late DateTime clock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 1, 1);
    repo = SavedBaseUrlRepositoryImpl(await SharedPreferences.getInstance(), now: () {
      clock = clock.add(const Duration(minutes: 1));
      return clock;
    });
  });

  test('saved URLs come back most recently used first', () async {
    await repo.save('https://staging.example.com', 'Staging');
    await repo.save('https://prod.example.com', 'Prod');
    expect(repo.getAll().map((e) => e.name), ['Prod', 'Staging']);

    await repo.markUsed('https://staging.example.com');
    expect(repo.getAll().map((e) => e.name), ['Staging', 'Prod']);
  });

  test('trailing slash and whitespace match the same entry; save renames', () async {
    await repo.save('https://api.example.com/', 'API');
    expect(repo.find('  https://api.example.com ')?.name, 'API');

    await repo.save('https://api.example.com', 'Renamed');
    expect(repo.getAll(), hasLength(1));
    expect(repo.getAll().single.name, 'Renamed');
  });

  test('markUsed ignores unsaved URLs; delete removes', () async {
    await repo.markUsed('https://nope.example.com');
    expect(repo.getAll(), isEmpty);

    await repo.save('https://a.example.com', 'A');
    await repo.delete('https://a.example.com/');
    expect(repo.getAll(), isEmpty);
  });

  test('name suggestion uses the host', () {
    expect(SavedBaseUrl.suggestName('https://api.example.com/v1'), 'api.example.com');
  });
}
