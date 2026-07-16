import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arbiter_mock_server/core/services/json_document_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('arbiter/json_docs');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mock(Future<Object?> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  final svc = JsonDocumentService.instance;

  group('JsonDocumentService', () {
    test('read invokes readFile with the path', () async {
      mock((c) async => '{"a":1}');
      expect(await svc.read('/x.json'), '{"a":1}');
      expect(calls.single.method, 'readFile');
      expect(calls.single.arguments, {'path': '/x.json'});
    });

    test('write invokes writeFile and returns the bool', () async {
      mock((c) async => true);
      expect(await svc.write('/x.json', '{}'), isTrue);
      expect(calls.single.arguments, {'path': '/x.json', 'content': '{}'});
    });

    test('write returns false when native returns null', () async {
      mock((c) async => null);
      expect(await svc.write('/x.json', '{}'), isFalse);
    });

    test('displayName returns the native name', () async {
      mock((c) async => 'nice.json');
      expect(await svc.displayName('content://x/1'), 'nice.json');
    });

    test('displayName falls back to the last path segment', () async {
      mock((c) async => null);
      expect(await svc.displayName('/a/b/c.json'), 'c.json');
    });

    test('fileInfo parses name/size/modified', () async {
      mock((c) async => {'name': 'f.json', 'size': 123, 'modified': 999});
      final info = await svc.fileInfo('/f.json');
      expect(info.name, 'f.json');
      expect(info.size, 123);
      expect(info.modified, 999);
    });

    test('fileInfo tolerates missing fields', () async {
      mock((c) async => {'name': 'f.json'});
      final info = await svc.fileInfo('/f.json');
      expect(info.size, isNull);
      expect(info.modified, isNull);
    });

    test('getPending returns the native list', () async {
      mock((c) async => ['/a.json', '/b.json']);
      expect(await svc.getPending(), ['/a.json', '/b.json']);
    });
  }, skip: JsonDocumentService.isSupported ? false : 'requires macOS/Android host');
}
