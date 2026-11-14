import 'package:flutter/foundation.dart';

class DeletionStatus {
  const DeletionStatus(
    this.state, {
    this.step = '',
    this.canRetry = false,
    this.retainedUntil,
    this.providerRetentionUntil,
  });
  final String state, step;
  final bool canRetry;
  final DateTime? retainedUntil, providerRetentionUntil;
  factory DeletionStatus.fromMap(Map<String, dynamic> value) => DeletionStatus(
    value['state'] as String,
    step: value['step'] as String? ?? '',
    canRetry: value['canRetry'] == true,
    retainedUntil: value['retainedUntil'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (value['retainedUntil'] as num).toInt(),
          )
        : null,
    providerRetentionUntil: value['providerRetentionUntil'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (value['providerRetentionUntil'] as num).toInt(),
          )
        : null,
  );
}

abstract class PrivacyRepository extends ChangeNotifier {
  String? get receiptExport => null;
  bool get pending;
  bool get hasPassword;
  bool get hasGoogle;
  Future<void> request({String? password, bool google = false});
  Future<DeletionStatus> status();
  Future<void> retry();
  Future<void> closeCompletedReceipt();
  Future<void> forgetLocalReceipt();
}
