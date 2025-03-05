import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flet/flet.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

class InAppPurchaseControl extends StatefulWidget {
  final Control control;
  final FletControlBackend backend;

  const InAppPurchaseControl({
    Key? key,
    required this.control,
    required this.backend,
  }) : super(key: key);

  @override
  State<InAppPurchaseControl> createState() => _InAppPurchaseControlState();
}

class _InAppPurchaseControlState extends State<InAppPurchaseControl> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  List<ProductDetails> _products = [];

  @override
  void initState() {
    super.initState();

    // Listen to purchase updates
    final Stream<List<PurchaseDetails>> purchaseUpdated =
        _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _listenToPurchaseUpdated,
      onDone: () {
        _subscription.cancel();
      },
      onError: (error) {
        widget.backend.triggerControlEvent(
          widget.control.id,
          "purchase_error",
          error.toString(),
        );
      },
    );

    // Subscribe to backend methods
    widget.backend.subscribeMethods(
      widget.control.id,
      (methodName, args) async {
        switch (methodName) {
          case "initialize":
            await _initializeStore();
            break;
          case "query_products":
            var productIds = args["productIds"] as List<dynamic>;
            if (productIds.isNotEmpty) {
              await _queryProducts(productIds.cast<String>());
            }
            break;
          case "buy_product":
            var productId = args["productId"];
            if (productId != null) {
              await _buyProduct(productId);
            }
            break;
          case "restore_purchases":
            await _restorePurchases();
            break;
        }
        return null;
      },
    );
  }

  Future<void> _initializeStore() async {
    final bool available = await _inAppPurchase.isAvailable();
    if (!available) {
      widget.backend.triggerControlEvent(
        widget.control.id,
        "purchase_error",
        "Store not available",
      );
      return;
    }
  }

  Future<void> _queryProducts(List<String> productIds) async {
    try {
      final ProductDetailsResponse response =
          await _inAppPurchase.queryProductDetails(productIds.toSet());

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('Products not found: ${response.notFoundIDs}');
      }

      _products = response.productDetails;

      // Convert to JSON and trigger event
      final List<Map<String, dynamic>> productsJson = _products.map((product) {
        return {
          'id': product.id,
          'title': product.title,
          'description': product.description,
          'price': product.price,
          'rawPrice': product.rawPrice,
          'currencyCode': product.currencyCode,
          'currencySymbol': _getCurrencySymbol(product),
          'type': _getProductType(product),
        };
      }).toList();

      widget.backend.triggerControlEvent(
        widget.control.id,
        "products_ready",
        jsonEncode(productsJson),
      );
    } catch (e) {
      widget.backend.triggerControlEvent(
        widget.control.id,
        "purchase_error",
        "Failed to query products: $e",
      );
    }
  }

  String _getCurrencySymbol(ProductDetails product) {
    // Extract currency symbol from price string if possible
    final priceString = product.price;
    if (priceString.isNotEmpty) {
      final firstChar = priceString[0];
      if (firstChar != '0' &&
          firstChar != '1' &&
          firstChar != '2' &&
          firstChar != '3' &&
          firstChar != '4' &&
          firstChar != '5' &&
          firstChar != '6' &&
          firstChar != '7' &&
          firstChar != '8' &&
          firstChar != '9') {
        return firstChar;
      }
    }
    return product.currencyCode;
  }

  String _getProductType(ProductDetails product) {
    if (product is GooglePlayProductDetails) {
      final productDetails = product.productDetails;
      if (productDetails.subscriptionOfferDetails != null) {
        return 'subscription';
      }
      return 'consumable'; // Default for Google Play
    }

    return 'consumable'; // Default
  }

  Future<void> _buyProduct(String productId) async {
    final ProductDetails? product = _products.firstWhereOrNull(
      (p) => p.id == productId,
    );

    if (product == null) {
      widget.backend.triggerControlEvent(
        widget.control.id,
        "purchase_error",
        "Product not found: $productId",
      );
      return;
    }

    final PurchaseParam purchaseParam = PurchaseParam(
      productDetails: product,
    );

    try {
      // Is it a subscription?
      if (_getProductType(product) == 'subscription') {
        await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      } else {
        await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
      }
    } catch (e) {
      widget.backend.triggerControlEvent(
        widget.control.id,
        "purchase_error",
        "Purchase failed: $e",
      );
    }
  }

  Future<void> _restorePurchases() async {
    try {
      await _inAppPurchase.restorePurchases();
    } catch (e) {
      widget.backend.triggerControlEvent(
        widget.control.id,
        "purchase_error",
        "Restore failed: $e",
      );
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _sendPurchaseUpdate(purchaseDetails, 'pending');
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        _sendPurchaseUpdate(
            purchaseDetails,
            purchaseDetails.status == PurchaseStatus.purchased
                ? 'purchased'
                : 'restored');

        // Complete the transaction
        if (purchaseDetails.pendingCompletePurchase) {
          InAppPurchase.instance.completePurchase(purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        _sendPurchaseUpdate(purchaseDetails, 'error',
            errorMessage: purchaseDetails.error?.message ?? 'Unknown error');
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        _sendPurchaseUpdate(purchaseDetails, 'canceled');
      }
    }
  }

  void _sendPurchaseUpdate(PurchaseDetails purchaseDetails, String status,
      {String? errorMessage}) {
    final Map<String, dynamic> purchaseUpdate = {
      'productId': purchaseDetails.productID,
      'status': status,
      'transactionId': purchaseDetails.purchaseID ?? '',
    };

    if (errorMessage != null) {
      purchaseUpdate['errorMessage'] = errorMessage;
    }

    widget.backend.triggerControlEvent(
      widget.control.id,
      "purchase_updated",
      jsonEncode(purchaseUpdate),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This is an invisible control, just a bridge to the in-app purchase functionality
    return const SizedBox.shrink();
  }
}
