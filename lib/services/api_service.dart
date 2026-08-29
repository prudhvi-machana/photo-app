import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/album.dart';
import '../models/photo.dart';
import '../models/trash_photo.dart';
import '../models/user.dart';
import 'api_config.dart';

class ApiService {
  final String baseUrl = ApiConfig.baseUrl;
  static const MethodChannel _videoChannel =
      MethodChannel('photo_app/video_transcoder');

  String? token;

  void setToken(String token) {
    this.token = token;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Future<List<Album>> getAlbums() async {
    final response = await http.get(Uri.parse('$baseUrl/albums'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to load albums');
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Album.fromJson(json)).toList();
  }

  Future<Album> createAlbum(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/albums'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create album');
    }
    return Album.fromJson(jsonDecode(response.body));
  }

  Future<Album> updateAlbum(int albumId, String name) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/albums/$albumId'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode != 200) throw Exception('Failed to update album');
    return Album.fromJson(jsonDecode(response.body));
  }

  Future<void> deleteAlbum(int albumId) async {
    final response = await http.delete(Uri.parse('$baseUrl/albums/$albumId'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to delete album');
  }

  Future<List<Photo>> getRecentPhotos() async {
    final response = await http.get(Uri.parse('$baseUrl/photos/recent'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to load recent photos');
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Photo.fromJson(json)).toList();
  }

  Future<List<Photo>> getAlbumPhotos(int albumId) async {
    final response = await http.get(Uri.parse('$baseUrl/albums/$albumId/photos'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to load album photos');
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Photo.fromJson(json)).toList();
  }

  Future<Photo> uploadPhoto(XFile photo) async {
    if (token == null) throw Exception('Not authenticated');

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/photos/upload'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', photo.path, filename: photo.name));

    final response = await request.send();
    final body = await http.Response.fromStream(response);
    if (body.statusCode != 200 && body.statusCode != 201) {
      throw Exception('Upload failed: ${body.statusCode} ${body.body}');
    }
    return Photo.fromJson(jsonDecode(body.body));
  }

  Future<String> createVideoPlayback(XFile original) async {
    final playbackPath = await _videoChannel.invokeMethod<String>(
      'createPlaybackVideo',
      {'inputPath': original.path},
    );

    if (playbackPath == null || playbackPath.isEmpty) {
      throw Exception('Failed to create playback video');
    }

    final playbackFile = File(playbackPath);
    if (!await playbackFile.exists()) {
      throw Exception('Playback file was not created');
    }

    return playbackPath;
  }

  Future<Photo> uploadVideoWithPlayback(XFile original) async {
    if (token == null) throw Exception('Not authenticated');

    final playbackPath = await createVideoPlayback(original);
    final playbackFile = File(playbackPath);

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/photos/upload-video'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath(
      'original_file',
      original.path,
      filename: original.name,
    ));
    request.files.add(await http.MultipartFile.fromPath(
      'playback_file',
      playbackPath,
      filename: 'playback.mp4',
    ));

    try {
      final response = await request.send();
      final body = await http.Response.fromStream(response);
      if (body.statusCode != 200 && body.statusCode != 201) {
        throw Exception('Video upload failed: ${body.statusCode} ${body.body}');
      }
      return Photo.fromJson(jsonDecode(body.body));
    } finally {
      try {
        await playbackFile.delete();
      } catch (_) {}
    }
  }

  Future<List<int>> downloadPhoto(int photoId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/photos/$photoId'),
      headers: {'Authorization': 'Bearer ${token ?? ''}'},
    );
    if (response.statusCode != 200) throw Exception('Failed to download media: ${response.statusCode}');
    return response.bodyBytes;
  }

  Future<File> downloadPhotoToTempFile(int photoId, String filename) async {
    final request = http.Request('GET', Uri.parse('$baseUrl/photos/$photoId'));
    request.headers['Authorization'] = 'Bearer ${token ?? ''}';
    final response = await http.Client().send(request);
    if (response.statusCode != 200) throw Exception('Failed to download media: ${response.statusCode}');

    final directory = await getTemporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${directory.path}/$safeName');
    final sink = file.openWrite();
    try {
      await response.stream.pipe(sink);
    } catch (_) {
      await sink.close();
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    return file;
  }

  Future<void> addPhotoToAlbum(int albumId, int photoId) async {
    final response = await http.post(Uri.parse('$baseUrl/albums/$albumId/photos/$photoId'), headers: _headers);
    if (response.statusCode != 200 && response.statusCode != 201) throw Exception('Failed to add photo to album: ${response.statusCode}');
  }

  Future<void> removePhotoFromAlbum(int albumId, int photoId) async {
    final response = await http.delete(Uri.parse('$baseUrl/albums/$albumId/photos/$photoId'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to remove photo from album: ${response.statusCode}');
  }

  Future<void> movePhotoToAlbum(int currentAlbumId, int destinationAlbumId, int photoId) async {
    await addPhotoToAlbum(destinationAlbumId, photoId);
    await removePhotoFromAlbum(currentAlbumId, photoId);
  }

  Future<List<TrashPhoto>> getTrashPhotos() async {
    final response = await http.get(Uri.parse('$baseUrl/photos/trash'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to load trash');
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => TrashPhoto.fromJson(json)).toList();
  }

  Future<void> movePhotoToTrash(int photoId) async {
    final response = await http.delete(Uri.parse('$baseUrl/photos/$photoId'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to move media to trash: ${response.statusCode}');
  }

  Future<void> restorePhoto(int photoId) async {
    final response = await http.post(Uri.parse('$baseUrl/photos/trash/$photoId/restore'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to restore media: ${response.statusCode}');
  }

  Future<void> permanentlyDeletePhoto(int photoId) async {
    final response = await http.delete(Uri.parse('$baseUrl/photos/trash/$photoId'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to permanently delete media: ${response.statusCode}');
  }

  Future<void> deletePhoto(int photoId) async => movePhotoToTrash(photoId);

  Future<User> getCurrentUser() async {
    final response = await http.get(Uri.parse('$baseUrl/auth/me'), headers: _headers);
    if (response.statusCode != 200) throw Exception('Failed to load current user');
    return User.fromJson(jsonDecode(response.body));
  }
}
