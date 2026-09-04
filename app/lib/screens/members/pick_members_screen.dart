import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/member_avatar.dart';
import '../../models/member.dart';
import '../../services/contacts_service.dart';
import '../../state/session_controller.dart';
import '../assignment/item_assignment_screen.dart';
import '../split/split_summary_screen.dart';

/// FR-4.1-4.4: pick members from device contacts, or add them manually.
class PickMembersScreen extends StatefulWidget {
  const PickMembersScreen({super.key});

  @override
  State<PickMembersScreen> createState() => _PickMembersScreenState();
}

enum _ContactsState { notRequested, loading, granted, unavailable, denied }

class _PickMembersScreenState extends State<PickMembersScreen> {
  final ContactsService _contactsService = ContactsService();
  _ContactsState _state = _ContactsState.notRequested;
  List<DeviceContact> _contacts = [];
  String _query = '';

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  /// Maps a device contact id to the member id it created, so unchecking
  /// removes the right member.
  final Map<String, String> _memberIdByContactId = {};

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _state = _ContactsState.loading);
    try {
      final granted = await _contactsService.requestPermission();
      if (!granted) {
        setState(() => _state = _ContactsState.denied);
        return;
      }
      final contacts = await _contactsService.fetchContacts();
      setState(() {
        _contacts = contacts;
        _state = _ContactsState.granted;
      });
    } catch (_) {
      setState(() => _state = _ContactsState.unavailable);
    }
  }

  List<DeviceContact> get _filteredContacts {
    if (_query.trim().isEmpty) return _contacts;
    final q = _query.toLowerCase();
    return _contacts
        .where((c) => c.name.toLowerCase().contains(q) || (c.phone ?? '').contains(q))
        .toList();
  }

  void _toggleContact(SessionController session, DeviceContact contact) {
    final existingMemberId = _memberIdByContactId[contact.id];
    if (existingMemberId != null) {
      session.removeMember(existingMemberId);
      setState(() => _memberIdByContactId.remove(contact.id));
    } else {
      final member = session.addMember(
        name: contact.name,
        phone: contact.phone,
        fromDeviceContact: true,
      );
      setState(() => _memberIdByContactId[contact.id] = member.id);
    }
  }

  void _addManualMember(SessionController session) {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty) return;
    session.addMember(name: name, phone: phone.isEmpty ? null : phone);
    _nameController.clear();
    _phoneController.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final members = session.members;

    return AppScaffold(
      title: 'Receipt Workspace',
      bottomBar: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Selected', style: AppTypography.bodySecondary),
                Text('${members.length} people', style: AppTypography.label),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: PrimaryButton(
              label: 'Continue',
              icon: Icons.arrow_forward,
              onPressed: members.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => session.bill.isItemized
                              ? const ItemAssignmentScreen()
                              : const SplitSummaryScreen(),
                        ),
                      ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Step 2 of 4 · Pick who\'s splitting this', style: AppTypography.sectionHeading),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search name or number…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildContactsSection(session),
          const SizedBox(height: AppSpacing.lg),
          _buildManualAddForm(session),
          if (members.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildSelectedList(session, members),
          ],
        ],
      ),
    );
  }

  Widget _buildContactsSection(SessionController session) {
    switch (_state) {
      case _ContactsState.notRequested:
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.bgInput,
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.accentViolet),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'SplitYuk only reads the contacts you pick — nothing is ever uploaded.',
                      style: AppTypography.bodySecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: 'Choose from contacts',
                icon: Icons.contacts_outlined,
                onPressed: _loadContacts,
              ),
            ],
          ),
        );
      case _ContactsState.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: CircularProgressIndicator(color: AppColors.accentTerracotta)),
        );
      case _ContactsState.denied:
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.bgAmber,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: const Text(
            'Contacts permission was not granted. You can still add everyone manually below.',
            style: TextStyle(color: AppColors.textAmber),
          ),
        );
      case _ContactsState.unavailable:
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.bgInput,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: const Text(
            'Contacts aren\'t available on this device. Add everyone manually below.',
            style: AppTypography.bodySecondary,
          ),
        );
      case _ContactsState.granted:
        final filtered = _filteredContacts;
        if (filtered.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('No matching contacts.', style: AppTypography.bodySecondary),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('CONTACTS', style: AppTypography.eyebrow),
            const SizedBox(height: AppSpacing.sm),
            ...filtered.map((contact) {
              final selected = _memberIdByContactId.containsKey(contact.id);
              final index = _contacts.indexOf(contact);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Material(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    onTap: () => _toggleContact(session, contact),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          MemberAvatar(name: contact.name, colorIndex: index, radius: 18),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(contact.name, style: AppTypography.label),
                                if (contact.phone != null)
                                  Text(contact.phone!, style: AppTypography.bodySecondary),
                              ],
                            ),
                          ),
                          Checkbox(
                            value: selected,
                            activeColor: AppColors.accentViolet,
                            onChanged: (_) => _toggleContact(session, contact),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
    }
  }

  Widget _buildManualAddForm(SessionController session) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.person_add_alt_outlined, color: AppColors.accentTerracottaDark),
              SizedBox(width: AppSpacing.sm),
              Text('Add someone not in your contacts', style: AppTypography.label),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'WhatsApp / phone number'),
          ),
          const SizedBox(height: AppSpacing.md),
          DashedOutlineButton(label: 'Add to list', onPressed: () => _addManualMember(session)),
        ],
      ),
    );
  }

  Widget _buildSelectedList(SessionController session, List<Member> members) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('SELECTED', style: AppTypography.eyebrow),
            const Spacer(),
            Text('${members.length} people', style: AppTypography.bodySecondary),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...members.asMap().entries.map((entry) {
          final index = entry.key;
          final member = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                MemberAvatar(name: member.name, colorIndex: index, radius: 16),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    member.isCreator ? '${member.name} · You' : member.name,
                    style: AppTypography.body,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.textSecondary,
                  onPressed: () {
                    _memberIdByContactId.removeWhere((_, id) => id == member.id);
                    session.removeMember(member.id);
                  },
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
