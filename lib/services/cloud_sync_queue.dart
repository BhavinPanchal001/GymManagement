import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A document change saved on this phone until the server acknowledges it.
class CloudChange {
  final String collection;
  final String documentId;
  final Map<String, dynamic>? data;

  const CloudChange(this.collection, this.documentId, this.data);

  Map<String, dynamic> toMap() => {
    'collection': collection,
    'documentId': documentId,
    'data': data,
  };

  factory CloudChange.fromMap(Map<String, dynamic> map) => CloudChange(
    map['collection'] as String,
    map['documentId'] as String,
    map['data'] == null ? null : Map<String, dynamic>.from(map['data'] as Map),
  );
}

class _PendingBatch {
  final String id;
  final List<CloudChange> changes;

  const _PendingBatch(this.id, this.changes);

  Map<String, dynamic> toMap() => {
    'id': id,
    'changes': changes.map((c) => c.toMap()).toList(),
  };

  factory _PendingBatch.fromMap(Map<String, dynamic> map) => _PendingBatch(
    map['id'] as String,
    (map['changes'] as List)
        .map((c) => CloudChange.fromMap(Map<String, dynamic>.from(c as Map)))
        .toList(),
  );
}

/// The queue is scoped to one owner and survives app restarts and sign-out.
/// Payment and receipt changes are uploaded in the same atomic batch.
class CloudSyncQueue extends ChangeNotifier {
  final SharedPreferences preferences;
  final String userId;
  final Future<void> Function(List<CloudChange>) upload;
  final Duration retryDelay;
  final Duration uploadTimeout;
  final List<_PendingBatch> _pending = [];
  Future<void> _persistTail = Future.value();
  Future<void>? _uploadFuture;
  Timer? _retryTimer;
  bool _closed = false;
  int _sequence = 0;
  String? lastError;

  CloudSyncQueue({
    required this.preferences,
    required this.userId,
    required this.upload,
    this.retryDelay = const Duration(seconds: 30),
    this.uploadTimeout = const Duration(seconds: 15),
  });

  String get _key => 'gym_${userId}_cloud_outbox_v1';
  int get pendingCount =>
      _pending.fold(0, (count, b) => count + b.changes.length);
  bool get isUploading => _uploadFuture != null;

  void load() {
    final saved = preferences.getString(_key);
    if (saved == null) return;
    final batches = json.decode(saved) as List;
    _pending.addAll(
      batches.map(
        (b) => _PendingBatch.fromMap(Map<String, dynamic>.from(b as Map)),
      ),
    );
  }

  Future<void> _changePending(void Function(List<_PendingBatch>) update) {
    final write = _persistTail.catchError((Object _) {}).then((_) async {
      final next = List<_PendingBatch>.from(_pending);
      update(next);
      final saved = json.encode(next.map((b) => b.toMap()).toList());
      bool stored;
      try {
        stored = await preferences.setString(_key, saved);
      } catch (_) {
        await preferences.reload();
        rethrow;
      }
      if (!stored) {
        await preferences.reload();
        throw StateError('Could not save changes on this phone.');
      }
      _pending
        ..clear()
        ..addAll(next);
      if (!_closed) notifyListeners();
    });
    _persistTail = write;
    return write;
  }

  Future<void> enqueue(
    List<CloudChange> changes, {
    bool autoFlush = true,
  }) async {
    if (_closed) throw StateError('This account is no longer connected.');
    if (changes.isEmpty) return;
    if (changes.length > 450) {
      throw ArgumentError('Split large updates into batches of 450 changes.');
    }
    // Copy payloads so later edits cannot change an already queued receipt.
    final copied = changes
        .map(
          (c) => CloudChange.fromMap(
            json.decode(json.encode(c.toMap())) as Map<String, dynamic>,
          ),
        )
        .toList();
    final batch = _PendingBatch(
      '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}',
      copied,
    );
    await _changePending((next) => next.add(batch));
    if (!_closed && autoFlush) unawaited(flush());
  }

  Future<void> enqueueAll(
    List<CloudChange> changes, {
    bool autoFlush = true,
  }) async {
    if (_closed) throw StateError('This account is no longer connected.');
    if (changes.isEmpty) return;
    final copied = changes
        .map(
          (change) => CloudChange.fromMap(
            json.decode(json.encode(change.toMap())) as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
    final batches = <_PendingBatch>[];
    for (var index = 0; index < copied.length; index += 450) {
      batches.add(
        _PendingBatch(
          '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}',
          copied.sublist(index, (index + 450).clamp(0, copied.length)),
        ),
      );
    }
    await _changePending((next) => next.addAll(batches));
    if (!_closed && autoFlush) unawaited(flush());
  }

  /// Apply pending local edits over an arriving server snapshot.
  Map<String, Map<String, dynamic>> overlay(
    String collection,
    Map<String, Map<String, dynamic>> snapshot,
  ) {
    final merged = Map<String, Map<String, dynamic>>.from(snapshot);
    for (final batch in _pending) {
      for (final change in batch.changes) {
        if (change.collection != collection) continue;
        if (change.data == null) {
          merged.remove(change.documentId);
        } else {
          merged[change.documentId] = change.data!;
        }
      }
    }
    return merged;
  }

  Future<void> flush() {
    if (_closed) return Future.value();
    _retryTimer?.cancel();
    return _uploadFuture ??= _drain().whenComplete(() {
      _uploadFuture = null;
      if (!_closed) notifyListeners();
    });
  }

  Future<void> _drain() async {
    try {
      while (!_closed && _pending.isNotEmpty) {
        await _persistTail.catchError((Object _) {});
        if (_closed || _pending.isEmpty) return;
        final batch = _pending.first;
        await upload(batch.changes).timeout(uploadTimeout);
        if (_closed) return;
        await _changePending((next) => next.remove(batch));
        lastError = null;
        notifyListeners();
      }
    } catch (_) {
      if (_closed) return;
      lastError = 'Changes are saved on this phone, but could not be uploaded.';
      notifyListeners();
      _retryTimer = Timer(retryDelay, () => unawaited(flush()));
    }
  }

  @override
  void dispose() {
    _closed = true;
    _retryTimer?.cancel();
    super.dispose();
  }
}
