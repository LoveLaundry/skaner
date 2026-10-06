/// Shared parsing for the two guest pages that accept a code off a printed
/// tag or a quotation.
class GuestTag {
  GuestTag._();

  /// Extracts the identifier from whatever the guest pasted or scanned.
  ///
  /// A printed QR tag scans as a full URL (`https://…/tags/AB-123`) but a
  /// guest typing into the field usually gives the bare code, so both are
  /// accepted by taking the last non-empty path segment.
  ///
  /// Returns `null` when there is nothing to look up. The old code called
  /// `.last` on the segment list, so pasting `/`, `//` or `?` — all of which
  /// pass an `isEmpty` check on the raw input — threw a `StateError` and
  /// stranded the screen on its spinner.
  static String? slugOf(String raw) {
    final segments = raw
        .trim()
        .split('?')
        .first
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return segments.isEmpty ? null : segments.last.trim();
  }
}
