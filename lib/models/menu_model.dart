class MenuModel {
  final int id;
  final int categoryId;
  final String name;
  final int price;
  final int priceDineIn;
  final int priceOnline;
  final String image;
  final String imageUrl;
  final int stock;
  final bool isAvailable;

  MenuModel({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    required this.priceDineIn,
    required this.priceOnline,
    required this.image,
    required this.imageUrl,
    required this.stock,
    required this.isAvailable,
  });

  factory MenuModel.fromJson(Map<String, dynamic> json) {
    int parseSafeInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? 0;
    }

    return MenuModel(
      id: parseSafeInt(json['id']),
      categoryId: parseSafeInt(json['category_id']),
      name: json['name']?.toString() ?? 'Tanpa Nama',
      price: parseSafeInt(json['price']),
      // SINKRONKAN DENGAN FIELD DATABASE BE
      priceDineIn: parseSafeInt(json['price_dine_in']),
      priceOnline: parseSafeInt(json['price_online']),
      image: json['image']?.toString() ?? '',
      imageUrl:
          json['image_url']?.toString() ?? 'https://via.placeholder.com/150',
      stock: parseSafeInt(json['stock']),
      isAvailable: json['is_available'] == 1 || json['is_available'] == true,
    );
  }
}
