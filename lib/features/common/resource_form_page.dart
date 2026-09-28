import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/query_cache.dart';
import '../../data/resource_controller.dart';
import '../../data/resource_definition.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';

/// One form screen for every module whose writes are a flat record.
///
/// It seeds from the record being edited, validates against the declared
/// fields, and lets the API client decide between a real write and an
/// outbox entry — so the operator gets the same confirmation either way.
class ResourceFormPage extends StatefulWidget {
  const ResourceFormPage({
    super.key,
    required this.definition,
    this.record,
    this.hotelName,
  });

  final ResourceDefinition definition;

  /// `null` creates, non-null edits.
  final Map<String, dynamic>? record;
  final String? hotelName;

  @override
  State<ResourceFormPage> createState() => _ResourceFormPageState();
}

class _ResourceFormPageState extends State<ResourceFormPage> {
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _numControllers = {};
  Map<String, String> _errors = {};
  bool _busy = false;
  bool _dirty = false;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    _seed();
  }

  void _seed() {
    final def = widget.definition;
    for (final f in def.formFields) {
      dynamic v;
      if (f.hotelScoped && widget.hotelName != null && widget.hotelName!.isNotEmpty) {
        v = widget.hotelName;
      } else if (f.defaultValue != null) {
        v = f.defaultValue;
      } else if (widget.record != null) {
        v = pick(widget.record!, [f.name, _snake(f.name), _camel(f.name)]);
      }
      if (v == null) {
        switch (f.type) {
          case ResourceFieldType.switchField:
            v = 0;
          case ResourceFieldType.date:
            v = DateTime.now().toIso8601String();
          case ResourceFieldType.dateTime:
            v = DateTime.now().toIso8601String();
          default:
            v = '';
        }
      }
      _values[f.name] = v;
    }
  }

  static String _snake(String s) =>
      s.replaceAllMapped(RegExp(r'([A-Z])'), (m) => '_${m[1]!.toLowerCase()}');

  static String _camel(String s) {
    final parts = s.split('_');
    if (parts.isEmpty) return s;
    return parts.first +
        parts.skip(1).map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join();
  }

  @override
  void dispose() {
    for (final c in _numControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String name, dynamic value) {
    setState(() {
      _values[name] = value;
      _dirty = true;
      if (_errors.containsKey(name)) {
        _errors = Map.of(_errors)..remove(name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.definition;
    final t = context.texts;
    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await AppConfirmDialog.show(
          context,
          title: 'Discard changes?',
          message: 'This ${def.singular.toLowerCase()} has unsaved edits.',
          confirmLabel: 'Discard',
          destructive: true,
        );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? def.formTitleForEdit : 'New ${def.singular}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppButton(
                label: _isEdit ? 'Save' : 'Create',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.sm,
                loading: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_isEdit)
              AppSyncStatusBar(
                status: CacheStatus.fresh,
                updatedAt: null,
                label: 'Editing',
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  if (def.formFields.isEmpty)
                    const AppEmptyState(
                      title: 'No editable fields',
                      message:
                          'This module is edited through a dedicated workflow.',
                      icon: Icons.lock_outline,
                    )
                  else
                    ResourceFieldBuilder(
                      fields: def.formFields,
                      values: _values,
                      errors: _errors,
                      hotelName: widget.hotelName,
                      onChanged: _set,
                    ),
                  const SizedBox(height: 20),
                  if (_isEdit && def.canDelete)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _confirmDelete,
                      icon: const Icon(Icons.delete_outline, size: 17),
                      label: Text('Delete ${def.singular.toLowerCase()}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.c.danger,
                        side: BorderSide(color: context.c.dangerBorder),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Writes are queued when the device is offline and replayed in '
                    'order once the connection returns.',
                    style: t.bodySmall?.copyWith(color: context.c.fgFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _busy
            ? const LinearProgressIndicator(minHeight: 2)
            : null,
      ),
    );
  }

  Map<String, dynamic> _payload() {
    final out = <String, dynamic>{};
    for (final f in widget.definition.formFields) {
      // A field hidden for the current values is not part of the payload.
      if (f.visibleWhen != null && !f.visibleWhen!(_values)) continue;
      final v = _values[f.name];
      if (v == null) continue;
      out[f.name] = switch (f.type) {
        ResourceFieldType.number || ResourceFieldType.money => asDouble(v),
        ResourceFieldType.date || ResourceFieldType.dateTime =>
          DateTime.tryParse('$v')?.toIso8601String() ?? v,
        _ => v is String && v.isEmpty ? null : v,
      };
    }
    // Preserve fields the form does not declare, so a partial update never
    // drops server-owned columns.
    if (_isEdit) {
      for (final e in widget.record!.entries) {
        out.putIfAbsent(e.key, () => e.value);
      }
    }
    out.removeWhere((_, v) => v == null);
    return out;
  }

  Future<void> _submit() async {
    final def = widget.definition;
    final errors = ResourceFieldBuilder.validate(def.formFields, _values);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      AppToast.error(context, 'Fix ${errors.length} field(s) before saving');
      return;
    }

    final services = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final payload = _payload();
      final Object? result = _isEdit
          ? await services.api.patch(def.service,
              def.recordPath(widget.record!['id']),
              body: payload)
          : await services.api.post(def.service, def.listPath(), body: payload);
      services.cache.invalidateResource(def.cacheKey);
      if (!mounted) return;
      setState(() => _dirty = false);
      if (result is QueuedResponse) {
        AppToast.info(context,
            'Offline — ${def.singular.toLowerCase()} queued and will sync');
      } else {
        AppToast.success(
          context,
          '${def.singular} ${_isEdit ? 'updated' : 'created'}',
        );
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
      final fieldErrors = e.fieldErrors;
      if (fieldErrors.isNotEmpty) {
        setState(() => _errors = fieldErrors);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final def = widget.definition;
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Delete ${def.singular}?',
      message: 'This cannot be undone from the device.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    final services = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await services.api.delete(def.service, def.recordPath(widget.record!['id']));
      services.cache.invalidateResource(def.cacheKey);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
