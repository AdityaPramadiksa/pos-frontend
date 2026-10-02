class CategoryModel {
  final int id;
  final String name;

  CategoryModel({required this.id, required this.name});

  // Memetakan JSON dari Laravel ke Objek Dart
  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(id: json['id'] as int, name: json['name'] as String);
  }
}
