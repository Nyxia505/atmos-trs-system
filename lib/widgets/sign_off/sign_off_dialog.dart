import 'dart:async';

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/sign_off_service.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/sign_off/signature_pad.dart';

/// "Who is saving this?" — pick a remembered name + position, draw a fresh
/// signature, certify. Returns null when cancelled (nothing is saved).
class SignOffDialog extends StatefulWidget {
  const SignOffDialog({
    super.key,
    required this.ownerId,
    required this.action,
    required this.summary,
    this.details = const [],
    this.requireReason = false,
    this.reasonHint,
    this.notice,
  });

  final String ownerId;
  final SignOffAction action;
  final String summary;
  final List<String> details;
  final bool requireReason;
  final String? reasonHint;
  final String? notice;

  static Future<SignOffCapture?> show(
    BuildContext context, {
    required String ownerId,
    required SignOffAction action,
    required String summary,
    List<String> details = const [],
    bool requireReason = false,
    String? reasonHint,
    String? notice,
  }) =>
      showDialog<SignOffCapture>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SignOffDialog(
          ownerId: ownerId,
          action: action,
          summary: summary,
          details: details,
          requireReason: requireReason,
          reasonHint: reasonHint,
          notice: notice,
        ),
      );

  @override
  State<SignOffDialog> createState() => _SignOffDialogState();
}

class _SignOffDialogState extends State<SignOffDialog> {
  final _name = TextEditingController();
  final _position = TextEditingController();
  final _reason = TextEditingController();
  final _pad = SignaturePadController();
  late final Stream<List<SignOffSigner>> _signers = SignOffService.watchSigners(widget.ownerId);
  String? _selectedId;
  bool _prefilled = false;
  bool _certified = false;
  bool _remember = true;
  bool _busy = false;
  String? _error;

  bool get _needsReason => widget.requireReason || widget.action.requiresReason;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _position, _reason]) {
      c.addListener(_refresh);
    }
    _pad.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.dispose();
    _position.dispose();
    _reason.dispose();
    _pad.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().length >= 2 &&
      _position.text.trim().length >= 2 &&
      !_pad.isEmpty &&
      _certified &&
      (!_needsReason || _reason.text.trim().length >= 4);

  void _pick(SignOffSigner s) {
    setState(() {
      _selectedId = s.id;
      _name.text = s.name;
      _position.text = s.position;
    });
  }

  void _newPerson() {
    setState(() {
      _selectedId = null;
      _name.clear();
      _position.clear();
    });
  }

  Future<void> _forget(SignOffSigner s) async {
    try {
      await SignOffService.forgetSigner(widget.ownerId, s.id);
      if (_selectedId == s.id) _newPerson();
    } catch (e) {
      setState(() => _error = 'Could not remove ${s.name}: $e');
    }
  }

  Future<void> _confirm() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final png = await _pad.toPng();
    if (!mounted) return;
    if (png == null) {
      setState(() {
        _busy = false;
        _error = 'Please sign inside the box.';
      });
      return;
    }
    final name = _name.text.trim();
    final position = _position.text.trim();
    if (_remember) {
      unawaited(SignOffService.rememberSigner(widget.ownerId, name, position).catchError(
        (Object e) => debugPrint('[SignOff] remember signer: $e'),
      ));
    }
    Navigator.of(context).pop(SignOffCapture(
      name: name,
      position: position,
      signaturePng: png,
      reason: _reason.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
              child: Row(children: [
                const Icon(Icons.draw_rounded, color: AeDashTokens.accent),
                const SizedBox(width: 10),
                Expanded(child: Text('Sign to save', style: AeDashTokens.heading(size: 18))),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summaryBox(),
                    if (widget.notice != null) ...[
                      const SizedBox(height: 8),
                      Text(widget.notice!, style: AeDashTokens.body(size: 12, color: AeDashTokens.accent, weight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 14),
                    Text('Who is saving this?', style: AeDashTokens.section(size: 13.5)),
                    const SizedBox(height: 8),
                    _signerPicker(),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _field(_name, 'Full name', Icons.person_outline_rounded)),
                      const SizedBox(width: 10),
                      Expanded(child: _field(_position, 'Position', Icons.badge_outlined)),
                    ]),
                    const SizedBox(height: 10),
                    _field(
                      _reason,
                      _needsReason ? 'Reason (required)' : 'Note (optional)',
                      Icons.edit_note_rounded,
                      hint: widget.reasonHint,
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: Text('Signature', style: AeDashTokens.section(size: 13.5))),
                      TextButton.icon(
                        onPressed: _pad.strokes.isEmpty ? null : _pad.undo,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('Undo'),
                      ),
                      TextButton.icon(
                        onPressed: _pad.strokes.isEmpty ? null : _pad.clear,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Clear'),
                      ),
                    ]),
                    SignaturePad(controller: _pad),
                    const SizedBox(height: 4),
                    Text('A fresh signature is needed for every save.', style: AeDashTokens.body(size: 11.5)),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _certified,
                      onChanged: (v) => setState(() => _certified = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text(
                        'I certify that this entry is true and correct to the best of my knowledge.',
                        style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text),
                      ),
                    ),
                    CheckboxListTile(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v ?? true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text('Remember this name and position on this establishment',
                          style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text)),
                    ),
                    Text(
                      'Your name, position, signature and the change are kept as an audit record '
                      'for your LGU, OPTACA and the Governor (Data Privacy Act, RA 10173).',
                      style: AeDashTokens.body(size: 11),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: AeDashTokens.body(size: 12, color: AeDashTokens.danger)),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AeDashTokens.accent),
                    onPressed: _valid && !_busy ? _confirm : null,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Sign & save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBox() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AeDashTokens.softAccent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AeDashTokens.accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.action.label, style: AeDashTokens.section(size: 13.5, color: AeDashTokens.accent)),
            const SizedBox(height: 4),
            Text(widget.summary, style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text, weight: FontWeight.w600)),
            for (final d in widget.details.take(6))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $d', style: AeDashTokens.body(size: 12)),
              ),
            if (widget.details.length > 6)
              Text('• …and ${widget.details.length - 6} more', style: AeDashTokens.body(size: 12)),
          ],
        ),
      );

  Widget _signerPicker() {
    return StreamBuilder<List<SignOffSigner>>(
      stream: _signers,
      builder: (context, snap) {
        final list = snap.data ?? const <SignOffSigner>[];
        if (!_prefilled && list.isNotEmpty && _name.text.isEmpty) {
          _prefilled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _name.text.isEmpty) _pick(list.first);
          });
        }
        if (list.isEmpty) {
          return Text(
            snap.connectionState == ConnectionState.waiting
                ? 'Loading saved people…'
                : 'No saved people yet — type a name and position below.',
            style: AeDashTokens.body(size: 12),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in list.take(12))
              InputChip(
                selected: _selectedId == s.id,
                onPressed: () => _pick(s),
                onDeleted: () => _forget(s),
                deleteButtonTooltipMessage: 'Forget (past sign-offs are kept)',
                avatar: const Icon(Icons.person_rounded, size: 16),
                label: Text(s.position.isEmpty ? s.name : '${s.name} · ${s.position}'),
              ),
            ActionChip(
              avatar: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Someone else'),
              onPressed: _newPerson,
            ),
          ],
        );
      },
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {String? hint}) => TextField(
        controller: c,
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
          isDense: true,
          prefixIcon: Icon(icon, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}
