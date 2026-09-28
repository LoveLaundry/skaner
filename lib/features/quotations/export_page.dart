import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Derived screen: the web app exposes these exports as a dropdown on the
/// dashboard header rather than a page of its own. The mobile port keeps the
/// same six server exports — gate passes, bills and deliveries, each as CSV or
/// Excel — and gives them a screen, because a dropdown behind an icon is not
/// reachable one-handed.
class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  static const List<({String type, String label, String description})>
      _targets = [
    (
      type: 'gatepasses',
      label: 'Gate passes',
      description: 'Every received pass with its status and balance'
    ),
    (
      type: 'bills',
      label: 'Bills',
      description: 'All bills with totals, payments and outstanding'
    ),
    (
      type: 'deliveries',
      label: 'Deliveries',
      description: 'Dispatched linen with quantities and dates'
    ),
  ];

  DateTime? _from;
  DateTime? _to;
  String? _running;

  bool get _hasDateFilter => _from != null || _to != null;

  Map<String, dynamic> get _query => {
        if (_from != null) 'date_from': Fmt.isoDate(_from),
        if (_to != null) 'date_to': Fmt.isoDate(_to),
      };

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, reportsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Export')),
        body: opsNotPermitted('export'),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Server export',
            style: context.texts.bodySmall?.copyWith(color: context.c.fgFaint),
          ),
          const SizedBox(height: 4),
          Text(
            'The server builds each file, so the export always matches what the '
            'rest of the app shows.',
            style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Date range', style: context.texts.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Optional. Leave empty to export everything in scope.',
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.c.fgMuted),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppDateField(
                        value: _from,
                        hint: 'From',
                        onChanged: (d) => setState(() => _from = d),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDateField(
                        value: _to,
                        hint: 'To',
                        onChanged: (d) => setState(() => _to = d),
                      ),
                    ),
                  ],
                ),
                if (_hasDateFilter)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _from = null;
                        _to = null;
                      }),
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                      label: const Text('Clear dates'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: context.c.fgMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final t in _targets) ...[
            _TargetCard(
              label: t.label,
              description: t.description,
              busy: _running == t.type,
              onCsv: () => _export(t.type, csv: true),
              onXlsx: () => _export(t.type, csv: false),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  /// A CSV arrives as text and an XLSX as bytes, so the two formats cannot share
  /// a file even though the request is otherwise identical.
  Future<void> _export(String type, {required bool csv}) async {
    setState(() => _running = type);
    final path = csv ? '/export/$type' : '/export/$type/xlsx';
    final name = '$type-${Fmt.isoDate(DateTime.now())}.${csv ? 'csv' : 'xlsx'}';
    try {
      final api = AppScope.read(context).api;
      final bytes = csv
          ? utf8.encode(
              await api.getText(
                operationsService,
                path,
                query: _query,
              ),
            )
          : await api.getBytes(
              operationsService,
              path,
              query: _query,
            );
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: csv
                ? 'text/csv'
                : 'application/vnd.openxmlformats-officedocument'
                    '.spreadsheetml.sheet',
          ),
        ],
        subject: '${type[0].toUpperCase()}${type.substring(1)} export',
      );
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (e) {
      if (mounted) AppToast.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({
    required this.label,
    required this.description,
    required this.busy,
    required this.onCsv,
    required this.onXlsx,
  });

  final String label;
  final String description;
  final bool busy;
  final VoidCallback onCsv;
  final VoidCallback onXlsx;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const OpsIcon(Icons.download_outlined, tone: AppTone.info),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: context.texts.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      description,
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.c.fgMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'CSV',
                  variant: AppButtonVariant.outline,
                  icon: Icons.table_rows_outlined,
                  loading: busy,
                  onPressed: onCsv,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Excel',
                  variant: AppButtonVariant.outline,
                  icon: Icons.grid_on_outlined,
                  onPressed: busy ? null : onXlsx,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
