import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/transfer_manager.dart';

class UploadPhotosScreen extends StatefulWidget {
  final String token;
  final int? albumId;

  const UploadPhotosScreen({
    super.key,
    required this.token,
    this.albumId,
  });

  @override
  State<UploadPhotosScreen> createState() => _UploadPhotosScreenState();
}

class _PreparedVideo {
  final XFile media;
  final String playbackPath;

  const _PreparedVideo({required this.media, required this.playbackPath});
}

class _UploadPhotosScreenState extends State<UploadPhotosScreen> {
  final ImagePicker _picker = ImagePicker();
  final ApiService _apiService = ApiService();

  List<XFile> _selectedMedia = [];
  bool _isPreparing = false;
  int _preparingVideo = 0;
  int _totalVideos = 0;

  @override
  void initState() {
    super.initState();
    _apiService.setToken(widget.token);
  }

  bool _isVideo(XFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.startsWith('video/')) return true;

    final extension = file.name.split('.').last.toLowerCase();
    return {
      'mp4',
      'mov',
      'm4v',
      'avi',
      'mkv',
      'webm',
      '3gp',
      '3gpp',
      'ts',
    }.contains(extension);
  }

  Future<void> _selectMedia() async {
    try {
      final media = await _picker.pickMultipleMedia();
      if (!mounted) return;
      setState(() => _selectedMedia = media);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to select media.')),
      );
    }
  }

  Future<void> _uploadSelectedMedia() async {
    if (_selectedMedia.isEmpty || _isPreparing) return;

    final selected = List<XFile>.from(_selectedMedia);
    final videos = selected.where(_isVideo).toList();

    setState(() {
      _isPreparing = true;
      _preparingVideo = 0;
      _totalVideos = videos.length;
    });

    try {
      // Prepare every video before enqueueing the upload batch. This is
      // important because the downloader's grouped notification counts only
      // tasks that have already been enqueued. By preparing first, all
      // selected media items exist in the batch before progress starts, so
      // "Uploading X of Y" and the completion notification remain accurate.
      final preparedVideos = <_PreparedVideo>[];
      for (final video in videos) {
        if (!mounted) return;
        setState(() => _preparingVideo++);

        final playbackPath = await _apiService.createVideoPlayback(video);
        preparedVideos.add(
          _PreparedVideo(media: video, playbackPath: playbackPath),
        );
      }

      final preparedByPath = <String, _PreparedVideo>{
        for (final video in preparedVideos) video.media.path: video,
      };

      // Enqueue every selected media item only after all video preparation is
      // complete. The notification group therefore starts with the real batch
      // size, including videos that took time to prepare on the phone.
      for (final media in selected) {
        if (_isVideo(media)) {
          final prepared = preparedByPath[media.path];
          if (prepared == null) {
            throw Exception('Video preparation result is missing');
          }

          final queued = await TransferManager.enqueueVideoUpload(
            originalPath: media.path,
            originalFilename: media.name,
            playbackPath: prepared.playbackPath,
            token: widget.token,
            albumId: widget.albumId,
          );
          if (!queued) {
            throw Exception('Could not queue ${media.name}');
          }
        } else {
          final queued = await TransferManager.enqueuePhotoUpload(
            filePath: media.path,
            filename: media.name,
            token: widget.token,
            albumId: widget.albumId,
          );
          if (!queued) {
            throw Exception('Could not queue ${media.name}');
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPreparing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start upload: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.albumId != null ? 'Add Media' : 'Upload Media';
    final hasSelection = _selectedMedia.isNotEmpty;
    final videoCount = _selectedMedia.where(_isVideo).length;
    final photoCount = _selectedMedia.length - videoCount;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: hasSelection ? _buildPreview() : _buildEmptyState(),
            ),
            const SizedBox(height: 16),
            if (!hasSelection)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selectMedia,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Select Photos & Videos'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isPreparing ? null : _selectMedia,
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isPreparing ? null : _uploadSelectedMedia,
                      child: _isPreparing
                          ? Text(
                              _totalVideos > 0
                                  ? 'Preparing $_preparingVideo/$_totalVideos'
                                  : 'Preparing...',
                            )
                          : Text('Upload ${_selectedMedia.length}'),
                    ),
                  ),
                ],
              ),
            if (hasSelection) ...[
              const SizedBox(height: 10),
              Text(
                '$photoCount photo${photoCount == 1 ? '' : 's'} • '
                '$videoCount video${videoCount == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.perm_media_outlined, size: 64),
          const SizedBox(height: 16),
          Text(
            widget.albumId != null
                ? 'Select photos and videos to add'
                : 'Select photos and videos to upload',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return GridView.builder(
      itemCount: _selectedMedia.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final media = _selectedMedia[index];
        if (_isVideo(media)) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Icon(Icons.videocam, size: 40),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(media.path),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: Icon(Icons.image)),
          ),
        );
      },
    );
  }
}
