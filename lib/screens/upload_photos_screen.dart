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

class _UploadPhotosScreenState extends State<UploadPhotosScreen> {
  final ImagePicker _picker = ImagePicker();
  final ApiService _apiService = ApiService();

  List<XFile> _selectedMedia = [];
  bool _isPreparing = false;

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

    setState(() => _isPreparing = true);

    try {
      for (final media in _selectedMedia) {
        if (_isVideo(media)) {
          // Transcoding happens on the phone. Once prepared, the actual
          // original + playback upload runs in Android background transfer.
          final playbackPath = await _apiService.createVideoPlayback(media);
          await TransferManager.enqueueVideoUpload(
            originalPath: media.path,
            originalFilename: media.name,
            playbackPath: playbackPath,
            token: widget.token,
            albumId: widget.albumId,
          );
        } else {
          await TransferManager.enqueuePhotoUpload(
            filePath: media.path,
            filename: media.name,
            token: widget.token,
            albumId: widget.albumId,
          );
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
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
