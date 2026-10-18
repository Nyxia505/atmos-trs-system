import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/utils/optaca_stakeholder_export.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// CSV, Excel, and PDF directory of LGUs, hotels, restaurants, and attractions.
class OptacaStakeholderReportsPanel extends StatefulWidget {
  const OptacaStakeholderReportsPanel({
    super.key,
    required this.spots,
  });

  final List<Map<String, dynamic>> spots;

  @override
  State<OptacaStakeholderReportsPanel> createState() =>
      _OptacaStakeholderReportsPanelState();
}

class _OptacaStakeholderReportsPanelState
    extends State<OptacaStakeholderReportsPanel> {
  String _kind = 'All';
  bool _busy = false;

  Future<List<OptacaStakeholderRow>> _rows() async {
    final usersSnap = await FirebaseFirestore.instance.collection('users').get();
    final estSnap = await FirebaseFirestore.instance
        .collection('accommodation_establishments')
        .get();
    return OptacaStakeholderExport.build(
      users: [for (final doc in usersSnap.docs) doc.data()],
      establishments: [for (final doc in estSnap.docs) doc.data()],
      spots: widget.spots,
      kindFilter: _kind,
    );
  }

  Future<void> _download(String format) async {
    setState(() => _busy = true);
    try {
      final rows = await _rows();
      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No stakeholders match this filter.')),
        );
        return;
      }
      await OptacaStakeholderExport.download(format: format, rows: rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed. $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stakeholder reports',
          style: GovernorDashboardTokens.sectionTitle(),
        ),
        const SizedBox(height: 4),
        Text(
          'Download every LGU office, hotel, restaurant, and private attraction. Official DOT forms stay in the section below.',
          style: GovernorDashboardTokens.body(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: _kind,
              items: const [
                DropdownMenuItem(value: 'All', child: Text('All stakeholders')),
                DropdownMenuItem(value: 'LGU', child: Text('LGUs')),
                DropdownMenuItem(value: 'Hotel', child: Text('Hotels')),
                DropdownMenuItem(value: 'Restaurant', child: Text('Restaurants')),
                DropdownMenuItem(
                  value: 'Private attraction',
                  child: Text('Private attractions'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _kind = value ?? 'All'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _download('csv'),
              icon: const Icon(Icons.table_rows_outlined),
              label: const Text('CSV'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _download('excel'),
              icon: const Icon(Icons.grid_on_outlined),
              label: const Text('Excel'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _download('pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_busy ? 'Preparing…' : 'PDF'),
            ),
          ],
        ),
      ],
    );
  }
}
