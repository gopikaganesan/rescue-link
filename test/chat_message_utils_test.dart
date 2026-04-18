import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescue_link/core/utils/chat_message_utils.dart';

void main() {
  group('extractYoutubeVideoIds', () {
    test('extracts multiple ids in order and removes duplicates', () {
      const text = '''
      Watch this https://www.youtube.com/watch?v=Y107-A8Ny-4
      Also https://youtu.be/PQV71INDaqY
      Repeat https://www.youtube.com/watch?v=Y107-A8Ny-4
      ''';

      final ids = extractYoutubeVideoIds(text);

      expect(ids, ['Y107-A8Ny-4', 'PQV71INDaqY']);
    });

    test('returns empty when no youtube link exists', () {
      const text = 'No links here, just steps and phone numbers 112.';

      final ids = extractYoutubeVideoIds(text);

      expect(ids, isEmpty);
    });
  });

  group('pickLatestByUpdatedAt', () {
    test('picks map with latest timestamp', () {
      final docs = <Map<String, dynamic>>[
        {'id': 'older', 'updatedAt': Timestamp.fromMillisecondsSinceEpoch(10)},
        {'id': 'newest', 'updatedAt': Timestamp.fromMillisecondsSinceEpoch(30)},
        {'id': 'middle', 'updatedAt': Timestamp.fromMillisecondsSinceEpoch(20)},
      ];

      final latest = pickLatestByUpdatedAt<Map<String, dynamic>>(
        docs,
        (item) => item['updatedAt'],
      );

      expect(latest?['id'], 'newest');
    });

    test('handles null or missing updatedAt values', () {
      final docs = <Map<String, dynamic>>[
        {'id': 'missing'},
        {'id': 'dated', 'updatedAt': DateTime.fromMillisecondsSinceEpoch(50)},
      ];

      final latest = pickLatestByUpdatedAt<Map<String, dynamic>>(
        docs,
        (item) => item['updatedAt'],
      );

      expect(latest?['id'], 'dated');
    });
  });
}
