class Photo {
  final int id;
  final String filename;
  final String originalFilename;
  final String mimeType;
  final int size;
  final String uploadedAt;
  final String? thumbnailUrl;

  Photo({
    required this.id,
    required this.filename,
    required this.originalFilename,
    required this.mimeType,
    required this.size,
    required this.uploadedAt,
    this.thumbnailUrl,
  });

  factory Photo.fromJson(Map<String, dynamic> json) {
    return Photo(
      id: json['id'],
      filename: json['filename'] ?? '',
      originalFilename: json['original_filename'] ?? '',
      mimeType: json['mime_type'] ?? '',
      size: json['size'] ?? 0,
      uploadedAt: json['uploaded_at'] ?? '',
      thumbnailUrl: json['thumbnail_url'] ?? '/photos/${json['id']}/thumbnail',
    );
  }
}