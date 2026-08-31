import 'package:photo_manager/photo_manager.dart';

class LocalMedia {
  final AssetEntity asset;
  final String filename;
  final bool alsoInCloud;

  const LocalMedia({
    required this.asset,
    required this.filename,
    this.alsoInCloud = false,
  });

  DateTime get createdAt => asset.createDateTime;
  bool get isVideo => asset.type == AssetType.video;
}
