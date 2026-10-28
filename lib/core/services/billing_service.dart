import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:in_app_purchase/in_app_purchase.dart';

/// Покупки PRO (P2 ТЗ). Интерфейс позволяет платформе без магазина
/// (web/десктоп-тесты) использовать имитацию.
abstract class BillingService {
  bool get isAvailable;
  Future<bool> purchasePro();
  Future<bool> restorePro();
}

/// Идентификатор продукта в App Store Connect / Google Play Console.
const String kProProductId = 'smart_notes_pro_monthly';

class InAppPurchaseBillingService implements BillingService {
  final InAppPurchase _iap = InAppPurchase.instance;
  bool? _availableCache;

  @override
  bool get isAvailable => _availableCache ?? false;

  Future<bool> _checkAvailable() async {
    if (kIsWeb) {
      _availableCache = false;
      return false;
    }
    try {
      _availableCache = await _iap.isAvailable();
      return _availableCache!;
    } catch (_) {
      _availableCache = false;
      return false;
    }
  }

  @override
  Future<bool> purchasePro() async {
    if (!await _checkAvailable()) return false;

    final response = await _iap.queryProductDetails({kProProductId});
    if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
      return false;
    }
    final product = response.productDetails.first;
    final purchaseStream = _iap.purchaseStream;
    final completer = Completer<bool>();

    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = purchaseStream.listen((purchases) {
      for (final p in purchases) {
        if (p.productID != kProProductId) continue;
        switch (p.status) {
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            if (!completer.isCompleted) completer.complete(true);
            sub.cancel();
          case PurchaseStatus.error:
          case PurchaseStatus.canceled:
            if (!completer.isCompleted) completer.complete(false);
            sub.cancel();
          case PurchaseStatus.pending:
            break;
        }
      }
    });

    final ok = await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!ok) {
      await sub.cancel();
      return false;
    }
    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () async {
        await sub.cancel();
        return false;
      },
    );
  }

  @override
  Future<bool> restorePro() async {
    if (!await _checkAvailable()) return false;
    try {
      await _iap.restorePurchases();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Заглушка для web/тестов: покупка всегда «успешна».
class SimulatedBillingService implements BillingService {
  @override
  bool get isAvailable => false;
  @override
  Future<bool> purchasePro() async => true;
  @override
  Future<bool> restorePro() async => true;
}
