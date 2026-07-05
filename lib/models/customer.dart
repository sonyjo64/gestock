class Customer {
  final int? id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String type;
  final double balance;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.type = 'retail',
    this.balance = 0,
  });

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as int?,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        address: map['address'] as String?,
        type: map['type'] as String? ?? 'retail',
        balance: (map['balance'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'type': type,
        'balance': balance,
      };

  bool get isWholesale => type == 'wholesale';
}
