import 'package:cqrs_offline_sync/cqrs_offline_sync.dart';
import 'package:test/test.dart';

void main() {
  group('SyncCommandResult', () {
    test('serializes reasonCode only when non-null', () {
      final result = SyncCommandResult(
        opId: 'op-1',
        status: SyncCommandResultStatus.rejectedConflictStale,
        latestCursor: SyncCursor('1'),
        reasonCode: SyncCommandResultReasonCodes.recoverableMissingRow,
        reason: 'Row missing',
      );

      final json = result.toJson();
      expect(json['reasonCode'], SyncCommandResultReasonCodes.recoverableMissingRow);
      expect(json['reason'], 'Row missing');
    });

    test('omits reasonCode from JSON when null', () {
      final result = SyncCommandResult(
        opId: 'op-1',
        status: SyncCommandResultStatus.applied,
        latestCursor: SyncCursor('1'),
        reason: 'Applied',
      );

      final json = result.toJson();
      expect(json.containsKey('reasonCode'), isFalse);
      expect(json['reason'], 'Applied');
    });

    test('parses reasonCode from JSON', () {
      final json = <String, dynamic>{
        'opId': 'op-1',
        'status': 'rejected_conflict_stale',
        'latestCursor': '1',
        'reasonCode': SyncCommandResultReasonCodes.recoverableMissingRow,
        'reason': 'Row missing',
      };

      final result = SyncCommandResult.fromJson(json);
      expect(result.reasonCode, SyncCommandResultReasonCodes.recoverableMissingRow);
      expect(result.reason, 'Row missing');
    });

    test('treats empty reasonCode as null', () {
      final json = <String, dynamic>{
        'opId': 'op-1',
        'status': 'applied',
        'latestCursor': '1',
        'reasonCode': '',
        'reason': 'Applied',
      };

      final result = SyncCommandResult.fromJson(json);
      expect(result.reasonCode, isNull);
      expect(result.reason, 'Applied');
    });

    test('treats missing reasonCode as null', () {
      final json = <String, dynamic>{
        'opId': 'op-1',
        'status': 'applied',
        'latestCursor': '1',
      };

      final result = SyncCommandResult.fromJson(json);
      expect(result.reasonCode, isNull);
    });
  });

  group('SyncCommandResultReasonCodes', () {
    test('recoverableMissingRow has expected wire value', () {
      expect(
        SyncCommandResultReasonCodes.recoverableMissingRow,
        'recoverable_missing_row',
      );
    });
  });
}
