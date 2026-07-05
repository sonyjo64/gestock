import 'package:flutter/material.dart';
import '../core/database/database_helper.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../models/supplier.dart';

class AppProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  // POS Cart
  final List<CartItem> _cart = [];
  Customer? _selectedCustomer;
  String _paymentMethod = 'cash';
  double _orderDiscount = 0;
  double _taxRate = 0;

  List<CartItem> get cart => List.unmodifiable(_cart);
  Customer? get selectedCustomer => _selectedCustomer;
  String get paymentMethod => _paymentMethod;
  double get orderDiscount => _orderDiscount;
  double get taxRate => _taxRate;

  double get subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get tax => subtotal * (_taxRate / 100);
  double get total => subtotal + tax - _orderDiscount;

  void addToCart(Product product) {
    final existing = _cart.indexWhere((i) => i.product.id == product.id);
    if (existing >= 0) {
      _cart[existing].quantity++;
    } else {
      _cart.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void removeFromCart(int index) {
    _cart.removeAt(index);
    notifyListeners();
  }

  void updateCartItemQty(int index, double qty) {
    if (qty <= 0) {
      _cart.removeAt(index);
    } else {
      _cart[index].quantity = qty;
    }
    notifyListeners();
  }

  void updateCartItemPrice(int index, double price) {
    _cart[index].price = price;
    notifyListeners();
  }

  void updateCartItemDiscount(int index, double discount) {
    _cart[index].discount = discount;
    notifyListeners();
  }

  void setCustomer(Customer? customer) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  void setOrderDiscount(double discount) {
    _orderDiscount = discount;
    notifyListeners();
  }

  void setTaxRate(double rate) {
    _taxRate = rate;
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _selectedCustomer = null;
    _paymentMethod = 'cash';
    _orderDiscount = 0;
    notifyListeners();
  }

  Future<int> completeSale({double amountPaid = 0, String? notes}) async {
    final saleData = {
      'customer_id': _selectedCustomer?.id,
      'subtotal': subtotal,
      'discount': _orderDiscount,
      'tax': tax,
      'total': total,
      'payment_method': _paymentMethod,
      'amount_paid': amountPaid > 0 ? amountPaid : total,
      'notes': notes,
    };

    final items = _cart
        .map((item) => {
              'product_id': item.product.id,
              'product_name': item.product.name,
              'quantity': item.quantity,
              'price': item.price,
              'discount': item.discount,
              'total': item.total,
            })
        .toList();

    final saleId = await _db.insertSale(saleData, items);
    clearCart();
    return saleId;
  }

  // Products
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> get products => _products;

  Future<void> loadProducts({String? search, int? categoryId}) async {
    _products = await _db.getProducts(search: search, categoryId: categoryId);
    notifyListeners();
  }

  Future<void> saveProduct(Map<String, dynamic> data, {int? id}) async {
    if (id != null) {
      await _db.updateProduct(id, data);
    } else {
      await _db.insertProduct(data);
    }
    await loadProducts();
  }

  Future<void> deleteProduct(int id) async {
    await _db.deleteProduct(id);
    await loadProducts();
  }

  // Categories
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> get categories => _categories;

  Future<void> loadCategories() async {
    _categories = await _db.getCategories();
    notifyListeners();
  }

  Future<void> addCategory(String name) async {
    await _db.insertCategory(name);
    await loadCategories();
  }

  Future<void> deleteCategory(int id) async {
    await _db.deleteCategory(id);
    await loadCategories();
  }

  // Customers
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> get customers => _customers;

  Future<void> loadCustomers({String? search}) async {
    _customers = await _db.getCustomers(search: search);
    notifyListeners();
  }

  Future<void> saveCustomer(Map<String, dynamic> data, {int? id}) async {
    if (id != null) {
      await _db.updateCustomer(id, data);
    } else {
      await _db.insertCustomer(data);
    }
    await loadCustomers();
  }

  Future<void> deleteCustomer(int id) async {
    await _db.deleteCustomer(id);
    await loadCustomers();
  }

  // Suppliers
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> get suppliers => _suppliers;

  Future<void> loadSuppliers({String? search}) async {
    _suppliers = await _db.getSuppliers(search: search);
    notifyListeners();
  }

  Future<void> saveSupplier(Map<String, dynamic> data, {int? id}) async {
    if (id != null) {
      await _db.updateSupplier(id, data);
    } else {
      await _db.insertSupplier(data);
    }
    await loadSuppliers();
  }

  Future<void> deleteSupplier(int id) async {
    await _db.deleteSupplier(id);
    await loadSuppliers();
  }

  // Dashboard
  Map<String, dynamic> _dashboardStats = {};
  Map<String, dynamic> get dashboardStats => _dashboardStats;

  Future<void> loadDashboard() async {
    _dashboardStats = await _db.getDashboardStats();
    notifyListeners();
  }

  // Reports
  Map<String, dynamic> _reportData = {};
  Map<String, dynamic> get reportData => _reportData;

  Future<void> loadReport(String startDate, String endDate) async {
    _reportData = await _db.getSalesReport(startDate, endDate);
    notifyListeners();
  }

  // Sales history
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> get sales => _sales;

  Future<void> loadSales({String? startDate, String? endDate}) async {
    _sales = await _db.getSales(startDate: startDate, endDate: endDate);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getSaleItems(int saleId) async {
    return await _db.getSaleItems(saleId);
  }

  // Expenses
  List<Map<String, dynamic>> _expenseHeads = [];
  List<Map<String, dynamic>> get expenseHeads => _expenseHeads;
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> get expenses => _expenses;

  Future<void> loadExpenseHeads() async {
    _expenseHeads = await _db.getExpenseHeads();
    notifyListeners();
  }

  Future<void> addExpenseHead(String name) async {
    await _db.insertExpenseHead(name);
    await loadExpenseHeads();
  }

  Future<void> loadExpenses({String? startDate, String? endDate}) async {
    _expenses = await _db.getExpenses(startDate: startDate, endDate: endDate);
    notifyListeners();
  }

  Future<void> addExpense(Map<String, dynamic> data) async {
    await _db.insertExpense(data);
    await loadExpenses();
  }
}
