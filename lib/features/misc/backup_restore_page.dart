import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/api_config.dart';
import '../../../config/app_config.dart';
import '../../../core/api/query_cache.dart';
import '../../../core/utils/formatting.dart';
import '../../../state/app_scope.dart';
import '../../../ui/kit/data.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/theme.dart';
import '../../../ui/kit/inputs.dart';

/// Port of `features/reports-backup/reports-backup-page.tsx`.
///
/// The browser build wrote into a folder the user picked with the File System
/// Access API. A phone has no equivalent, so the same `YYYY/MM-Month/` tree is
/// created inside the app documents directory instead: files always land
/// somewhere durable, and the share sheet is offered for anything that has to
/// leave the device.
///
/// Both artifacts are hashed. The JSON backup carries a SHA-256 per source and
/// the gzip round-trip is verified before the compressed file is allowed on
/// disk — a backup that cannot be read back is worse than no backup.
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Mirrors `REPORT_SOURCES` — the areas a snapshot claims to cover.
  static const List<({String key, String label})> _reportSources = [
    (key: 'company', label: 'Company settings'),
    (key: 'income', label: 'Income (ledger)'),
    (key: 'expenses', label: 'Expenses'),
    (key: 'attendance', label: 'Attendance'),
    (key: 'salary', label: 'Salary slips (payments)'),
    (key: 'bills', label: 'Bills'),
    (key: 'payments', label: 'Payments received'),
    (key: 'shop_bills', label: 'Shop bills'),
    (key: 'legacy_invoices', label: 'Legacy invoices'),
    (key: 'gatepasses', label: 'Gate passes'),
    (key: 'deliveries', label: 'Deliveries'),
    (key: 'returns', label: 'Returns'),
    (key: 'linen_status', label: 'Linen stock status'),
  ];

  static const String _metaKey = 'll_backup_last';

  bool _monthMode = false;
  late String _date;
  late String _month;
  final List<String> _log = [];
  final List<String> _existing = [];
  bool _busy = false;
  bool _shared = false;
  _Snapshot? _result;
  Map<String, dynamic>? _lastBackup;

  @override
  void initState() {
    super.initState();
    _date = Fmt.today();
    _month = _date.substring(0, 7);
    _loadLastBackup();
  }

  String get _period => _monthMode ? _month : _date;

  String get _prefix => _period;

  String get _year => _period.substring(0, 4);

  String get _monthNumber => _period.substring(5, 7);

  String get _monthDir {
    final m = int.tryParse(_monthNumber) ?? 1;
    return '${m.toString().padLeft(2, '0')}-${_monthNames[(m - 1).clamp(0, 11)]}';
  }

  String get _relativePath => '$_year/$_monthDir';

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
  }

  // ── Formatting helpers ────────────────────────────────────────────────

  String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  String _fmtDate(String value) {
    final parts = value.split('-');
    if (parts.length < 3) return value;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  String _monthLabel(String period) {
    if (period.length < 7) return period;
    final m = int.tryParse(period.substring(5, 7));
    if (m == null) return period;
    return '${_monthNames[(m - 1).clamp(0, 11)]} ${period.substring(0, 4)}';
  }

  String _money(Object? value) => Fmt.money(_num(value));

  double _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  String _text(Object? value, [String fallback = '']) {
    if (value == null) return fallback;
    final s = value.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String _dayOf(Object? value) {
    final s = _text(value);
    return s.length >= 10 ? s.substring(0, 10) : '';
  }

  List<Map<String, dynamic>> _rows(dynamic payload) {
    if (payload is List) {
      return payload
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }
    if (payload is Map) {
      for (final key in const [
        'items',
        'rows',
        'data',
        'records',
        'results',
        'transactions',
        'expenses',
        'linens',
      ]) {
        final value = payload[key];
        if (value is List) {
          return value
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false);
        }
      }
    }
    return const [];
  }

  // ── Period window ─────────────────────────────────────────────────────

  /// First and last day of the period, in the `YYYY-MM-DD` form the management
  /// and bills services expect.
  (String, String) _window() {
    if (_monthMode) {
      final year = int.parse(_year);
      final month = int.parse(_monthNumber);
      final last = DateTime(year, month + 1, 0).day;
      return (
        '$_year-$_monthNumber-01',
        '$_year-$_monthNumber-${last.toString().padLeft(2, '0')}'
      );
    }
    final day = DateTime.parse(_date);
    return (
      Fmt.isoDate(DateTime(day.year, day.month, 1)),
      Fmt.isoDate(DateTime(day.year, day.month + 1, 0)),
    );
  }

  bool _inPeriod(Object? value) {
    final day = _dayOf(value);
    if (day.isEmpty) return false;
    final (start, end) = _window();
    return day.compareTo(start) >= 0 && day.compareTo(end) <= 0;
  }

  // ── Snapshot collection ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _paged(
    String service,
    String path, {
    int limit = 500,
    Map<String, dynamic> extra = const {},
  }) async {
    final api = AppScope.read(context).api;
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    // Bounded so a server that ignores `limit` cannot spin forever: 20 pages of
    // 500 rows is 10k records, well past any single business period.
    for (var page = 0; page < 20; page++) {
      final payload = await api.get(service, path, query: {
        'skip': offset,
        'offset': offset,
        'limit': limit,
        ...extra,
      });
      final rows = _rows(payload);
      out.addAll(rows);
      if (rows.length < limit) break;
      offset += limit;
    }
    return out;
  }

  /// One area of the business. `ok: false` means the source was unreachable —
  /// the run still completes, but the operator sees which gap they are looking
  /// at instead of a silently short report.
  Future<_Source> _collect(
    String key,
    String label,
    Future<List<Map<String, dynamic>>> Function() load,
  ) async {
    try {
      final records = await load();
      return _Source(
        key: key,
        label: label,
        ok: true,
        fetched: records.length,
        records: records,
      );
    } catch (err) {
      return _Source(
        key: key,
        label: label,
        error: '$err',
      );
    }
  }

  Future<_Snapshot> _collectSnapshot() async {
    final (start, end) = _window();
    _append('Collecting ${_monthMode ? 'monthly' : 'daily'} snapshot…');
    final sources = <_Source>[
      _Source(
        key: 'company',
        label: 'Company settings',
        ok: true,
        fetched: 1,
        records: [
          {
            'name': CompanyInfo.name,
            'tagline': CompanyInfo.tagline,
            'registration_no': CompanyInfo.registrationNo,
            'address': CompanyInfo.addressBlock,
            'phone': CompanyInfo.phonePrimary,
            'email': CompanyInfo.email,
          }
        ],
      ),
    ];

    sources.add(await _collect('income', 'Income (ledger)', () async {
      final rows = await _paged(
        ServiceNames.management,
        '/api/transactions',
        extra: {'start_date': start, 'end_date': end},
      );
      return rows
          .where((r) =>
              _inPeriod(r['transaction_date'] ?? r['date'] ?? r['created_at']))
          .map((r) => {
                'id': _text(r['id'] ?? r['_id'] ?? r['transaction_id']),
                'date': _dayOf(r['transaction_date'] ?? r['date']),
                'customer': _text(r['customer_name'] ??
                    r['customer'] ??
                    r['client_name'] ??
                    r['payee']),
                'description':
                    _text(r['description'] ?? r['particulars'] ?? r['notes']),
                'source': _text(r['source']),
                'payment_method': _text(r['payment_method'] ?? r['method']),
                'amount': _num(r['total_amount'] ??
                    r['amount'] ??
                    r['total'] ??
                    r['value']),
              })
          .toList();
    }));

    sources.add(await _collect('expenses', 'Expenses', () async {
      final rows = await _paged(
        ServiceNames.management,
        '/api/expenses',
        extra: {'start_date': start, 'end_date': end},
      );
      return rows
          .where((r) => _inPeriod(r['date'] ??
              r['expense_date'] ??
              r['created_at'] ??
              r['paid_date']))
          .map((r) => {
                'id': _text(r['id'] ?? r['_id'] ?? r['expense_id']),
                'date': _dayOf(r['date'] ?? r['expense_date']),
                'category': _text(
                    r['category_name'] ?? r['category'] ?? r['category_id']),
                'description':
                    _text(r['description'] ?? r['particulars'] ?? r['notes']),
                'payee': _text(r['payee'] ??
                    r['expense_for'] ??
                    r['paid_to'] ??
                    r['vendor']),
                'payment_method': _text(r['payment_method'] ?? r['method']),
                'amount': _num(r['amount'] ?? r['total'] ?? r['value']),
              })
          .toList();
    }));

    sources.add(await _collect('attendance', 'Attendance', () async {
      final api = AppScope.read(context).api;
      final names = await _employeeNames();
      final payload = await api.get(
        ServiceNames.management,
        '/api/attendance',
        query: {
          'start_date': _monthMode ? start : _date,
          'end_date': _monthMode ? end : _date,
          'limit': 2000,
        },
      );
      return _rows(payload).map((r) {
        final id =
            _text(r['employee_id'] ?? r['employee'] ?? r['id'] ?? r['_id']);
        return {
          'employee_id': id,
          'employee_name': _text(
            r['employee_name'] ?? r['name'] ?? r['full_name'],
            names[id] ?? (id.isEmpty ? 'Unknown' : id),
          ),
          'date': _dayOf(r['date'] ?? r['attendance_date']),
          'status': _text(r['status'], 'PRESENT').toUpperCase(),
          'overtime_hours': _num(r['overtime_hours'] ?? r['ot_hours']),
        };
      }).toList();
    }));

    sources.add(await _collect('salary', 'Salary slips (payments)', () async {
      final rows = await _paged(
        ServiceNames.management,
        '/api/salary/slips',
        extra: {'year': int.parse(_year), 'month': int.parse(_monthNumber)},
      );
      return rows
          .where((r) => _inPeriod(r['paid_date'] ??
              r['date'] ??
              r['created_at'] ??
              r['settled_date']))
          .map((r) => {
                'slip_id': _text(r['id'] ?? r['_id'] ?? r['slip_id']),
                'employee_name': _text(
                    r['employee_name'] ?? r['name'] ?? r['full_name'],
                    'Unknown'),
                'period_start': _text(r['period_start'] ?? r['start_date']),
                'period_end': _text(r['period_end'] ?? r['end_date']),
                'gross': _num(
                    r['total_earnings'] ?? r['gross'] ?? r['gross_salary']),
                'deductions': _num(r['total_deductions'] ??
                    r['deductions'] ??
                    r['deduction_total']),
                'net': _num(r['net_salary'] ??
                    r['net'] ??
                    r['net_pay'] ??
                    r['take_home']),
                'status': _text(r['status'], 'FINALIZED').toUpperCase(),
                'paid_date': _text(r['paid_date']),
              })
          .toList();
    }));

    sources.add(await _collect('bills', 'Bills', () async {
      final rows = await _paged(
        ServiceNames.bills,
        '/bills',
        extra: {'start_date': start, 'end_date': end},
      );
      return rows
          .where((r) => _inPeriod(r['bill_date'] ??
              r['date'] ??
              r['created_at'] ??
              r['pickup_date']))
          .toList();
    }));

    sources.add(await _collect('payments', 'Payments received', () async {
      final rows = await _paged(
        ServiceNames.management,
        '/api/payments',
        extra: {'start_date': start, 'end_date': end},
      );
      return rows
          .where((r) => _inPeriod(r['payment_date'] ??
              r['date'] ??
              r['created_at'] ??
              r['paid_date']))
          .map((r) => {
                'id': _text(r['id'] ?? r['_id'] ?? r['payment_id']),
                'date': _dayOf(r['payment_date'] ?? r['date']),
                'customer': _text(
                    r['customer_name'] ?? r['customer'] ?? r['client_name']),
                'method': _text(r['payment_method'] ?? r['method']),
                'amount': _num(r['amount'] ??
                    r['total_amount'] ??
                    r['total'] ??
                    r['value']),
              })
          .toList();
    }));

    sources.add(await _collect('shop_bills', 'Shop bills', () async {
      final rows = await _paged(ServiceNames.bills, '/shop-bills');
      return rows
          .where(
              (r) => _inPeriod(r['bill_date'] ?? r['date'] ?? r['created_at']))
          .toList();
    }));

    sources.add(await _collect('legacy_invoices', 'Legacy invoices', () async {
      final rows =
          await _paged(ServiceNames.bills, '/shop-bills/legacy', limit: 200);
      return rows
          .where(
              (r) => _inPeriod(r['bill_date'] ?? r['date'] ?? r['created_at']))
          .toList();
    }));

    sources.add(await _collect('gatepasses', 'Gate passes', () async {
      final rows = await _paged(ServiceNames.bills, '/gatepasses');
      return rows
          .where((r) => _inPeriod(r['gatepass_date'] ??
              r['date'] ??
              r['created_at'] ??
              r['issued_at']))
          .toList();
    }));

    sources.add(await _collect('deliveries', 'Deliveries', () async {
      final rows = await _paged(ServiceNames.bills, '/deliveries');
      return rows
          .where((r) => _inPeriod(r['delivery_date'] ??
              r['date'] ??
              r['created_at'] ??
              r['dispatched_at']))
          .toList();
    }));

    sources.add(await _collect('returns', 'Returns', () async {
      final rows = await _paged(ServiceNames.bills, '/returns');
      return rows
          .where((r) =>
              _inPeriod(r['return_date'] ?? r['date'] ?? r['created_at']))
          .toList();
    }));

    sources.add(await _collect('linen_status', 'Linen stock status', () async {
      final api = AppScope.read(context).api;
      return _rows(
          await api.get(ServiceNames.bills, '/linens', query: {'limit': 5000}));
    }));

    double totalOf(String key) => sources
        .firstWhere((s) => s.key == key)
        .records
        .fold<double>(0, (sum, r) => sum + _num(r['amount']));

    final income = totalOf('income');
    final expenses = totalOf('expenses');

    return _Snapshot(
      periodKind: _monthMode ? 'month' : 'day',
      period: _period,
      sources: sources,
      income: income,
      expenses: expenses,
      apiBases: {
        'mgmt_api': ApiConfig.managementBase,
        'bills_api': ApiConfig.billsBase,
      },
    );
  }

  Future<Map<String, String>> _employeeNames() async {
    try {
      final api = AppScope.read(context).api;
      final payload = await api.get(ServiceNames.management, '/api/employees',
          query: {'search': ''});
      final map = <String, String>{};
      for (final r in _rows(payload)) {
        final id = _text(r['id'] ?? r['_id'] ?? r['employee_id']);
        final name = _text(r['full_name'] ?? r['name'] ?? r['employee_name']);
        if (id.isNotEmpty && name.isNotEmpty) map[id] = name;
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  // ── JSON backup ───────────────────────────────────────────────────────

  Map<String, dynamic> _manifest(_Snapshot snapshot) {
    final hashes = <String, dynamic>{};
    final data = <String, dynamic>{};
    for (final s in snapshot.sources) {
      hashes[s.key] =
          sha256.convert(utf8.encode(jsonEncode(s.records))).toString();
      data[s.key] = s.records;
    }
    return {
      'meta': {
        'period_kind': snapshot.periodKind,
        'period': snapshot.period,
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'app': 'Skaner',
        'api_bases': snapshot.apiBases,
        'totals': {
          'income': snapshot.income,
          'expenses': snapshot.expenses,
          'net': snapshot.net,
        },
        'sources': [
          for (final s in snapshot.sources)
            {
              'key': s.key,
              'label': s.label,
              'ok': s.ok,
              'error': s.error,
              'fetched': s.fetched,
              'count': s.records.length,
            }
        ],
      },
      'hashes': hashes,
      'data': data,
    };
  }

  /// Hashes every source, gzips the JSON, then reads the gzip back and
  /// compares it to the original so a compressed file that cannot be restored
  /// never reaches the disk.
  Future<_JsonBackup> _buildJson(_Snapshot snapshot) async {
    final json =
        const JsonEncoder.withIndent('  ').convert(_manifest(snapshot));
    final bytes = utf8.encode(json);
    final plainHash = sha256.convert(bytes).toString();

    final codec = GZipCodec(level: 6);
    final gz = Uint8List.fromList(codec.encode(bytes));
    if (utf8.decode(codec.decode(gz)) != json) {
      throw StateError('Gzip round-trip verification failed');
    }

    return _JsonBackup(
      json: json,
      gzip: gz,
      verify: {
        'plain_sha256': plainHash,
        'gzip_sha256': sha256.convert(gz).toString(),
        'verified_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  // ── Filesystem ────────────────────────────────────────────────────────

  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _targetDir() async {
    final dir = Directory('${(await _rootDir()).path}/$_relativePath');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<String>> _listBackupFiles() async {
    final root = await _rootDir();
    final out = <String>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is File && entity.uri.pathSegments.contains(_prefix)) {
        out.add(entity.path);
      }
    }
    out.sort();
    return out;
  }

  Future<void> _checkExisting() async {
    try {
      final files = await _listBackupFiles();
      if (!mounted) return;
      setState(() {
        _existing
          ..clear()
          ..addAll(files.map((p) => p.split('/').last));
      });
      AppToast.success(
        context,
        files.isEmpty
            ? 'No files yet for this period'
            : '${files.length} file(s) will be overwritten',
      );
    } catch (err) {
      if (!mounted) return;
      AppToast.error(context, 'Could not inspect backups: $err');
    }
  }

  // ── Run ───────────────────────────────────────────────────────────────

  Future<void> _run({required bool pdf, required bool json}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _shared = false;
      _log.clear();
      _result = null;
      _existing.clear();
    });

    final startedAt = DateTime.now().toUtc();
    String stamp(DateTime v) =>
        v.toIso8601String().replaceFirst('T', ' ').substring(0, 19);

    try {
      _append('Started at ${stamp(startedAt)} (UTC)');
      _append(
          'Generating ${_monthMode ? 'MONTHLY' : 'daily'} report for $_period —'
          '${pdf && json ? ' PDF + JSON' : pdf ? ' PDF' : ' JSON'}');

      final snapshot = await _collectSnapshot();
      final okCount = snapshot.sources.where((s) => s.ok).length;
      final failed =
          snapshot.sources.where((s) => !s.ok).map((s) => s.label).toList();
      _append('Snapshot ready: $okCount/${snapshot.sources.length} sources'
          '${failed.isEmpty ? '' : ' (unavailable: ${failed.join(', ')})'}');
      for (final s in snapshot.sources) {
        _append(
            '  ${s.ok ? 'ok  ' : 'FAIL'} ${s.label}: fetched ${s.fetched} → '
            'kept ${s.records.length}${s.error != null ? ' (${s.error})' : ''}');
      }
      _append(
          'API bases → ${snapshot.apiBases['mgmt_api']} · ${snapshot.apiBases['bills_api']}');
      _append('Ledger: income ${Fmt.money(snapshot.income)} • '
          'expenses ${Fmt.money(snapshot.expenses)} • net ${Fmt.money(snapshot.net)}');

      final files = <_SavedFile>[];
      final paths = <String>[];

      final dir = await _targetDir();
      _append('Writing into backups/$_relativePath/…');

      if (pdf) {
        _append('Building PDF…');
        final bytes = await _buildPdf(snapshot);
        final file = File('${dir.path}/$_prefix.pdf');
        await file.writeAsBytes(bytes, flush: true);
        _append('PDF ready: ${_fmtBytes(bytes.length)}');
        files.add(_SavedFile('$_prefix.pdf', bytes.length));
        paths.add(file.path);
      }

      if (json) {
        _append('Building JSON backup + gzip…');
        final built = await _buildJson(snapshot);
        final file = File('${dir.path}/$_prefix.json.gz');
        await file.writeAsBytes(built.gzip, flush: true);
        _append(
            'JSON.gz ready: ${_fmtBytes(built.gzip.length)} (round-trip verified)');
        files.add(_SavedFile('$_prefix.json.gz', built.gzip.length));
        paths.add(file.path);

        final verifyFile = File('${dir.path}/$_prefix.verify.json');
        await verifyFile.writeAsString(jsonEncode(built.verify), flush: true);
        files.add(_SavedFile('$_prefix.verify.json',
            utf8.encode(jsonEncode(built.verify)).length));
        paths.add(verifyFile.path);
      }

      final finishedAt = DateTime.now().toUtc();
      _append('Done at ${stamp(finishedAt)} (UTC)');

      final meta = {
        'report_date': _prefix,
        'period_kind': _monthMode ? 'month' : 'day',
        'started_at': startedAt.toIso8601String(),
        'finished_at': finishedAt.toIso8601String(),
        'folder_name': 'backups/$_relativePath',
        'files': [
          for (final f in files) {'name': f.name, 'size': f.size}
        ],
        'modes': [
          if (pdf) 'pdf',
          if (json) 'json',
        ],
        'snapshot_summary': {
          'income': snapshot.income,
          'expenses': snapshot.expenses,
          'net': snapshot.net,
          'sources_ok': okCount,
          'sources_total': snapshot.sources.length,
        },
        'paths': paths,
      };

      if (!mounted) return;
      setState(() {
        _result = snapshot;
        _lastBackup = meta;
        _busy = false;
      });
      _saveLastBackup(meta);
      AppToast.success(
        context,
        '${_monthMode ? 'Monthly' : 'Daily'} report saved '
        '(${files.map((f) => f.name).join(', ')})',
      );
    } catch (err) {
      _append('Error: $err');
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, '$err');
    }
  }

  // ── PDF ───────────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdf(_Snapshot snapshot) async {
    final doc = pw.Document();
    final income = snapshot.source('income');
    final expenses = snapshot.source('expenses');
    final attendance = snapshot.source('attendance');
    final salary = snapshot.source('salary');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.Text(CompanyInfo.name,
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text(
            '${_monthMode ? 'Monthly' : 'Daily'} report — '
            '${_monthMode ? _monthLabel(_month) : _fmtDate(_date)}',
            style: const pw.TextStyle(fontSize: 13),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Ledger',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          _ledgerRow('Income', Fmt.money(snapshot.income)),
          _ledgerRow('Expenses', Fmt.money(snapshot.expenses)),
          _ledgerRow('Net', Fmt.money(snapshot.net)),
          pw.SizedBox(height: 12),
          pw.Text('Data sources',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              for (final s in snapshot.sources)
                pw.TableRow(children: [
                  pw.Expanded(
                      child: pw.Text(s.label,
                          style: const pw.TextStyle(fontSize: 9))),
                  pw.Text(s.ok ? 'ok' : 'failed',
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('${s.fetched} → ${s.records.length}',
                      style: const pw.TextStyle(fontSize: 9)),
                ]),
            ],
          ),
          if (income.records.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Income entries',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            _recordTable(<_Column>[
              const _Column('Date', 'date'),
              const _Column('Customer', 'customer'),
              const _Column('Description', 'description'),
              const _Column('Amount', 'amount', money: true),
            ], income.records),
          ],
          if (expenses.records.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Expenses',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            _recordTable(<_Column>[
              const _Column('Date', 'date'),
              const _Column('Category', 'category'),
              const _Column('Payee', 'payee'),
              const _Column('Amount', 'amount', money: true),
            ], expenses.records),
          ],
          if (attendance.records.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Attendance',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            _recordTable(<_Column>[
              const _Column('Date', 'date'),
              const _Column('Employee', 'employee_name'),
              const _Column('Status', 'status'),
              const _Column('OT', 'overtime_hours'),
            ], attendance.records),
          ],
          if (salary.records.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Salary slips',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            _recordTable(<_Column>[
              const _Column('Employee', 'employee_name'),
              const _Column('Gross', 'gross', money: true),
              const _Column('Deductions', 'deductions', money: true),
              const _Column('Net', 'net', money: true),
            ], salary.records),
          ],
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _ledgerRow(String label, String value) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      );

  pw.Widget _recordTable(
      List<_Column> spec, List<Map<String, dynamic>> records) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [
        pw.TableRow(children: [
          for (final col in spec)
            pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text(col.header,
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
        ]),
        for (final record in records.take(200))
          pw.TableRow(children: [
            for (final col in spec)
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(
                  col.money
                      ? Fmt.money(_num(record[col.key]))
                      : _text(record[col.key], '—'),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
          ]),
      ],
    );
  }

  // ── Share, print, restore ─────────────────────────────────────────────

  Future<void> _share() async {
    final files = await _listBackupFiles();
    if (files.isEmpty) {
      if (!mounted) return;
      AppToast.warning(context, 'No saved files to share yet');
      return;
    }
    await Share.shareXFiles(
      files.map(XFile.new).toList(),
      text: '${_monthMode ? 'Monthly' : 'Daily'} backup — $_period',
    );
    if (!mounted) return;
    setState(() => _shared = true);
  }

  Future<void> _print() async {
    try {
      final snapshot = _result ?? await _collectSnapshot();
      final bytes = await _buildPdf(snapshot);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: '$_prefix.pdf',
      );
    } catch (err) {
      if (!mounted) return;
      AppToast.error(context, 'Could not build the PDF: $err');
    }
  }

  /// Snapshot source keys do not match the resource keys the screens read, so
  /// they are mapped explicitly. A key that is not listed is not restored
  /// rather than written somewhere nothing will ever look.
  static const Map<String, String> _cacheKeyFor = {
    'company': 'company-settings',
    'income': 'transactions',
    'expenses': 'expenses',
    'attendance': 'attendance',
    'salary': 'salary',
    'bills': 'bills',
    'payments': 'payments',
    'shop_bills': 'shop-bills',
    'legacy_invoices': 'legacy-invoices',
    'gatepasses': 'gatepasses',
    'deliveries': 'deliveries',
    'returns': 'returns',
    'linen_status': 'linens',
  };

  /// Reads a saved backup, re-hashes every source and seeds the local query
  /// cache with the snapshot's rows. The server is never touched: this only
  /// gives the app something to read offline until a real sync lands.
  Future<void> _restore() async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Restore from backup?',
      message: 'The saved snapshot will seed the local cache for offline '
          'reading. Server data is untouched, and the next real sync '
          'overwrites the cache.',
      confirmLabel: 'Restore',
      icon: Icons.settings_backup_restore,
    );
    if (!confirmed || !mounted) return;
    final cache = AppScope.read(context).cache;
    try {
      final files = await _listBackupFiles();
      // Filenames mix `YYYY-MM` and `YYYY-MM-DD` prefixes, so a lexical sort
      // does not identify the newest file. Modification time does.
      final gz = <File>[];
      for (final path in files.where((p) => p.endsWith('.json.gz'))) {
        final f = File(path);
        if (await f.exists()) gz.add(f);
      }
      if (gz.isEmpty) {
        if (!mounted) return;
        AppToast.warning(context, 'No .json.gz backup found for this period');
        return;
      }
      gz.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      final file = gz.last;
      final raw = await file.readAsBytes();
      final decoded = jsonDecode(utf8.decode(GZipCodec().decode(raw)));
      if (decoded is! Map) throw StateError('Backup is not a JSON object');
      final payload = Map<String, dynamic>.from(decoded);
      final meta = (payload['meta'] as Map?)?.cast<String, dynamic>() ?? {};
      final hashes =
          (payload['hashes'] as Map?)?.cast<String, dynamic>() ?? const {};
      final data = (payload['data'] as Map?)?.cast<String, dynamic>() ?? {};
      if (data.isEmpty) {
        if (!mounted) return;
        AppToast.warning(context, 'This backup contains no records');
        return;
      }
      for (final entry in hashes.entries) {
        final actual =
            sha256.convert(utf8.encode(jsonEncode(data[entry.key]))).toString();
        if (entry.value.toString() != actual) {
          throw StateError(
              'Checksum mismatch for ${entry.key} — file is corrupt');
        }
      }

      // Restored rows are historical, so they are written with the snapshot's
      // own timestamp: a months-old backup must not appear as freshly synced.
      final takenAt =
          DateTime.tryParse(meta['generated_at'] as String? ?? '') ??
              DateTime.now().toUtc();
      final stale = takenAt
          .isAfter(DateTime.now().subtract(QueryCache.stalenessFor('bills')));
      final skipped = <String>[];
      var restored = 0;
      for (final entry in data.entries) {
        final key = _cacheKeyFor[entry.key];
        final rows = entry.value;
        if (key == null || rows is! List) {
          skipped.add(entry.key);
          continue;
        }
        final maps = rows.whereType<Map>().toList();
        if (maps.isEmpty) {
          skipped.add(entry.key);
          continue;
        }
        cache.write(
          key,
          maps.map((r) => Map<String, dynamic>.from(r)).toList(),
          updatedAt: takenAt.toLocal(),
          status: stale ? CacheStatus.fresh : CacheStatus.stale,
        );
        restored++;
      }
      if (!mounted) return;
      if (restored == 0) {
        AppToast.error(context, 'No restorable data found in this backup');
        return;
      }
      final when = '${takenAt.year}-${_two(takenAt.month)}-'
          '${_two(takenAt.day)} ${_two(takenAt.hour)}:${_two(takenAt.minute)}';
      final note =
          skipped.isEmpty ? '' : ' · ${skipped.length} source(s) skipped';
      AppToast.success(context, 'Restored $restored source(s) from $when$note');
    } catch (err) {
      if (!mounted) return;
      AppToast.error(context, 'Restore failed: $err');
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  // ── Last backup meta ───────────────────────────────────────────────────

  Future<void> _loadLastBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_metaKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map && mounted) {
        setState(() => _lastBackup = Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // A malformed meta is not worth blocking the screen for.
    }
  }

  Future<void> _saveLastBackup(Map<String, dynamic> meta) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_metaKey, jsonEncode(meta));
    } catch (_) {
      // Best effort only — the files themselves are already on disk.
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final last = _lastBackup;
    final summary =
        (last?['snapshot_summary'] as Map?)?.cast<String, dynamic>();
    final modes = (last?['modes'] as List?)?.cast<String>() ?? const <String>[];

    return Column(
      children: [
        AppPageHeader(
          title: 'Reports & Backup',
          subtitle: 'Daily PDF plus a machine-readable JSON backup of every '
              'business area, filed under $_relativePath/ in the app folder.',
          busy: _busy,
          actions: [
            AppButton(
              label: 'Share',
              icon: Icons.ios_share,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: _busy ? null : _share,
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              AppNotice(
                tone: AppTone.warning,
                title: 'Admin only',
                message:
                    'Backups are written to this device’s private app folder. '
                    'Share them out to keep a copy off the phone — the device copy '
                    'is deleted if the app is uninstalled.',
              ),
              const SizedBox(height: 14),
              _generateCard(t, c),
              const SizedBox(height: 14),
              _lastBackupCard(t, c, last, summary, modes),
              const SizedBox(height: 14),
              _sourcesCard(t, c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _generateCard(TextTheme t, AppColors c) {
    return AppCard(
      leading: const Icon(Icons.cloud_download_outlined, size: 18),
      title: 'Generate Report',
      subtitle: _shared
          ? 'Files shared — copies still saved in the app folder'
          : 'Tap Share afterwards to move copies off this device',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _segment(t, c),
          const SizedBox(height: 14),
          _periodPicker(t, c),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: 'PDF only',
                icon: Icons.picture_as_pdf_outlined,
                onPressed: _busy ? null : () => _run(pdf: true, json: false),
              ),
              AppButton(
                label: 'JSON only',
                icon: Icons.archive_outlined,
                onPressed: _busy ? null : () => _run(pdf: false, json: true),
              ),
              AppButton(
                label: 'PDF + JSON',
                icon: Icons.cloud_download_outlined,
                variant: AppButtonVariant.primary,
                onPressed: _busy ? null : () => _run(pdf: true, json: true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: 'Check existing',
                icon: Icons.search,
                size: AppButtonSize.sm,
                dense: true,
                onPressed: _busy ? null : _checkExisting,
              ),
              AppButton(
                label: 'Share',
                icon: Icons.ios_share,
                size: AppButtonSize.sm,
                dense: true,
                onPressed: _busy ? null : _share,
              ),
              AppButton(
                label: 'Print PDF',
                icon: Icons.print_outlined,
                size: AppButtonSize.sm,
                dense: true,
                onPressed: _busy ? null : _print,
              ),
              AppButton(
                label: 'Restore',
                icon: Icons.settings_backup_restore,
                size: AppButtonSize.sm,
                dense: true,
                onPressed: _busy ? null : _restore,
              ),
            ],
          ),
          if (_existing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in _existing)
                  AppBadge(
                    '$name · will overwrite',
                    tone: AppTone.warning,
                    icon: Icons.delete_outline,
                    compact: true,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'JSON backups are gzipped (.json.gz), checksummed per source, and '
            'round-trip verified before saving.',
            style: t.bodySmall?.copyWith(color: c.fgMuted, fontSize: context.fs(11)),
          ),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 12),
            _runLog(t, c),
          ],
          if (_busy) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const AppSpinner(size: 14),
                const SizedBox(width: 8),
                Text('Working…',
                    style: t.bodySmall?.copyWith(color: c.fgMuted)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _segment(TextTheme t, AppColors c) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          _segmentButton(t, c, 'Day', !_monthMode),
          _segmentButton(t, c, 'Month', _monthMode),
        ],
      ),
    );
  }

  Widget _segmentButton(TextTheme t, AppColors c, String label, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_monthMode == (label == 'Month')) return;
          setState(() {
            _monthMode = label == 'Month';
            _existing.clear();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: active ? Shadows.sm : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? c.fg : c.fgMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _periodPicker(TextTheme t, AppColors c) {
    return Row(
      children: [
        Icon(Icons.calendar_today_outlined, size: 15, color: c.fgMuted),
        const SizedBox(width: 8),
        Expanded(child: _monthMode ? _monthField(t, c) : _dateField(t, c)),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = Fmt.isoDate(picked);
      _existing.clear();
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse('$_month-01') ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      helpText: 'Select any day of the month',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _month = Fmt.isoDate(picked).substring(0, 7);
      _existing.clear();
    });
  }

  Widget _dateField(TextTheme t, AppColors c) {
    return _field(t, c, Fmt.date(_date), _pickDate, 'Change report date');
  }

  Widget _monthField(TextTheme t, AppColors c) {
    return _field(t, c, _monthLabel(_month), _pickMonth, 'Change report month');
  }

  Widget _field(
    TextTheme t,
    AppColors c,
    String label,
    VoidCallback onTap,
    String tooltip,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: t.bodyMedium),
              Text(_monthMode ? 'Change' : 'Change',
                  style: t.bodySmall?.copyWith(color: c.fgMuted, fontSize: context.fs(11))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _runLog(TextTheme t, AppColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RUN LOG',
            style: t.labelSmall?.copyWith(
              color: const Color(0xFF9CA3AF),
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final e in _log.asMap().entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${(e.key + 1).toString().padLeft(2, '0')} ${e.value}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: context.fs(11),
                  height: 1.5,
                  color: Color(0xFFD1D5DB),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lastBackupCard(
    TextTheme t,
    AppColors c,
    Map<String, dynamic>? last,
    Map<String, dynamic>? summary,
    List<String> modes,
  ) {
    return AppCard(
      leading: const Icon(Icons.lock_outline, size: 18),
      title: 'Last Backup',
      child: last == null
          ? Text('No backup has been generated yet.',
              style: t.bodyMedium?.copyWith(color: c.fgMuted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${last['period_kind'] == 'month' ? _monthLabel(last['report_date']?.toString() ?? '') : _fmtDate(last['report_date']?.toString() ?? '')} · '
                  '${(last['finished_at']?.toString() ?? '').replaceFirst('T', ' ').split('.').first} UTC',
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Net ${_money(summary?['net'])} '
                  '(${_money(summary?['income'])} income − ${_money(summary?['expenses'])} expenses)',
                  style: t.bodyMedium?.copyWith(color: c.fgMuted),
                ),
                Text(
                  '${summary?['sources_ok'] ?? 0}/${summary?['sources_total'] ?? 0} data sources · ${modes.join(' + ')}',
                  style: t.bodySmall?.copyWith(color: c.fgMuted),
                ),
                const SizedBox(height: 10),
                for (final f in (last['files'] as List?) ?? const [])
                  if (f is Map)
                    _fileRow(t, c, _text(f['name']), _num(f['size']).round()),
              ],
            ),
    );
  }

  Widget _fileRow(TextTheme t, AppColors c, String name, int size) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              name,
              style: TextStyle(fontFamily: 'monospace', fontSize: context.fs(11)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(_fmtBytes(size), style: t.bodySmall?.copyWith(color: c.fgMuted)),
        ],
      ),
    );
  }

  Widget _sourcesCard(TextTheme t, AppColors c) {
    final result = _result;
    return AppCard(
      leading: const Icon(Icons.cloud_download_outlined, size: 18),
      title: 'Data Sources',
      child: result == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Run a generation to see which data sources were included for that day.',
                  style: t.bodyMedium?.copyWith(color: c.fgMuted),
                ),
                const SizedBox(height: 8),
                for (final s in _reportSources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: c.fgMuted, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(s.label,
                              style: t.bodySmall?.copyWith(color: c.fgMuted)),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statBox(
                        t, c, 'Income', Fmt.money(result.income), c.success),
                    const SizedBox(width: 8),
                    _statBox(
                        t, c, 'Expenses', Fmt.money(result.expenses), c.danger),
                    const SizedBox(width: 8),
                    _statBox(t, c, 'Net', Fmt.money(result.net),
                        result.net >= 0 ? c.success : c.danger),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in result.sources)
                      AppBadge(
                        s.ok
                            ? '${s.label} · ${s.fetched}→${s.records.length}'
                            : '${s.label} · failed',
                        tone: s.ok ? AppTone.success : AppTone.danger,
                        icon: s.ok
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_outlined,
                        compact: true,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final f in (lastFiles(result)))
                  Text('${f.name} · ${_fmtBytes(f.size)}',
                      style: TextStyle(
                          fontFamily: 'monospace', fontSize: context.fs(11))),
              ],
            ),
    );
  }

  List<_SavedFile> lastFiles(_Snapshot result) => [
        for (final s in result.sources)
          if (s.ok && s.records.isNotEmpty)
            _SavedFile(
              '${s.key}.json',
              utf8.encode(jsonEncode(s.records)).length,
            ),
      ];

  Widget _statBox(
      TextTheme t, AppColors c, String label, String value, Color tone) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFieldLabel(label, opaque: true),
            const SizedBox(height: 2),
            FittedBox(
              child: Text(
                value,
                style: t.titleSmall
                    ?.copyWith(color: tone, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Source {
  const _Source({
    required this.key,
    required this.label,
    this.ok = false,
    this.error,
    this.fetched = 0,
    this.records = const [],
  });

  final String key;
  final String label;
  final bool ok;
  final String? error;
  final int fetched;
  final List<Map<String, dynamic>> records;
}

class _Snapshot {
  const _Snapshot({
    required this.periodKind,
    required this.period,
    required this.sources,
    required this.income,
    required this.expenses,
    required this.apiBases,
  });

  final String periodKind;
  final String period;
  final List<_Source> sources;
  final double income;
  final double expenses;
  final Map<String, String> apiBases;

  double get net => income - expenses;

  _Source source(String key) => sources.firstWhere(
        (s) => s.key == key,
        orElse: () => _Source(key: key, label: key),
      );
}

class _JsonBackup {
  const _JsonBackup({
    required this.json,
    required this.gzip,
    required this.verify,
  });

  final String json;
  final Uint8List gzip;
  final Map<String, dynamic> verify;
}

class _SavedFile {
  const _SavedFile(this.name, this.size);
  final String name;
  final int size;
}

class _Column {
  const _Column(this.header, this.key, {this.money = false});
  final String header;
  final String key;
  final bool money;
}
