class Supplier {
  final int? id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final double balance;

  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.balance = 0,
  });

  factory Supplier.fromMap(Map<String, dynamic> map) => Supplier(
        id: map['id'] as int?,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        address: map['address'] as String?,
        balance: (map['balance'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'balance': balance,
      };
}
