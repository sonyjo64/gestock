class Product {
  final int? id;
  final String name;
  final int? categoryId;
  final String? categoryName;
  final double price;
  final double costPrice;
  final double stock;
  final String? barcode;
  final String unit;
  final String? description;

  Product({
    this.id,
    required this.name,
    this.categoryId,
    this.categoryName,
    required this.price,
    this.costPrice = 0,
    this.stock = 0,
    this.barcode,
    this.unit = 'pcs',
    this.description,
  });

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as int?,
        name: map['name'] as String,
        categoryId: map['category_id'] as int?,
        categoryName: map['category_name'] as String?,
        price: (map['price'] as num).toDouble(),
        costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
        stock: (map['stock'] as num?)?.toDouble() ?? 0,
        barcode: map['barcode'] as String?,
        unit: map['unit'] as String? ?? 'pcs',
        description: map['description'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'category_id': categoryId,
        'price': price,
        'cost_price': costPrice,
        'stock': stock,
        'barcode': barcode,
        'unit': unit,
        'description': description,
      };
}

class CartItem {
  final Product product;
  double quantity;
  double price;
  double discount;

  CartItem({
    required this.product,
    this.quantity = 1,
    double? price,
    this.discount = 0,
  }) : price = price ?? product.price;

  double get total => (price * quantity) - discount;

  Map<String, dynamic> toSaleItem(int saleId) => {
        'sale_id': saleId,
        'product_id': product.id,
        'product_name': product.name,
        'quantity': quantity,
        'price': price,
        'discount': discount,
        'total': total,
      };
}
