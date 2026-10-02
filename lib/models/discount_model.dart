class DiscountModel {
  final int id;
  final String name;
  final String type; // 'percentage' atau 'fixed'
  final int value;

  DiscountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
  });

  factory DiscountModel.fromJson(Map<String, dynamic> json) {
    return DiscountModel(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      value: json['value'],
    );
  }
}
