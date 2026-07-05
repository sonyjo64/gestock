import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/database/db.dart';

class CartItem {
  final int? productId;
  final String name;
  double price;
  final double costPrice;
  double quantity;
  double discount;
  final String unit;

  CartItem({
    this.productId,
    required this.name,
    required this.price,
    this.costPrice = 0,
    this.quantity = 1,
    this.discount = 0,
    this.unit = 'pcs',
  });

  double get lineTotal => (price * quantity) - discount;

  Map<String, dynamic> toMap() => {
    'product_id': productId,
    'product_name': name,
    'quantity': quantity,
    'price': price,
    'cost_price': costPrice,
    'discount': discount,
    'total': lineTotal,
  };

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'name': name,
    'price': price,
    'costPrice': costPrice,
    'quantity': quantity,
    'discount': discount,
    'unit': unit,
  };

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
    productId: j['productId'] as int?,
    name: j['name'] as String,
    price: (j['price'] as num).toDouble(),
    costPrice: (j['costPrice'] as num?)?.toDouble() ?? 0,
    quantity: (j['quantity'] as num).toDouble(),
    discount: (j['discount'] as num?)?.toDouble() ?? 0,
    unit: j['unit'] as String? ?? 'pcs',
  );
}

class PosProvider extends ChangeNotifier {
  final List<CartItem> _cart = [];
  Map<String, dynamic>? _customer;
  String _paymentMethod = 'cash';
  double _orderDiscount = 0;
  double _taxRate = 0;
  String _orderType = 'sale';

  List<CartItem> get cart => List.unmodifiable(_cart);
  Map<String, dynamic>? get customer => _customer;
  String get paymentMethod => _paymentMethod;
  double get orderDiscount => _orderDiscount;
  double get taxRate => _taxRate;
  String get orderType => _orderType;
  int get itemCount => _cart.fold(0, (s, i) => s + i.quantity.ceil());

  double get subtotal => _cart.fold(0.0, (s, i) => s + i.lineTotal);
  double get taxAmount => subtotal * (_taxRate / 100);
  double get total => subtotal + taxAmount - _orderDiscount;

  void setTaxRate(double rate) { _taxRate = rate; notifyListeners(); }
  void setOrderType(String t) { _orderType = t; notifyListeners(); }

  void addProduct(Map<String, dynamic> p) {
    final idx = _cart.indexWhere((i) => i.productId == p['id']);
    if (idx >= 0) {
      _cart[idx].quantity++;
    } else {
      _cart.add(CartItem(
        productId: p['id'] as int?,
        name: p['name'] as String,
        price: (p['price'] as num).toDouble(),
        costPrice: (p['cost_price'] as num?)?.toDouble() ?? 0,
        unit: p['unit'] as String? ?? 'pcs',
      ));
    }
    notifyListeners();
  }

  void removeItem(int idx) { _cart.removeAt(idx); notifyListeners(); }

  void setQty(int idx, double qty) {
    if (qty <= 0) { _cart.removeAt(idx); } else { _cart[idx].quantity = qty; }
    notifyListeners();
  }

  void setPrice(int idx, double price) { _cart[idx].price = price; notifyListeners(); }
  void setItemDiscount(int idx, double d) { _cart[idx].discount = d; notifyListeners(); }

  void setCustomer(Map<String, dynamic>? c) { _customer = c; notifyListeners(); }
  void setPaymentMethod(String m) { _paymentMethod = m; notifyListeners(); }
  void setOrderDiscount(double d) { _orderDiscount = d; notifyListeners(); }

  void clear() {
    _cart.clear();
    _customer = null;
    _paymentMethod = 'cash';
    _orderDiscount = 0;
    notifyListeners();
  }

  Future<int> completeSale(int? employeeId, {double? amountPaid, String? notes}) async {
    final sale = {
      'customer_id': _customer?['id'],
      'employee_id': employeeId,
      'subtotal': subtotal,
      'discount': _orderDiscount,
      'tax': taxAmount,
      'total': total,
      'payment_method': _paymentMethod,
      // En crédit, rien n'est payé immédiatement (tout le total devient une dette).
      'amount_paid': _paymentMethod == 'credit' ? 0.0 : (amountPaid ?? total),
      'change_amount': (amountPaid != null && amountPaid > total) ? amountPaid - total : 0,
      'notes': notes,
    };
    final items = _cart.map((i) => i.toMap()).toList();
    final id = await DB.instance.createSale(sale, items);
    clear();
    return id;
  }

  Future<void> holdOrder(String label) async {
    final data = jsonEncode({
      'cart': _cart.map((i) => i.toJson()).toList(),
      'customer': _customer,
      'paymentMethod': _paymentMethod,
      'orderDiscount': _orderDiscount,
    });
    await DB.instance.holdOrder(label, data);
    clear();
  }

  Future<List<Map<String, dynamic>>> getHeldOrders() => DB.instance.getHeldOrders();

  Future<void> resumeOrder(Map<String, dynamic> held) async {
    clear();
    final data = jsonDecode(held['data'] as String) as Map<String, dynamic>;
    final items = (data['cart'] as List).map((i) => CartItem.fromJson(i as Map<String, dynamic>)).toList();
    _cart.addAll(items);
    _customer = data['customer'] as Map<String, dynamic>?;
    _paymentMethod = data['paymentMethod'] as String? ?? 'cash';
    _orderDiscount = (data['orderDiscount'] as num?)?.toDouble() ?? 0;
    await DB.instance.deleteHeldOrder(held['id'] as int);
    notifyListeners();
  }
}
