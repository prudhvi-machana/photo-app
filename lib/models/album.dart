class Album {
  final int id;
  final String name;
  final int photoCount;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  Album({
    required this.id,
    required this.name,
    required this.photoCount,
    this.thumbnailUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'],
      name: json['name'] ?? '',
      photoCount: json['photo_count'] ?? 0,
      thumbnailUrl: json['thumbnail_url'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}