import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/utils/installation_id.dart';
import '../models/member.dart';

enum NotificationChannel { whatsapp, email }

class NotifyOutcome {
  const NotifyOutcome({required this.memberId, required this.success, this.error});
  final String memberId;
  final bool success;
  final String? error;
}

/// Talks to the stateless backend relay (PRD §13) that actually holds the
/// Fonnte/email API keys and sends the message — this app never talks to
/// Fonnte or an email provider directly, and never sees their credentials.
///
/// [relayBaseUrl] is intentionally not hardcoded to a real deployment: this
/// app ships without a live backend connected. Until a real relay URL is
/// configured (see /server in the repo root), [isConfigured] is false and
/// the UI must say so plainly rather than pretend a send succeeded.
class NotificationService {
  NotificationService({this.relayBaseUrl});

  final String? relayBaseUrl;

  bool get isConfigured => relayBaseUrl != null && relayBaseUrl!.trim().isNotEmpty;

  /// PRD §11 rule 4: prefer [preferred], but fall back to whichever channel
  /// the member actually has contact info for; null if neither is set.
  static NotificationChannel? resolveChannel(Member member, NotificationChannel preferred) {
    final preferredAvailable = preferred == NotificationChannel.whatsapp
        ? member.hasWhatsAppChannel
        : member.hasEmailChannel;
    if (preferredAvailable) return preferred;
    if (member.hasWhatsAppChannel) return NotificationChannel.whatsapp;
    if (member.hasEmailChannel) return NotificationChannel.email;
    return null;
  }

  Future<NotifyOutcome> send({
    required Member member,
    required NotificationChannel channel,
    required String billTitle,
    required int amountDue,
    String? attachmentImagePath,
  }) async {
    if (!isConfigured) {
      return NotifyOutcome(
        memberId: member.id,
        success: false,
        error: 'Backend relay not configured.',
      );
    }

    try {
      final token = await InstallationId.get();
      final uri = Uri.parse('${relayBaseUrl!}/api/notify');
      final request = http.MultipartRequest('POST', uri)
        ..fields['installationToken'] = token
        ..fields['channel'] = channel.name
        ..fields['billTitle'] = billTitle
        ..fields['amountDue'] = amountDue.toString()
        ..fields['recipientName'] = member.name;

      if (channel == NotificationChannel.whatsapp) {
        request.fields['phone'] = member.phone ?? '';
      } else {
        request.fields['email'] = member.email ?? '';
      }

      if (attachmentImagePath != null) {
        final file = File(attachmentImagePath);
        if (await file.exists()) {
          request.files.add(await http.MultipartFile.fromPath('attachment', attachmentImagePath));
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return NotifyOutcome(memberId: member.id, success: true);
      }
      return NotifyOutcome(
        memberId: member.id,
        success: false,
        error: 'Relay returned ${response.statusCode}.',
      );
    } catch (_) {
      return NotifyOutcome(
        memberId: member.id,
        success: false,
        error: 'Could not reach the relay. Check your connection and try again.',
      );
    }
  }
}
