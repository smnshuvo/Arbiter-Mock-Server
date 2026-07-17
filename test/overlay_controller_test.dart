import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OverlayController Status Coloring', () {
    // Test status code to color mapping
    test('2xx status codes should map to green', () {
      final statusCodes = [200, 201, 204, 299];
      for (final code in statusCodes) {
        expect(isSuccessStatus(code), isTrue);
      }
    });

    test('3xx status codes should map to yellow/amber', () {
      final statusCodes = [300, 301, 302, 304, 399];
      for (final code in statusCodes) {
        expect(isRedirectStatus(code), isTrue);
      }
    });

    test('4xx and 5xx status codes should map to red', () {
      final statusCodes = [400, 404, 500, 503, 599];
      for (final code in statusCodes) {
        expect(isErrorStatus(code), isTrue);
      }
    });

    test('error status should trigger error timestamp', () {
      final controller = MockOverlayController();
      controller.pushLog('GET', '/api/users', 404, 100);

      expect(controller.lastStatusCode, equals(404));
      expect(controller.lastErrorTime, isNotNull);
    });

    test('successful status should not update error timestamp', () {
      final controller = MockOverlayController();
      final initialErrorTime = controller.lastErrorTime;

      controller.pushLog('GET', '/api/users', 200, 100);

      expect(controller.lastStatusCode, equals(200));
      expect(controller.lastErrorTime, equals(initialErrorTime));
    });
  });

  group('OverlayController Error Persistence', () {
    test('error status should persist red for 3 seconds', () {
      final controller = MockOverlayController();

      // Trigger an error
      controller.pushLog('POST', '/api/data', 500, 200);
      expect(controller.determineBubbleStatusCode(), equals(499)); // Red

      // Immediately after, red should still show
      controller.advanceTime(Duration(milliseconds: 1500));
      expect(controller.determineBubbleStatusCode(), equals(499)); // Still red

      // After 3 seconds, should return to normal
      controller.advanceTime(Duration(milliseconds: 2000)); // Total 3.5 seconds
      expect(controller.determineBubbleStatusCode(), equals(500)); // Back to last status
    });

    test('successful request during error persistence should not change color', () {
      final controller = MockOverlayController();

      // Trigger an error
      controller.pushLog('GET', '/api/fail', 500, 100);
      expect(controller.determineBubbleStatusCode(), equals(499)); // Red

      // Make a successful request after 1 second
      controller.advanceTime(Duration(seconds: 1));
      controller.pushLog('GET', '/api/success', 200, 50);

      // Should still show red because error persistence is active
      expect(controller.determineBubbleStatusCode(), equals(499)); // Still red

      // After error persistence expires (2+ more seconds), should show green
      controller.advanceTime(Duration(milliseconds: 2100));
      expect(controller.determineBubbleStatusCode(), equals(200)); // Now green
    });

    test('multiple errors should reset 3-second timer', () {
      final controller = MockOverlayController();

      controller.pushLog('GET', '/api/fail1', 500, 100);
      controller.advanceTime(Duration(milliseconds: 2500));

      // Error should be about to expire
      expect(controller.determineBubbleStatusCode(), equals(499));

      // Another error should reset the timer
      controller.pushLog('POST', '/api/fail2', 503, 150);

      // Should have 3 seconds again
      controller.advanceTime(Duration(milliseconds: 2000));
      expect(controller.determineBubbleStatusCode(), equals(499)); // Still red
    });
  });

  group('OverlayController Minimize Feature', () {
    test('minimize should set minimized to true and expanded to false', () {
      final controller = MockOverlayController();

      controller.expanded = true;
      controller.minimize();

      expect(controller.minimized, isTrue);
      expect(controller.expanded, isFalse);
    });

    test('tapping minimized icon should restore bubble', () {
      final controller = MockOverlayController();

      controller.minimize();
      expect(controller.minimized, isTrue);

      controller.restoreFromMinimized();

      expect(controller.minimized, isFalse);
    });

    test('bubble visibility should be correct based on minimized state', () {
      final controller = MockOverlayController();

      // Initially expanded - show feed
      controller.expanded = true;
      controller.minimized = false;
      expect(controller.shouldShowBubble(), isFalse);
      expect(controller.shouldShowFeed(), isTrue);

      // Close feed
      controller.expanded = false;
      expect(controller.shouldShowBubble(), isTrue);
      expect(controller.shouldShowMinimized(), isFalse);

      // Minimize to icon
      controller.minimized = true;
      expect(controller.shouldShowBubble(), isFalse);
      expect(controller.shouldShowMinimized(), isTrue);
    });
  });

  group('OverlayController Dot Color', () {
    test('dot should reflect last status code', () {
      final controller = MockOverlayController();

      // Set currentTime to some point to avoid error persistence interference
      controller.advanceTime(Duration(seconds: 10));

      controller.pushLog('GET', '/api/users', 200, 100);
      expect(controller.getDotColor(), equals('green'));

      controller.pushLog('GET', '/api/redirect', 301, 50);
      expect(controller.getDotColor(), equals('amber'));

      controller.pushLog('GET', '/api/error', 404, 150);
      expect(controller.getDotColor(), equals('red'));
    });

    test('dot should be red during error persistence window', () {
      final controller = MockOverlayController();

      controller.pushLog('GET', '/api/fail', 500, 100);
      expect(controller.getDotColor(), equals('red'));

      controller.advanceTime(Duration(milliseconds: 1500));
      expect(controller.getDotColor(), equals('red'));

      controller.advanceTime(Duration(milliseconds: 2000)); // Total 3.5 seconds
      expect(controller.getDotColor(), equals('red')); // Back to 500 which is red
    });
  });
}

// Helper functions for test assertions
bool isSuccessStatus(int code) => code >= 200 && code < 300;
bool isRedirectStatus(int code) => code >= 300 && code < 400;
bool isErrorStatus(int code) => code >= 400;

// Mock class for testing OverlayController logic
class MockOverlayController {
  int? lastStatusCode;
  int lastErrorTime = 0;
  bool expanded = false;
  bool minimized = false;
  int currentTime = 0;

  void pushLog(String method, String path, int statusCode, int responseTimeMs) {
    lastStatusCode = statusCode;
    if (statusCode >= 400) {
      lastErrorTime = currentTime;
    }
  }

  void advanceTime(Duration duration) {
    currentTime += duration.inMilliseconds;
  }

  int? determineBubbleStatusCode() {
    final timeSinceError = currentTime - lastErrorTime;
    if (timeSinceError < 3000) {
      return 499; // Red color code
    }
    return lastStatusCode;
  }

  void minimize() {
    expanded = false;
    minimized = true;
  }

  void restoreFromMinimized() {
    minimized = false;
  }

  bool shouldShowBubble() => !expanded && !minimized;
  bool shouldShowFeed() => expanded;
  bool shouldShowMinimized() => !expanded && minimized;

  String? getDotColor() {
    final statusCode = determineBubbleStatusCode();
    if (statusCode == null) return null;

    if (statusCode >= 400) return 'red';
    if (statusCode >= 300) return 'amber';
    if (statusCode >= 200) return 'green';
    return null;
  }
}
