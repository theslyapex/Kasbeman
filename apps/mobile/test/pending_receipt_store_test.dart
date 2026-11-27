import 'package:flutter_test/flutter_test.dart';
import 'package:kasbeman_mobile/src/inventory/pending_receipt_store.dart';

class MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

void main() {
  group('PendingReceiptStore', () {
    late MemorySecureKeyValueStore storage;
    late PendingReceiptStore store;

    setUp(() {
      storage = MemorySecureKeyValueStore();
      store = PendingReceiptStore(storage: storage);
    });

    const request = PendingReceiptRequest(
      saleId: 'sale-1',
      amount: 125000.5,
      paymentMethod: 'bank_transfer',
      idempotencyKey: 'request-key-1',
      reference: 'tracking-123',
      notes: 'customer receipt note',
    );

    test('persists and restores the exact receipt payload', () async {
      await store.save(
        userId: 'user-1',
        businessId: 'business-1',
        customerId: 'customer-1',
        request: request,
      );

      final restored = await store.read(
        userId: 'user-1',
        businessId: 'business-1',
        customerId: 'customer-1',
      );

      expect(restored?.saleId, request.saleId);
      expect(restored?.amount, request.amount);
      expect(restored?.paymentMethod, request.paymentMethod);
      expect(restored?.idempotencyKey, request.idempotencyKey);
      expect(restored?.reference, request.reference);
      expect(restored?.notes, request.notes);
    });

    test('isolates requests by user, business, and customer', () async {
      await store.save(
        userId: 'user-1',
        businessId: 'business-1',
        customerId: 'customer-1',
        request: request,
      );

      expect(
        await store.read(
          userId: 'user-2',
          businessId: 'business-1',
          customerId: 'customer-1',
        ),
        isNull,
      );
      expect(
        await store.read(
          userId: 'user-1',
          businessId: 'business-2',
          customerId: 'customer-1',
        ),
        isNull,
      );
      expect(
        await store.read(
          userId: 'user-1',
          businessId: 'business-1',
          customerId: 'customer-2',
        ),
        isNull,
      );
    });

    test('clears only the selected pending request', () async {
      await store.save(
        userId: 'user-1',
        businessId: 'business-1',
        customerId: 'customer-1',
        request: request,
      );
      await store.save(
        userId: 'user-1',
        businessId: 'business-1',
        customerId: 'customer-2',
        request: request,
      );

      await store.clear(
        userId: 'user-1',
        businessId: 'business-1',
        customerId: 'customer-1',
      );

      expect(
        await store.read(
          userId: 'user-1',
          businessId: 'business-1',
          customerId: 'customer-1',
        ),
        isNull,
      );
      expect(
        await store.read(
          userId: 'user-1',
          businessId: 'business-1',
          customerId: 'customer-2',
        ),
        isNotNull,
      );
    });

    test('rejects malformed secure-storage payloads', () async {
      storage.values['kasbeman.pending_receipt.v1.user-1.business-1.customer-1'] =
          '{"version":1,"sale_id":"sale-1","amount":"0","payment_method":"cash","idempotency_key":"key"}';

      expect(
        () => store.read(
          userId: 'user-1',
          businessId: 'business-1',
          customerId: 'customer-1',
        ),
        throwsFormatException,
      );
    });
  });
}
