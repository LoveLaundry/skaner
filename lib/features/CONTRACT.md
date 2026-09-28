# Feature screen contract (mobile port)

Project: `/home/dulshan/Desktop/LoveLaundry.LK/system-manegment/skaner`
Source of truth: `../quotations-ui` (React). Port behaviour, not markup.

Package: `love_mobi`. Read `lib/` before writing code — do not guess APIs.

## Absolute rules

1. **No new dependencies.** Use only what `pubspec.yaml` already lists.
2. **No comments unless the code is non-obvious.** Match the existing terse style.
3. `dart analyze lib` must report **No issues found**. Verify before you finish.
4. Do **not** edit files outside the ones you were told to create, except to
   add a new file. If you believe an existing shared file is wrong, report it
   instead of editing it.
5. Prefer the shared kit over raw Material widgets. The design system is
   already ported; using `FilledButton` directly is a defect.

## Layering

```
lib/core/…     transport, storage, offline outbox, models, utils  (read-only for you)
lib/data/…     ResourceController, asRows/pick/str/… , ResourceDefinition
lib/ui/theme.dart      AppColors via context.c, Radii, Shadows, AppFontSize, AppTheme
lib/ui/kit/…   primitives, inputs, feedback, data, shell_parts
lib/state/…    AppServices, AppScope, AuthState, HotelScope, ThemeState
lib/features/… screens (yours)
```

Read access to services:

```dart
final services = AppScope.of(context);   // in build(), to rebuild on change
final services = AppScope.read(context);  // in handlers, no subscription
services.api.get(service, path, query: {...})   // → dynamic
services.auth.hasPermission('some.permission')
services.auth.user?.displayName
services.hotels.selectedHotel / .queryParam / .hotels / .isAdmin
services.cache.invalidateResource('bills')
```

## HTTP

```dart
final payload = await services.api.get(ServiceNames.bills, '/bills', query: {'limit': 25});
final rows = asRows(payload);                       // handles {items}/{data}/[…]
final name = str(row, ['client_name']);             // tolerant key reading
final total = intOf(row, ['total_amount']);
final d = numOf(row, ['amount']); final b = boolOf(row, ['is_paid']);
final when = dateOf(row, ['delivery_date']);        // DateTime?
```

Writes go through `services.api`:

```dart
await services.api.post(ServiceNames.bills, '/bills', body: payload);
await services.api.patch(ServiceNames.bills, '/bills/12', body: payload);
await services.api.delete(ServiceNames.bills, '/bills/12');
```

They **queue automatically when offline** and return a `QueuedResponse`
marker. It is **returned, not thrown**, so a catch clause can never see it —
checking the result is the only correct pattern:

```dart
final result = await services.api.post(ServiceNames.bills, '/bills', body: p);
if (result is QueuedResponse) AppToast.info(context, 'Queued — will sync');
else                        AppToast.success(context, 'Saved');
```

`runWrite` in `lib/data/write_outcome.dart` wraps this; prefer it. Never write
`on QueuedResponse` — it is dead code that reports success for a write the
server never received. Do not discard the result with `.then((_) {})`
either; that drops the marker on the floor.

`e.statusCode` (401/403/404/400/422/null), `e.isValidation`, `e.isRetryable`,
`e.fieldErrors` (Map<String,String> for 422) are available.

Service names: `ServiceNames.quotation | .bills | .users | .workers | .management | .ai`

## Screen anatomy

Every screen is a `Scaffold`. Signed-in screens render inside the shell
automatically — **do not** add your own `Drawer` or `BottomNavigationBar`.

```dart
Scaffold(
  appBar: AppBar(title: Text('Gate passes')),
  body: Column(children: [
    AppSyncStatusBar(status: ctrl.status, updatedAt: ctrl.lastUpdated, label: 'Gate passes'),
    AppOfflineSyncBar(engine: services.sync),
    Expanded(child: /* list, form, or EmptyState */),
  ]),
)
```

### Loading a remote list

```dart
late final ResourceController<List<Map<String,dynamic>>> _c;
@override void initState() {
  super.initState();
  _c = ResourceController(
    key: 'gatepasses',                 // cache prefix; engine invalidates on this
    cache: AppScope.read(context).cache,
    fetcher: () async { /* …api call, return asRows(payload) */ },
  );
  _c.addListener(_onChanged);          // call setState here
  _c.load(force: true);                // or after first frame
}
@override void dispose() { _c.removeListener(_onChanged); _c.dispose(); super.dispose(); }
```

`_c` gives `data`, `phase` (`LoadPhase.loading|ready|failed|idle`), `status`
(`CacheStatus.fresh|syncing|stale|offline|syncedFailed`), `error`, `lastUpdated`,
`isLoading`, `hasData`, `refresh()`, `setData()`.

Rule: **never blank the list on a failed refresh.** If `_c.data` is non-empty,
keep showing it and let `AppSyncStatusBar` explain the state. Show
`AppErrorState(message:, onRetry:)` only when there is genuinely nothing to
show.

### A collection list

Either hand-roll with `ListView.builder` + `RefreshIndicator`, or use the
generic `ResourceListPage` when the module really is a flat CRUD screen
(declare a `ResourceDefinition` and pass it — see
`lib/features/common/resource_list_page.dart`).

Use `AppDataTable<T>` with `DataColumn`-style `AppDataColumn<T>(label:, value:)`
— on a phone it renders as cards, so a table never scrolls sideways.

### Forms

`AppField(label:, required:, hint:, error:, child: …)` wraps every control.
Controls: `AppTextInput`, `AppNumberInput`, `AppMoneyInput`,
`AppSearchableSelect<T>`, `AppDateField`, `AppDateTimeField`,
`AppSignaturePad`, `SwitchListTile`.

`AppTextInput` takes **either** a `controller` **or** `initialValue`.

Validate before submitting; show the message in the field's `error` slot so the
block does not grow when an error appears.

### Feedback

- `AppToast.success / .error / .info / .warning(context, msg)`
- `AppConfirmDialog.show(context, title:, message:, confirmLabel:, destructive:) → Future<bool>`
- `AppDialog.show<T>(context, title:, body:, actions: [...]) → Future<T?>`
- `AppEmptyState(title:, message:, icon:, action:)`
- `AppNotice(message:, tone:, title:, onClose:)`
- `AppSpinner()`, `AppLoader()`, `AppSkeletonList()`

### Buttons

`AppButton(label:, onPressed:, variant: AppButtonVariant.primary|secondary|ghost|outline|warning|danger|dangerGhost|link, size: AppButtonSize.xs|sm|md|lg, icon:, loading:, expand:, block:)`

`AppButton.icon(icon:, tooltip:, onPressed:, variant:, size:)`

Loading keeps the label and shows a spinner; the control must not change width
mid-submit.

### Formatting

`Fmt.money / .amount / .count / .qty / .percent / .date / .dateShort / .dateTime
/ .time / .monthYear / .isoDate / .isoDateTime / .today / .nowIso / .relative /
.parseDate` — see `lib/core/utils/formatting.dart`. Do not hand-roll date or
number formatting.

## Visual contract (from the web app)

- Colour carries **meaning** (status), never decoration.
- Hairline borders separate surfaces; shadows only for overlays.
- One radius scale: `Radii.xs|sm|md|lg|xl|pill`.
- Nothing animates for decoration — only for state changes.
- Touch targets ≥ 44px. A phone operator may be wearing gloves.
- Every list must handle the empty, loading, error and offline states.
- Statuses use `AppBadge(label, tone: AppTone.neutral|brand|success|warning|danger|info)`.
  `BillStatusBadge(status:)` and `VerificationStatusBadge(status:)` already
  encode the canonical mappings — use them rather than inventing colours.

## Permissions

`services.auth.hasPermission(p)`. Admins pass everything. Gate write affordances
behind the module's write permission and whole screens behind the read
permission. Use the same permission strings the web app uses.
