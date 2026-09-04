import 'package:flutter_contacts/flutter_contacts.dart';

class DeviceContact {
  const DeviceContact({required this.id, required this.name, this.phone});
  final String id;
  final String name;
  final String? phone;
}

/// Reads the device's contact list for member picking (FR-4.2). Nothing
/// read here is ever written anywhere — it's held in memory only for the
/// picker UI, matching PRD §3/§12.
class ContactsService {
  /// Android/iOS only. Callers must catch failures — on platforms without
  /// contacts support (web, desktop) this throws, and the UI should fall
  /// back to manual entry (FR-4.3) rather than crash.
  Future<bool> requestPermission() async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    return status == PermissionStatus.granted || status == PermissionStatus.limited;
  }

  Future<List<DeviceContact>> fetchContacts() async {
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    return contacts
        .where((c) => c.phones.isNotEmpty && (c.displayName ?? '').trim().isNotEmpty)
        .map((c) => DeviceContact(
              id: c.id ?? c.displayName!,
              name: c.displayName!,
              phone: c.phones.first.number,
            ))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
