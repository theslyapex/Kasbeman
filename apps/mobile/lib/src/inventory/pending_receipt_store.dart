import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class PendingReceiptRequest {
  const PendingReceiptRequest({
    required this.saleId,
    required this.amount,
    required this.paymentMethod,
    required this.idempotencyKey,
    this.reference,
    this.notes,
  });

  final String saleId;
  final num amount;
  final String paymentMethod;
  final String idempotencyKey;
  final String? reference;
  final String? notes;

  Map<String, Object?> toJson() => {
        'version': 1,
        'sale_id': saleId,
        'amount': amount.toString(),
        'payment_method': paymentMethod,
        'idempotency_key': idempotencyKey,
        'reference': reference,
        'notes': notes,
      };

  factory PendingReceiptRequest.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Unsupported pending receipt format.');
    }
    final saleId = decoded['sale_id'];
    final amountValue = decoded['amount'];
    final paymentMethod = decoded['payment_method'];
    final idempotencyKey = decoded['idempotency_key'];
    final amount = amountValue is String ? num.tryParse(amountValue) : null;
    const methods = {'cash', 'card', 'bank_transfer', 'cheque', 'other'};
    if (saleId is! String ||
        saleId.isEmpty ||
        amount == null ||
        amount <= 0 ||
        paymentMethod is! String ||
        !methods.contains(paymentMethod) ||
        idempotencyKey is! String ||
        idempotencyKey.isEmpty) {
      throw const FormatException('Invalid pending receipt data.');
    }
    final reference = decoded['reference'];
    final notes = decoded['notes'];
    if ((reference != null && reference is! String) ||
        (notes != null && notes is! String)) {
      throw const FormatException('Invalid pending receipt text.');
    }
    return PendingReceiptRequest(
      saleId: saleId,
      amount: amount,
      paymentMethod: paymentMethod,
      idempotencyKey: idempotencyKey,
      reference: reference as String?,
      notes: notes as String?,
    );
  }
}

class PendingReceiptStore {
  PendingReceiptStore({SecureKeyValueStore? storage})
      : _storage = storage ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _storage;

  String _key({
    required String userId,
    required String businessId,
    required String customerId,
  }) =>
      'kasbeman.pending_receipt.v1.'
      '${Uri.encodeComponent(userId)}.'
      '${Uri.encodeComponent(businessId)}.'
      '${Uri.encodeComponent(customerId)}';

  Future<PendingReceiptRequest?> read({
    required String userId,
    required String businessId,
    required String customerId,
  }) async {
    final raw = await _storage.read(
      key: _key(userId: userId, businessId: businessId, customerId: customerId),
    );
    return raw == null ? null : PendingReceiptRequest.fromJson(raw);
  }

  Future<void> save({
    required String userId,
    required String businessId,
    required String customerId,
    required PendingReceiptRequest request,
  }) =>
      _storage.write(
        key: _key(userId: userId, businessId: businessId, customerId: customerId),
        value: jsonEncode(request.toJson()),
      );

  Future<void> clear({
    required String userId,
    required String businessId,
    required String customerId,
  }) =>
      _storage.delete(
        key: _key(userId: userId, businessId: businessId, customerId: customerId),
      );
}
