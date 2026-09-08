import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../logic/receipt_parser.dart';
import '../../logic/receipt_validator.dart';
import '../../services/ai_receipt_service.dart';
import '../../services/ocr_service.dart';
import '../create/manual_entry_screen.dart';
import 'review_scanned_screen.dart';

/// FR-2.1/FR-2.2: capture or pick a receipt photo, then read it.
///
/// Reading is AI-first: the photo is sent to the backend relay's
/// `/api/parse-receipt`, which has Gemini read it directly — this is a
/// deliberate product decision (confirmed 2026-09-04) trading the "OCR
/// never leaves the device" property for materially better accuracy, since
/// on-device OCR mistakes can't be recovered by anything downstream. If
/// the relay isn't configured/reachable, this falls back to the on-device
/// ML Kit OCR + regex parser so scanning still works without a network
/// connection, just less precisely.
///
/// Uses `image_picker` rather than a custom live camera view — it covers
/// "take a photo directly or pick one from the gallery" with far less
/// platform-specific surface area to get wrong, at the cost of the
/// mockup's live auto-detect viewfinder framing.
class ScanReceiptScreen extends StatefulWidget {
  const ScanReceiptScreen({super.key});

  @override
  State<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends State<ScanReceiptScreen> {
  final ImagePicker _picker = ImagePicker();
  /// Created on demand, never on the web: constructing and disposing the
  /// ML Kit recognizer touches a platform channel that only exists on
  /// Android and iOS.
  OcrService? _ocrService;
  final AiReceiptService _aiReceiptService = AiReceiptService(
    relayBaseUrl: const String.fromEnvironment('SPLITYUK_RELAY_URL'),
  );
  bool _isProcessing = false;
  String? _error;

  @override
  void dispose() {
    _ocrService?.dispose();
    super.dispose();
  }

  /// The relay already retries Gemini internally, but its whole budget can
  /// still be spent by one overloaded model. One more attempt from here
  /// costs a few seconds and is worth far more than the on-device reader's
  /// output, which regularly mistakes a loyalty code for a purchase.
  Future<AiReceiptOutcome> _readWithAi(Uint8List bytes, String filename) async {
    var outcome = await _aiReceiptService.parseReceipt(bytes, filename: filename);

    // Only a transient failure is worth repeating — an unconfigured relay
    // will fail identically however many times it is asked.
    if (!outcome.succeeded && _aiReceiptService.isConfigured) {
      outcome = await _aiReceiptService.parseReceipt(bytes, filename: filename);
    }
    return outcome;
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final photo = await _picker.pickImage(source: source, imageQuality: 90);
      if (photo == null) {
        setState(() => _isProcessing = false);
        return;
      }
      await _readPhoto(photo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = 'Could not read that photo. Try again, or enter the bill manually.';
      });
    }
  }

  /// Reads an already-captured photo. Separate from picking it so the
  /// review screen's retry can re-read *this* photo rather than sending
  /// the user back to the camera for a new one.
  Future<void> _readPhoto(XFile photo) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      // Read once, in memory. Nothing downstream needs to re-open the
      // file, which is what lets the identical code path run on the web
      // where there is no filesystem at all.
      final bytes = await photo.readAsBytes();

      ParsedReceipt? parsed;
      var readSource = ReceiptReadSource.ai;

      final aiOutcome = await _readWithAi(bytes, photo.name);
      if (aiOutcome.succeeded) {
        if (!aiOutcome.isReceipt) {
          if (!mounted) return;
          setState(() {
            _isProcessing = false;
            _error = aiOutcome.reason;
          });
          return;
        }
        parsed = aiOutcome.parsed;
      } else {
        // AI relay unreachable/not configured — fall back to on-device OCR
        // rather than blocking the scan entirely. The review screen is
        // told, because this result is far weaker and must not be
        // presented as if the AI had produced it.
        readSource = ReceiptReadSource.onDevice;
        if (kIsWeb) {
          // ML Kit is a mobile-only plugin, so on the web there is no
          // second reader to fall back to. Say that plainly instead of
          // crashing on a platform channel that isn't there.
          if (!mounted) return;
          setState(() {
            _isProcessing = false;
            _error = aiOutcome.error ??
                'The AI reader could not be reached. Check your connection and try again, '
                    'or enter the bill manually.';
          });
          return;
        }
        final ocr = _ocrService ??= OcrService();
        final rawText = await ocr.recognizeText(photo.path);
        final localParsed = ReceiptParser.parse(rawText);
        final validation = ReceiptValidator.validate(rawText, localParsed);
        if (!validation.isValid) {
          if (!mounted) return;
          setState(() {
            _isProcessing = false;
            _error = validation.reason;
          });
          return;
        }
        parsed = localParsed;
      }

      if (parsed == null || parsed.items.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _error = "This doesn't look like a receipt. Try again with a clearer photo of your bill.";
        });
        return;
      }

      if (!mounted) return;
      // Pushed, not pushReplacement: this screen has to stay alive behind
      // the review so "Retake photo" comes back here (rather than skipping
      // out to the input chooser) and so the review's retry can ask it to
      // read the photo again. Which means clearing the spinner now, or
      // returning here would find it stuck on "Reading your receipt…".
      setState(() => _isProcessing = false);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewScannedScreen(
            imagePath: kIsWeb ? null : photo.path,
            imageBytes: bytes,
            parsed: parsed!,
            readSource: readSource,
            onRetry: readSource == ReceiptReadSource.onDevice
                ? () => _readPhoto(photo)
                : null,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = 'Could not read that photo. Try again, or enter the bill manually.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Receipt Workspace',
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Scan your receipt', style: AppTypography.sectionHeading),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Make sure the receipt is flat and well-lit. Read by AI for the '
              'most accurate result — the photo is sent to our relay for '
              'reading only, never stored.',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.xxl),
            Expanded(
              child: Center(
                child: _isProcessing
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.accentTerracotta),
                          SizedBox(height: AppSpacing.lg),
                          Text('Reading your receipt…', style: AppTypography.bodySecondary),
                        ],
                      )
                    : Icon(
                        Icons.receipt_long_outlined,
                        size: 96,
                        color: AppColors.accentTerracotta.withValues(alpha: 0.4),
                      ),
              ),
            ),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.bgAmber,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Text(_error!, style: const TextStyle(color: AppColors.textAmber)),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Gallery',
                    icon: Icons.photo_library_outlined,
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SecondaryButton(
                    label: 'Manual',
                    icon: Icons.edit_note_outlined,
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const ManualEntryScreen()),
                            ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Take a photo',
              icon: Icons.camera_alt_outlined,
              onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Make sure the receipt isn\'t folded and the text is clearly visible.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySecondary,
            ),
          ],
        ),
      ),
    );
  }
}
