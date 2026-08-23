import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/album.dart';
import '../models/photo.dart';
import '../models/trash_photo.dart';
import '../models/user.dart';
import 'api_config.dart';

class ApiService {
  final String baseUrl = ApiConfig.baseUrl;

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

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  Future<List<Album>> getAlbums() async {
    final response = await http.get(
      Uri.parse('$baseUrl/albums'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load albums');
    }

    final List<dynamic> data = jsonDecode(response.body);

    return data
        .map((json) => Album.fromJson(json))
        .toList();
  }

  Future<Album> createAlbum(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/albums'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
      }),
    );

    if (response.statusCode != 200 &&
        response.statusCode != 201) {
      throw Exception('Failed to create album');
    }

    return Album.fromJson(
      jsonDecode(response.body),
    );
  }

  Future<Album> updateAlbum(
    int albumId,
    String name,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/albums/$albumId'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update album');
    }

    return Album.fromJson(
      jsonDecode(response.body),
    );
  }

  Future<void> deleteAlbum(int albumId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/albums/$albumId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete album');
    }
  }

  // ---------------------------------------------------------------------------
  // Photos
  // ---------------------------------------------------------------------------

  Future<List<Photo>> getRecentPhotos() async {
    final response = await http.get(
      Uri.parse('$baseUrl/photos/recent'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load recent photos',
      );
    }

    final List<dynamic> data =
        jsonDecode(response.body);

    return data
        .map((json) => Photo.fromJson(json))
        .toList();
  }

  Future<List<Photo>> getAlbumPhotos(
    int albumId,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/albums/$albumId/photos',
      ),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load album photos',
      );
    }

    final List<dynamic> data =
        jsonDecode(response.body);

    return data
        .map((json) => Photo.fromJson(json))
        .toList();
  }

  Future<Photo> uploadPhoto(
    XFile photo,
  ) async {
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/photos/upload'),
    );

    request.headers['Authorization'] =
        'Bearer $token';

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        photo.path,
        filename: photo.name,
      ),
    );

    final streamedResponse =
        await request.send();

    final response =
        await http.Response.fromStream(
      streamedResponse,
    );

    if (response.statusCode != 200 &&
        response.statusCode != 201) {
      throw Exception(
        'Upload failed: ${response.statusCode}',
      );
    }

    return Photo.fromJson(
      jsonDecode(response.body),
    );
  }

  // ---------------------------------------------------------------------------
  // Download / View
  // ---------------------------------------------------------------------------

  Future<Uint8List> downloadPhoto(
    int photoId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/photos/$photoId'),
      headers: {
        'Authorization':
            'Bearer ${token ?? ''}',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download photo: '
        '${response.statusCode}',
      );
    }

    return response.bodyBytes;
  }

  // ---------------------------------------------------------------------------
  // Album Photos
  // ---------------------------------------------------------------------------

  Future<void> addPhotoToAlbum(
    int albumId,
    int photoId,
  ) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/albums/$albumId/photos/$photoId',
      ),
      headers: _headers,
    );

    if (response.statusCode != 200 &&
        response.statusCode != 201) {
      throw Exception(
        'Failed to add photo to album: '
        '${response.statusCode}',
      );
    }
  }

  Future<void> removePhotoFromAlbum(
    int albumId,
    int photoId,
  ) async {
    final response = await http.delete(
      Uri.parse(
        '$baseUrl/albums/$albumId/photos/$photoId',
      ),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to remove photo from album: '
        '${response.statusCode}',
      );
    }
  }

  Future<void> movePhotoToAlbum(
    int currentAlbumId,
    int destinationAlbumId,
    int photoId,
  ) async {
    await addPhotoToAlbum(
      destinationAlbumId,
      photoId,
    );

    await removePhotoFromAlbum(
      currentAlbumId,
      photoId,
    );
  }

  // ---------------------------------------------------------------------------
  // Trash
  // ---------------------------------------------------------------------------

  Future<List<TrashPhoto>>
      getTrashPhotos() async {
    final response = await http.get(
      Uri.parse('$baseUrl/photos/trash'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load trash',
      );
    }

    final List<dynamic> data =
        jsonDecode(response.body);

    return data
        .map(
          (json) => TrashPhoto.fromJson(json),
        )
        .toList();
  }

  Future<void> movePhotoToTrash(
    int photoId,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/photos/$photoId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to move photo to trash: '
        '${response.statusCode}',
      );
    }
  }

  Future<void> restorePhoto(
    int photoId,
  ) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/photos/trash/$photoId/restore',
      ),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to restore photo: '
        '${response.statusCode}',
      );
    }
  }

  Future<void> permanentlyDeletePhoto(
    int photoId,
  ) async {
    final response = await http.delete(
      Uri.parse(
        '$baseUrl/photos/trash/$photoId',
      ),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to permanently delete photo: '
        '${response.statusCode}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Backwards-compatible delete
  // ---------------------------------------------------------------------------

  Future<void> deletePhoto(
    int photoId,
  ) async {
    await movePhotoToTrash(photoId);
  }

  // ---------------------------------------------------------------------------
  // Current User
  // ---------------------------------------------------------------------------

  Future<User> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load current user',
      );
    }

    return User.fromJson(
      jsonDecode(response.body),
    );
  }
}