class CardData {
  final int id;
  final String upper;
  final String lower;
  const CardData(this.id, this.upper, this.lower);

  // ← ここに書く
  String get imagePath =>
      'assets/images/${id.toString().padLeft(3, '0')}.png';
}