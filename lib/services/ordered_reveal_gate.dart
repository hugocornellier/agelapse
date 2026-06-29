/// Releases stabilized-photo reveal notifications to the UI in strict
/// timestamp order.
///
/// The parallel transform-cache fast path in the stabilization service finishes
/// cache-hit photos out of order, which would otherwise make gallery thumbnails
/// pop in out of sequence (e.g. day 101 before day 100). The service builds one
/// gate per batch from the work list (already ascending by timestamp). As each
/// photo finishes, [complete] records it and returns the contiguous run of
/// timestamps that are now safe to reveal: a photo is held back until every
/// earlier photo in the batch has also finished, then released. When a
/// straggling earlier photo finally lands, every buffered later photo is
/// flushed at once, in order.
///
/// "Finished" means the photo reached a terminal outcome (success or failure),
/// not necessarily that it produced a visible image. Both the serial slow path
/// and the parallel fast path report every photo exactly once, so the cursor
/// always advances and can never deadlock on a photo that failed or found no
/// faces.
class OrderedRevealGate {
  OrderedRevealGate(List<String> order)
      : _order = List<String>.unmodifiable(order);

  /// Batch timestamps in reveal order (ascending).
  final List<String> _order;

  /// Timestamps that have finished stabilizing.
  final Set<String> _done = <String>{};

  /// Index into [_order] of the next photo awaiting reveal.
  int _cursor = 0;

  /// Whether every photo in the batch has been released for reveal.
  bool get isDrained => _cursor >= _order.length;

  /// Marks [timestamp] finished and returns the timestamps to reveal now, in
  /// ascending order. Returns empty when an earlier photo in the batch has not
  /// finished yet (this photo is buffered until it does), when [timestamp] has
  /// already been released, or when [timestamp] is not part of this batch.
  List<String> complete(String timestamp) {
    _done.add(timestamp);
    final released = <String>[];
    while (_cursor < _order.length && _done.contains(_order[_cursor])) {
      released.add(_order[_cursor]);
      _cursor++;
    }
    return released;
  }
}
