import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:lumino_app_moviestreaming/device_link_service.dart';
import 'package:lumino_app_moviestreaming/toast.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final barcode = capture.barcodes.first;
    final String? rawValue = barcode.rawValue;
    
    if (rawValue == null || !rawValue.startsWith('lumino-link:')) {
      // Ignore random QR codes
      return;
    }
    
    setState(() => _isProcessing = true);
    
    try {
      final parts = rawValue.split(':');
      if (parts.length != 3) {
        throw 'Invalid linking payload';
      }
      
      final sessionId = parts[1];
      final encryptionKey = parts[2];
      
      debugPrint('QrScannerPage: Authorizing session $sessionId');
      
      // Perform the authentication & encryption update on Supabase!
      final sessionRecord = await DeviceLinkService.authorizeSession(
        sessionId: sessionId,
        encryptionKey: encryptionKey,
      );
      
      if (mounted) {
        final childInfo = sessionRecord['child_device_info'] as Map<String, dynamic>?;
        final childOS = childInfo?['os'] ?? 'Device';
        
        Navigator.pop(context, childOS); // Return the linked child device name!
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'Scanning failed: $e',
          icon: Icons.error_outline_rounded,
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Scan QR Code',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // 1. Mobile Scanner View
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
          ),
          
          // 2. Beautiful QR Overlay Scanner Frame
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFFB561), width: 3),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB561).withValues(alpha: 0.1),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          
          // 3. Scan Guidance Text
          Positioned(
            bottom: 80,
            left: 24,
            right: 24,
            child: const Text(
              'Align the QR code on your TV or computer screen within the frame to link your account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          
          // 4. Processing overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFFFFB561),
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Authorizing & linking device...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
