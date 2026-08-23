class TrashPhoto {
  final int id;
  final String filename;
  final String originalFilename;
  final String mimeType;
  final int size;
  final DateTime uploadedAt;
  final DateTime deletedAt;
  final int daysRemaining;
  final String? thumbnailUrl;

  TrashPhoto({
    required this.id,
    required this.filename,
    required this.originalFilename,
    required this.mimeType,
    required this.size,
    required this.uploadedAt,
    required this.deletedAt,
    required this.daysRemaining,
    this.thumbnailUrl,
  });

  factory TrashPhoto.fromJson(Map<String, dynamic> json) {
    return TrashPhoto(
      id: json['id'],
      filename: json['filename'] ?? '',
      originalFilename: json['original_filename'] ?? '',
      mimeType: json['mime_type'] ?? '',
      size: json['size'] ?? 0,
      uploadedAt: DateTime.parse(json['uploaded_at']),
      deletedAt: DateTime.parse(json['deleted_at']),
      daysRemaining: json['days_remaining'] ?? 0,
      thumbnailUrl:
          json['thumbnail_url'] ??
          '/photos/${json['id']}/thumbnail',
    );
  }
}