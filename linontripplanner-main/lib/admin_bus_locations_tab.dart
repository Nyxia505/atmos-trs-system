import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'data.dart';
import 'municipality_coordinates.dart';
import 'services/bus_location_store.dart';

/// Admin list for Firestore bus stops and terminals.
class AdminBusLocationsTab extends StatelessWidget {
  const AdminBusLocationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BusLocationStore.instance.revision,
      builder: (context, _, __) {
        final rows = List<BusLocation>.from(BusLocationStore.instance.locations);
        return Stack(
          children: [
            if (rows.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No bus stops yet. Add one to store its coordinates in Firebase.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final active = row.isActive;
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      title: Text(row.name),
                      subtitle: Text(
                        '${row.municipality} · '
                        '${row.locationType == 'terminal' ? 'Bus terminal' : 'Bus stop'} · '
                        '${_routeLabel(row.routeType)} · '
                        '${active ? 'Active' : 'Inactive'}\n'
                        '${row.latitude.toStringAsFixed(6)}, '
                        '${row.longitude.toStringAsFixed(6)}',
                      ),
                      isThreeLine: true,
                      onTap: () => _openEditor(context, existing: row),
                    ),
                  );
                },
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _openEditor(context),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add stop'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEditor(BuildContext context, {BusLocation? existing}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BusLocationEditor(existing: existing),
      ),
    );
  }
}

String _routeLabel(String routeType) {
  switch (routeType) {
    case 'highland':
      return 'Highland';
    case 'both':
      return 'Coastal and Highland';
    default:
      return 'Coastal';
  }
}

class _BusLocationEditor extends StatefulWidget {
  final BusLocation? existing;

  const _BusLocationEditor({this.existing});

  @override
  State<_BusLocationEditor> createState() => _BusLocationEditorState();
}

class _BusLocationEditorState extends State<_BusLocationEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _order;
  late String _municipality;
  late String _routeType;
  late String _locationType;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _lat = TextEditingController(
      text: e == null ? '' : e.latitude.toStringAsFixed(6),
    );
    _lng = TextEditingController(
      text: e == null ? '' : e.longitude.toStringAsFixed(6),
    );
    _order = TextEditingController(text: '${e?.sortOrder ?? 0}');
    _municipality = e?.municipality ??
        (municipalities.isNotEmpty ? municipalities.first.name : '');
    _routeType = e?.routeType ?? 'coastal';
    _locationType = e?.locationType ?? 'stop';
    _status = e?.status ?? 'active';
    BusLocationStore.instance.ensureListening();
  }

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    _order.dispose();
    super.dispose();
  }

  LatLng? get _point {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }

  LatLng get _camera {
    final point = _point;
    if (point != null) return point;
    for (final m in municipalities) {
      if (m.name == _municipality) {
        final center = getMunicipalityCoordinates(m);
        if (center != null) {
          return LatLng(center.latitude, center.longitude);
        }
      }
    }
    return misamisOccidentalCenter;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final error = BusLocation.validate(
      name: _name.text,
      municipality: _municipality,
      routeType: _routeType,
      locationType: _locationType,
      status: _status,
      latitude: double.tryParse(_lat.text.trim()),
      longitude: double.tryParse(_lng.text.trim()),
    );
    if (error != null) {
      _snack(error);
      return;
    }
    setState(() => _saving = true);
    try {
      await BusLocationStore.instance.save(
        BusLocation(
          id: widget.existing?.id ?? '',
          name: _name.text.trim(),
          municipality: _municipality,
          routeType: _routeType,
          latitude: double.parse(_lat.text.trim()),
          longitude: double.parse(_lng.text.trim()),
          locationType: _locationType,
          status: _status,
          sortOrder: int.tryParse(_order.text.trim()) ?? 0,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null || id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this stop?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BusLocationStore.instance.delete(id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _snack('$e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final point = _point;
    final names = [
      for (final m in municipalities) m.name,
    ]..sort();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(widget.existing == null ? 'Add bus stop' : 'Edit bus stop'),
        actions: [
          if (widget.existing != null)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              height: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _camera,
                    zoom: 13,
                  ),
                  onTap: (pos) {
                    setState(() {
                      _lat.text = pos.latitude.toStringAsFixed(6);
                      _lng.text = pos.longitude.toStringAsFixed(6);
                    });
                  },
                  markers: {
                    if (point != null)
                      Marker(
                        markerId: const MarkerId('picked'),
                        position: point,
                      ),
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the map to fill latitude and longitude, or type them below.',
              style: TextStyle(fontSize: 12.5, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name.' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: names.contains(_municipality) ? _municipality : null,
              decoration: const InputDecoration(
                labelText: 'Municipality',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final name in names)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _municipality = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _routeType,
              decoration: const InputDecoration(
                labelText: 'Route',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'coastal', child: Text('Coastal')),
                DropdownMenuItem(value: 'highland', child: Text('Highland')),
                DropdownMenuItem(
                  value: 'both',
                  child: Text('Coastal and Highland'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _routeType = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _locationType,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'stop', child: Text('Bus stop')),
                DropdownMenuItem(value: 'terminal', child: Text('Bus terminal')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _locationType = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _order,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Order along the route',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
