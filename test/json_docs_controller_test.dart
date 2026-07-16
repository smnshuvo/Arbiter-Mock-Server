import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:arbiter_mock_server/core/services/json_document_service.dart';
import 'package:arbiter_mock_server/ui/screens/json_docs/json_docs_controller.dart';
import 'package:arbiter_mock_server/ui/screens/json_docs/recent_files_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('arbiter/json_docs');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final controller = JsonDocsController.instance;

  String? fileContent;
  bool writeResult = true;

  void resetController() {
    while (!controller.isEmpty) {
      controller.close(0);
    }
    controller.singleDocument = false;
    controller.activeIndex = 0;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fileContent = '{"a":1}';
    writeResult = true;
    resetController();
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readFile':
          return fileContent;
        case 'displayName':
          return 'doc.json';
        case 'fileInfo':
          return {'name': 'doc.json', 'size': 10, 'modified': 5};
        case 'writeFile':
          return writeResult;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    resetController();
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('JsonDocsController', () {
    test('openPath adds a document with content + title', () async {
      final ok = await controller.openPath('/a.json');
      expect(ok, isTrue);
      expect(controller.docs, hasLength(1));
      expect(controller.active!.title, 'doc.json');
      expect(controller.active!.controller.text, '{"a":1}');
      expect(controller.active!.dirty, isFalse);
    });

    test('opening the same path activates it without duplicating', () async {
      await controller.openPath('/a.json');
      await controller.openPath('/a.json');
      expect(controller.docs, hasLength(1));
    });

    test('multi-doc mode keeps several tabs', () async {
      await controller.openPath('/a.json');
      await controller.openPath('/b.json');
      expect(controller.docs, hasLength(2));
      expect(controller.activeIndex, 1);
    });

    test('singleDocument mode replaces the open document', () async {
      controller.singleDocument = true;
      await controller.openPath('/a.json');
      await controller.openPath('/b.json');
      expect(controller.docs, hasLength(1));
      expect(controller.active!.path, '/b.json');
    });

    test('singleDocument mode records a recent file', () async {
      controller.singleDocument = true;
      await controller.openPath('content://x/1');
      final recents = await RecentFilesStore.instance.list();
      expect(recents.map((e) => e.path), contains('content://x/1'));
      expect(recents.first.name, 'doc.json');
    });

    test('openPath returns false when the read fails (singleDocument)', () async {
      controller.singleDocument = true;
      fileContent = null;
      final ok = await controller.openPath('content://gone');
      expect(ok, isFalse);
      expect(controller.isEmpty, isTrue);
    });

    test('editing marks dirty; save clears it', () async {
      await controller.openPath('/a.json');
      final doc = controller.active!;
      doc.controller.text = '{"a":2}';
      expect(doc.dirty, isTrue);
      expect(await controller.save(doc), isTrue);
      expect(doc.dirty, isFalse);
    });

    test('close removes the document', () async {
      await controller.openPath('/a.json');
      controller.close(0);
      expect(controller.isEmpty, isTrue);
    });
  }, skip: JsonDocumentService.isSupported ? false : 'requires macOS/Android host');
}
