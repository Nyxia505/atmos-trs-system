import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/services/optaca_account_admin_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class OptacaAccountsPanel extends StatefulWidget {
  const OptacaAccountsPanel({super.key});

  @override
  State<OptacaAccountsPanel> createState() => _OptacaAccountsPanelState();
}

class _OptacaAccountsPanelState extends State<OptacaAccountsPanel> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = const [];
  String _kind = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      final rows = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final role = (data['role'] ?? '').toString().toLowerCase();
        if (role != 'tourism' &&
            role != 'tourism_office' &&
            role != 'tourism_establishment' &&
            role != 'tourismestablishment' &&
            role != 'establishment') {
          continue;
        }
        rows.add({...data, 'uid': doc.id});
      }
      rows.sort(
        (a, b) => (a['fullName'] ?? a['email'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo(
              (b['fullName'] ?? b['email'] ?? '').toString().toLowerCase(),
            ),
      );
      if (!mounted) return;
      setState(() {
        _accounts = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load accounts.';
      });
    }
  }

  String _kindOf(Map<String, dynamic> account) {
    final role = (account['role'] ?? '').toString().toLowerCase();
    if (role == 'tourism' || role == 'tourism_office') return 'LGU';
    final category = (account['category'] ?? '').toString().toLowerCase();
    if (category == 'hotel' ||
        category == 'resort' ||
        category == 'glamping' ||
        category == 'camping') {
      return 'Hotel';
    }
    if (category == 'restaurant' || category == 'food provider') {
      return 'Restaurant';
    }
    return 'Private attraction';
  }

  bool _active(Map<String, dynamic> account) {
    final status = (account['status'] ?? 'active').toString().toLowerCase();
    return status != 'inactive' && status != 'disabled' && status != 'deactivated';
  }

  Future<bool> _run(Future<void> action) async {
    try {
      await action;
      if (!mounted) return false;
      await _load();
      return true;
    } on OptacaAccountException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
  }

  Future<void> _create() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => const _AccountFormDialog(),
    );
    if (saved == true) await _load();
  }

  Future<void> _edit(Map<String, dynamic> account) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _AccountFormDialog(existing: account),
    );
    if (saved == true) await _load();
  }

  Future<void> _password(Map<String, dynamic> account) async {
    final controller = TextEditingController();
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password (at least 8 characters)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null) return;
    final ok = await _run(
      OptacaAccountAdminService.call({
        'action': 'setPassword',
        'uid': account['uid'],
        'password': next,
      }),
    );
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password updated.')),
    );
  }

  Future<void> _toggle(Map<String, dynamic> account) async {
    final active = _active(account);
    await _run(
      OptacaAccountAdminService.call({
        'action': 'setStatus',
        'uid': account['uid'],
        'active': !active,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _accounts.where((account) {
      if (_kind == 'All') return true;
      return _kindOf(account) == _kind;
    }).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('Accounts', style: GovernorDashboardTokens.heading(size: 20)),
        const SizedBox(height: 6),
        Text(
          'Create and edit LGU offices, hotels, restaurants, and private attractions. Deactivated accounts cannot sign in.',
          style: GovernorDashboardTokens.body(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final kind in const [
              'All',
              'LGU',
              'Hotel',
              'Restaurant',
              'Private attraction',
            ])
              ChoiceChip(
                label: Text(kind),
                selected: _kind == kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Create account'),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Text(_error!, style: GovernorDashboardTokens.body())
        else if (visible.isEmpty)
          Text('No accounts in this group.', style: GovernorDashboardTokens.body())
        else
          for (final account in visible) _accountTile(account),
      ],
    );
  }

  Widget _accountTile(Map<String, dynamic> account) {
    final active = _active(account);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text((account['fullName'] ?? account['email'] ?? 'Account').toString()),
        subtitle: Text(
          '${_kindOf(account)} · ${account['email'] ?? ''} · ${account['municipality'] ?? ''}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            Text(active ? 'Active' : 'Inactive'),
            IconButton(
              tooltip: 'Edit',
              onPressed: () => _edit(account),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Change password',
              onPressed: () => _password(account),
              icon: const Icon(Icons.key_outlined),
            ),
            IconButton(
              tooltip: active ? 'Deactivate' : 'Activate',
              onPressed: () => _toggle(account),
              icon: Icon(
                active ? Icons.pause_circle_outline : Icons.play_circle_outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountFormDialog extends StatefulWidget {
  const _AccountFormDialog({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends State<_AccountFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late String _kind;
  late String _municipalityId;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?['fullName']?.toString() ?? '');
    _email = TextEditingController(text: existing?['email']?.toString() ?? '');
    _password = TextEditingController();
    _kind = existing == null ? 'LGU' : _kindFrom(existing);
    _municipalityId = (existing?['municipalityId']?.toString().isNotEmpty == true)
        ? existing!['municipalityId'].toString()
        : getMisamisOccidentalMunicipalities().first.id;
  }

  String _kindFrom(Map<String, dynamic> account) {
    final role = (account['role'] ?? '').toString().toLowerCase();
    if (role == 'tourism' || role == 'tourism_office') return 'LGU';
    final category = (account['category'] ?? '').toString().toLowerCase();
    if (category == 'restaurant' || category == 'food provider') {
      return 'Restaurant';
    }
    if (category == 'hotel' ||
        category == 'resort' ||
        category == 'glamping' ||
        category == 'camping') {
      return 'Hotel';
    }
    return 'Private attraction';
  }

  String get _category {
    switch (_kind) {
      case 'Hotel':
        return 'Hotel';
      case 'Restaurant':
        return 'Restaurant';
      case 'Private attraction':
        return 'Attraction';
      default:
        return '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (_editing) {
        await OptacaAccountAdminService.call({
          'action': 'update',
          'uid': widget.existing!['uid'],
          'fullName': _name.text.trim(),
          'email': _email.text.trim(),
          'municipalityId': _municipalityId,
          if (_category.isNotEmpty) 'category': _category,
        });
      } else {
        await OptacaAccountAdminService.call({
          'action': 'create',
          'fullName': _name.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
          'municipalityId': _municipalityId,
          'role': _kind == 'LGU' ? 'tourism' : 'tourism_establishment',
          if (_category.isNotEmpty) 'category': _category,
        });
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on OptacaAccountException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit account' : 'Create account'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_editing)
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Account type'),
                  items: const [
                    DropdownMenuItem(value: 'LGU', child: Text('LGU tourism office')),
                    DropdownMenuItem(value: 'Hotel', child: Text('Hotel')),
                    DropdownMenuItem(value: 'Restaurant', child: Text('Restaurant')),
                    DropdownMenuItem(
                      value: 'Private attraction',
                      child: Text('Private attraction'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _kind = value ?? _kind),
                ),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: _kind == 'LGU' ? 'Office name' : 'Business name',
                ),
              ),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              if (!_editing)
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: _municipalityId,
                decoration: const InputDecoration(labelText: 'Municipality'),
                items: [
                  for (final m in getMisamisOccidentalMunicipalities())
                    DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(
                          () => _municipalityId = value ?? _municipalityId,
                        ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
