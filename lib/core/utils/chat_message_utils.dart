import 'package:cloud_firestore/cloud_firestore.dart';

List<String> extractYoutubeVideoIds(String text) {
  final youtubeUrlPattern =
      RegExp(r'(?:youtube\.com\/watch\?v=|youtu\.be\/)([A-Za-z0-9_-]{11})');
  final orderedIds = <String>[];
  for (final match in youtubeUrlPattern.allMatches(text)) {
    final videoId = match.group(1);
    if (videoId != null && !orderedIds.contains(videoId)) {
      orderedIds.add(videoId);
    }
  }
  return orderedIds;
}

T? pickLatestByUpdatedAt<T>(
  Iterable<T> items,
  dynamic Function(T item) readUpdatedAt,
) {
  T? latest;
  var latestMillis = -1;

  for (final item in items) {
    final currentMillis = _toMillis(readUpdatedAt(item));
    if (latest == null || currentMillis > latestMillis) {
      latest = item;
      latestMillis = currentMillis;
    }
  }

  return latest;
}

int _toMillis(dynamic value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  }
  if (value is DateTime) {
    return value.millisecondsSinceEpoch;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}
