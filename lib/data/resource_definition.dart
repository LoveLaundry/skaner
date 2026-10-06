import 'package:flutter/material.dart';

import '../data/resource_controller.dart';
import '../ui/kit/inputs.dart';
import '../ui/theme.dart';
import '../ui/kit/primitives.dart';

/// The declarative contract that lets one list screen and one form screen cover
/// every CRUD module in the app.
///
/// A complex workflow (quotation builder, gate pass, dispatch) is hand-written
/// instead — this is for the plain collection screens where the only
/// difference between modules is field names and endpoints.
@immutable
class ResourceField {
  const ResourceField({
    required this.name,
    required this.label,
    this.type = ResourceFieldType.text,
    this.hint,
    this.required = false,
    this.defaultValue,
    this.options = const [],
    this.hotelScoped = false,
    this.visibleWhen,
    this.min,
    this.max,
    this.maxLines = 1,
    this.helper,
  });

  /// Column name in the record and the key sent to the API.
  final String name;
  final String label;
  final ResourceFieldType type;
  final String? hint;
  final bool required;
  final Object? defaultValue;

  /// Static choices for [ResourceFieldType.select].
  final List<ResourceSelectOption> options;

  /// Sends the currently scoped hotel rather than the operator's pick.
  final bool hotelScoped;

  /// Hides the field unless the record satisfies this predicate.
  final bool Function(Map<String, dynamic> record)? visibleWhen;

  final double? min;
  final double? max;
  final int maxLines;
  final String? helper;
}

enum ResourceFieldType {
  text,
  textarea,
  number,
  money,
  select,
  date,
  dateTime,
  switchField,
  signature,
}

@immutable
class ResourceSelectOption {
  const ResourceSelectOption({required this.value, required this.label});

  final String value;
  final String label;
}

@immutable
class ResourceColumn {
  const ResourceColumn({
    required this.label,
    required this.value,
    this.minWidth = 90,
  });

  final String label;
  final String Function(Map<String, dynamic> row) value;
  final double minWidth;
}

/// Search + status filters rendered above the list.
@immutable
class ResourceFilter {
  const ResourceFilter({
    required this.name,
    required this.label,
    this.values = const [],
    this.statusValues = const [],
  });

  /// Query parameter name, e.g. `status`.
  final String name;
  final String label;
  final List<ResourceSelectOption> values;
  final List<ResourceSelectOption> statusValues;
}

@immutable
class ResourceDefinition {
  const ResourceDefinition({
    required this.service,
    required this.path,
    required this.singular,
    required this.plural,
    required this.cacheKey,
    this.columns = const [],
    this.titleField = 'id',
    this.subtitleField,
    this.searchParam = 'search',
    this.searchFields = const [],
    this.filters = const [],
    this.formFields = const [],
    this.hotelParam = 'client_name',
    this.hotelScoped = true,
    this.permission,
    this.readPermission,
    this.defaultLimit = 25,
    this.sortBy,
    this.canCreate = true,
    this.canEdit = true,
    this.canDelete = true,
    this.createLabel = 'New',
    this.icon,
    this.group = 'Operations',
    this.emptyTitle,
    this.emptyMessage,
    this.formTitleForEdit = 'Edit',
    this.detailPath,
    this.statusParam = 'status',
    this.toneResolver,
  });

  /// Backend service name, e.g. `quotation`.
  final String service;

  /// Collection path, e.g. `/bills`.
  final String path;
  final String singular;
  final String plural;

  /// Cache prefix; the sync engine invalidates on this name.
  final String cacheKey;

  final List<ResourceColumn> columns;

  /// Field shown as the row's headline.
  final String titleField;
  final String? subtitleField;
  final String? searchParam;
  final List<String> searchFields;
  final List<ResourceFilter> filters;
  final List<ResourceField> formFields;

  /// Query parameter that scopes rows to a hotel.
  final String hotelParam;
  final bool hotelScoped;

  /// Write permission. When set, the create/edit/delete actions hide unless
  /// the operator holds it.
  final String? permission;

  /// Read permission, for modules that are visible but not editable.
  final String? readPermission;

  final int defaultLimit;
  final String? sortBy;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;
  final String createLabel;
  final IconData? icon;
  final String group;
  final String? emptyTitle;
  final String? emptyMessage;
  final String formTitleForEdit;

  /// Path template for a single record, defaulting to `'$path/{id}'`.
  final String? detailPath;

  final String statusParam;
  final AppTone? Function(Map<String, dynamic> row)? toneResolver;

  String recordPath(Object id) => (detailPath ?? '$path/{id}').replaceFirst(
        '{id}',
        '$id',
      );

  String listPath() => path;

  /// Base query with hotel scope + sort applied.
  Map<String, dynamic> baseQuery({
    String? hotel,
    int? limit,
    int? page,
  }) =>
      {
        if (hotelScoped && hotel != null && hotel.isNotEmpty) hotelParam: hotel,
        if (limit != null) 'limit': limit,
        if (page != null && page > 1) 'page': page,
        if (sortBy != null) 'sort_by': sortBy,
      };
}

/// Renders the declared form fields and keeps the values in a map.
class ResourceFieldBuilder extends StatelessWidget {
  const ResourceFieldBuilder({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.hotelName,
    this.readOnly = false,
    this.errors = const {},
  });

  final List<ResourceField> fields;
  final Map<String, dynamic> values;
  final void Function(String name, dynamic value) onChanged;
  final String? hotelName;
  final bool readOnly;

  /// Field name → message, produced by [validate].
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    final visible = fields
        .where((f) => f.visibleWhen == null || f.visibleWhen!(values))
        .toList();
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _one(context, visible[i]),
        ],
      ],
    );
  }

  static Map<String, String> validate(
    List<ResourceField> fields,
    Map<String, dynamic> values,
  ) {
    final out = <String, String>{};
    for (final f in fields) {
      if (f.type == ResourceFieldType.signature) continue;
      final v = values[f.name];
      final empty = v == null || '$v'.trim().isEmpty;
      if (f.required && empty) {
        out[f.name] = '${f.label} is required';
        continue;
      }
      if (empty) continue;
      if (f.type == ResourceFieldType.number ||
          f.type == ResourceFieldType.money) {
        final n = asDouble(v, double.nan);
        if (n.isNaN) {
          out[f.name] = '${f.label} must be a number';
          continue;
        }
        if (f.min != null && n < f.min!) {
          out[f.name] = '${f.label} must be at least ${f.min}';
          continue;
        }
        if (f.max != null && n > f.max!) {
          out[f.name] = '${f.label} must be at most ${f.max}';
          continue;
        }
      }
      if (f.type == ResourceFieldType.date ||
          f.type == ResourceFieldType.dateTime) {
        if (asDate(v) == null) {
          out[f.name] = '${f.label} must be a valid date';
        }
      }
    }
    return out;
  }

  Widget _one(BuildContext context, ResourceField f) {
    final error = errors[f.name];
    final value = values[f.name];
    final disabled = readOnly || f.type == ResourceFieldType.signature;

    switch (f.type) {
      case ResourceFieldType.textarea:
        return AppField(
          label: f.label,
          required: f.required,
          hint: f.hint,
          error: error,
          child: AppTextInput(
            initialValue: asString(value),
            maxLines: f.maxLines,
            textCapitalization: TextCapitalization.sentences,
            enabled: !readOnly,
            onChanged: (v) => onChanged(f.name, v),
          ),
        );
      case ResourceFieldType.number:
        return AppField(
          label: f.label,
          required: f.required,
          hint: f.hint,
          error: error,
          child: AppNumberInput(
            controller: _numController(f, value),
            allowDecimal: f.maxLines > 1,
            enabled: !readOnly,
            onChanged: (v) => onChanged(f.name, asDouble(v)),
          ),
        );
      case ResourceFieldType.money:
        return AppField(
          label: f.label,
          required: f.required,
          hint: f.hint,
          error: error,
          child: AppMoneyInput(
            controller: _numController(f, value, money: true),
            enabled: !readOnly,
            onChanged: (v) => onChanged(f.name, asDouble(v)),
          ),
        );
      case ResourceFieldType.select:
        return AppField(
          label: f.label,
          required: f.required,
          hint: f.hint,
          error: error,
          child: _select(context, f, value, disabled),
        );
      case ResourceFieldType.date:
        return AppDateField(
          label: f.label,
          value: asDate(value),
          errorText: error,
          enabled: !readOnly,
          onChanged: (v) => onChanged(f.name, v?.toIso8601String()),
        );
      case ResourceFieldType.dateTime:
        return AppDateTimeField(
          label: f.label,
          value: asDate(value),
          errorText: error,
          onChanged: (v) => onChanged(f.name, v?.toIso8601String()),
        );
      case ResourceFieldType.switchField:
        return AppField(
          label: f.label,
          hint: f.helper,
          child: SwitchListTile.adaptive(
            value: asBool(value),
            onChanged: readOnly ? null : (v) => onChanged(f.name, v ? 1 : 0),
            contentPadding: EdgeInsets.zero,
            title: Text(
              asBool(value) ? 'Yes' : 'No',
              style: context.texts.bodyMedium,
            ),
          ),
        );
      case ResourceFieldType.signature:
        return AppField(
          label: f.label,
          hint: f.hint,
          child: AppSignaturePad(
            initialData: asString(value),
            onChanged: (v) => onChanged(f.name, v),
          ),
        );
      case ResourceFieldType.text:
        return AppField(
          label: f.label,
          required: f.required,
          hint: f.hint,
          error: error,
          child: AppTextInput(
            initialValue: asString(value),
            enabled: !readOnly,
            textCapitalization: f.name.contains('name') ||
                    f.name.contains('address') ||
                    f.name.contains('notes')
                ? TextCapitalization.words
                : TextCapitalization.none,
            onChanged: (v) => onChanged(f.name, v),
          ),
        );
    }
  }

  Widget _select(
    BuildContext context,
    ResourceField f,
    dynamic value,
    bool disabled,
  ) {
    final options = f.options.isEmpty && f.hotelScoped && hotelName != null
        ? [ResourceSelectOption(value: hotelName!, label: hotelName!)]
        : f.options;
    return AppSearchableSelect<String>(
      value: value == null ? null : asString(value),
      options: [
        for (final o in options)
          AppSelectOption<String>(value: o.value, label: o.label),
      ],
      enabled: !disabled,
      errorText: errors[f.name],
      clearable: !f.required,
      onChanged: (v) => onChanged(f.name, v),
    );
  }

  TextEditingController _numController(
    ResourceField f,
    dynamic value, {
    bool money = false,
  }) {
    final v = value == null ? '' : '$value';
    return TextEditingController(text: v.isEmpty ? '' : v)
      ..selection = TextSelection.collapsed(offset: v.length);
  }
}
