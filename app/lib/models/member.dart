/// A participant in the current bill-splitting session.
///
/// Exists only in memory for the active session — see PRD §3/§14. Nothing
/// here is ever written to disk or a server; it is discarded when the
/// session ends.
class Member {
  Member({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.isCreator = false,
    this.isPaid = false,
    this.fromDeviceContact = false,
  });

  final String id;
  String name;
  String? phone;
  String? email;

  /// The rounding remainder (FR-5.5) is charged to whichever member has
  /// this set. Exactly one member should be the creator at any time —
  /// enforced by [SessionController], not by this model.
  bool isCreator;

  /// Session-only paid/unpaid flag (FR-8.1) — never persisted.
  bool isPaid;

  final bool fromDeviceContact;

  bool get hasWhatsAppChannel => phone != null && phone!.trim().isNotEmpty;
  bool get hasEmailChannel => email != null && email!.trim().isNotEmpty;
  bool get isReachable => hasWhatsAppChannel || hasEmailChannel;

  Member copyWith({
    String? name,
    String? phone,
    String? email,
    bool? isCreator,
    bool? isPaid,
  }) {
    return Member(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      isCreator: isCreator ?? this.isCreator,
      isPaid: isPaid ?? this.isPaid,
      fromDeviceContact: fromDeviceContact,
    );
  }
}
