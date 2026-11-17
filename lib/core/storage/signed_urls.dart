import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_bootstrap.dart';

/// A private file: bucket + path inside it.
typedef StorageFile = ({String bucket, String path});

/// Asks Storage for 1-hour links to private files.
typedef SignedUrlFetcher =
    Future<Map<String, String>> Function(String bucket, List<String> paths);

/// Real fetcher (replaced in tests).
final signedUrlFetcherProvider = Provider<SignedUrlFetcher>((ref) {
  return (bucket, paths) async {
    final client = ref.read(supabaseClientProvider);
    final results = await client.storage
        .from(bucket)
        .createSignedUrlsResult(paths, 3600);
    return {
      for (final r in results)
        if (r is SignedUrlSuccess) r.path: r.signedUrl,
    };
  };
});

/// Caches signed links and asks for several at once (one request per
/// bucket per frame instead of one per photo).
class SignedUrlCache {
  SignedUrlCache(this._fetch);

  final SignedUrlFetcher _fetch;
  final Map<StorageFile, (String, DateTime)> _cache = {};
  final Map<StorageFile, Completer<String?>> _waiting = {};
  bool _scheduled = false;

  Future<String?> urlFor(StorageFile file) {
    final cached = _cache[file];
    if (cached != null && DateTime.now().isBefore(cached.$2)) {
      return Future.value(cached.$1);
    }
    final pending = _waiting[file];
    if (pending != null) return pending.future;
    final completer = Completer<String?>();
    _waiting[file] = completer;
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_flush);
    }
    return completer.future;
  }

  Future<void> _flush() async {
    _scheduled = false;
    final batch = Map<StorageFile, Completer<String?>>.from(_waiting);
    _waiting.clear();
    final byBucket = <String, List<StorageFile>>{};
    for (final f in batch.keys) {
      byBucket.putIfAbsent(f.bucket, () => []).add(f);
    }
    for (final entry in byBucket.entries) {
      try {
        final urls = await _fetch(entry.key, [
          for (final f in entry.value) f.path,
        ]);
        // Links live 60 minutes; renew after 50.
        final expires = DateTime.now().add(const Duration(minutes: 50));
        for (final f in entry.value) {
          final url = urls[f.path];
          if (url != null) _cache[f] = (url, expires);
          batch[f]!.complete(url);
        }
      } catch (_) {
        for (final f in entry.value) {
          batch[f]!.complete(null);
        }
      }
    }
  }
}

final signedUrlCacheProvider = Provider<SignedUrlCache>(
  (ref) => SignedUrlCache(ref.watch(signedUrlFetcherProvider)),
);

final signedUrlProvider = FutureProvider.family<String?, StorageFile>(
  (ref, file) => ref.watch(signedUrlCacheProvider).urlFor(file),
);
