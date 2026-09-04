import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/utils/id_generator.dart';
import '../core/utils/image_mime_type.dart';
import '../core/utils/installation_id.dart';
import '../logic/receipt_parser.dart';
import '../models/bill_item.dart';

class AiReceiptOutcome {
  const AiReceiptOutcome({this.parsed, this.isReceipt = true, this.reason, this.error});

  /// Non-null when the call succeeded and the photo was recognized as a
  /// receipt.
  final ParsedReceipt? parsed;

  /// False when the call succeeded but Gemini determined the photo isn't a
  /// receipt at all — [reason] then explains why.
  final bool isReceipt;
  final String? reason;

  /// Non-null when the call itself failed (relay not configured,
  /// unreachable, rate-limited, etc.) — distinct from "not a receipt".
  final String? error;

  bool get succeeded => error == null;
}

/// Sends the receipt photo to the backend relay's `/api/parse-receipt`,
/// which reads it with Gemini (a deliberate product decision: the photo
/// leaves the device at scan time for materially better accuracy than
/// on-device OCR — see CLAUDE.md). This app never calls Gemini directly;
/// the API key lives server-side only, same pattern as notifications.
class AiReceiptService {
  AiReceiptService({this.relayBaseUrl});

  final String? relayBaseUrl;

  bool get isConfigured => relayBaseUrl != null && relayBaseUrl!.trim().isNotEmpty;

  Future<AiReceiptOutcome> parseReceipt(String imagePath) async {
    if (!isConfigured) {
      return const AiReceiptOutcome(error: 'AI relay not configured.');
    }

    try {
      final token = await InstallationId.get();
      final uri = Uri.parse('${relayBaseUrl!}/api/parse-receipt');
      final request = http.MultipartRequest('POST', uri)
        ..fields['installationToken'] = token
        ..files.add(await http.MultipartFile.fromPath(
          'image',
          imagePath,
          // Without this the part is sent as application/octet-stream and
          // Gemini refuses it as raw binary instead of reading the receipt.
          contentType: ImageMimeType.forPath(imagePath),
        ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        String? message;
        try {
          message = (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String?;
        } catch (_) {
          // Ignore — fall back to a generic status-based message below.
        }
        return AiReceiptOutcome(error: message ?? 'Relay returned ${response.statusCode}.');
      }

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        return const AiReceiptOutcome(error: 'The relay returned an unreadable response.');
      }

      final isReceipt = json['isReceipt'] == true;
      if (!isReceipt) {
        return AiReceiptOutcome(
          isReceipt: false,
          reason: json['reason'] as String? ??
              "This doesn't look like a receipt. Try again with a clearer photo of your bill.",
        );
      }

      final rawItems = json['items'];
      final items = <BillItem>[];
      if (rawItems is List) {
        for (final entry in rawItems) {
          if (entry is! Map) continue;
          final name = entry['name'];
          final price = entry['price'];
          if (name is String && name.trim().isNotEmpty && price is num && price > 0) {
            items.add(BillItem(id: IdGenerator.next('item'), name: name.trim(), price: price.round()));
          }
        }
      }

      final totalRaw = json['detectedTotal'];
      final detectedTotal = totalRaw is num ? totalRaw.round() : null;

      return AiReceiptOutcome(parsed: ParsedReceipt(items: items, detectedTotal: detectedTotal));
    } catch (_) {
      return const AiReceiptOutcome(error: 'Could not reach the AI relay.');
    }
  }
}
