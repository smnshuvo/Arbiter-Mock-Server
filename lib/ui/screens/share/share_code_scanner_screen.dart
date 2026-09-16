import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../data/datasources/share/share_code.dart';

/// Full-screen camera that pops with the first scanned QR holding a valid
/// [ShareCode]. Other QR codes are ignored (with a hint) so pointing at the
/// wrong one never starts a bogus connection. Android/iOS only.
class ShareCodeScannerScreen extends StatefulWidget {
  const ShareCodeScannerScreen({super.key});

  @override
  State<ShareCodeScannerScreen> createState() => _ShareCodeScannerScreenState();
}

class _ShareCodeScannerScreenState extends State<ShareCodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  bool _sawForeignCode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      if (ShareCode.decode(raw) != null) {
        _done = true;
        Navigator.pop(context, raw);
        return;
      }
      if (!_sawForeignCode) setState(() => _sawForeignCode = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan share code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera access is off. Allow it in system settings, or type the code instead.'
                      : 'The camera could not start (${error.errorCode.name}). Type the code instead.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: t.accent, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              _sawForeignCode
                  ? "That QR code isn't an Arbiter share code."
                  : 'Point the camera at the QR code on the sharing device.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
