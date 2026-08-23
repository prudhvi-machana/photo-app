import 'package:flutter/material.dart';

import '../services/api_service.dart';

class CreateAlbumScreen extends StatefulWidget {
  final String token;

  const CreateAlbumScreen({
    super.key,
    required this.token,
  });

  @override
  State<CreateAlbumScreen> createState() => _CreateAlbumScreenState();
}

class _CreateAlbumScreenState extends State<CreateAlbumScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final ApiService _apiService = ApiService();

  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _apiService.setToken(widget.token);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createAlbum() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      await _apiService.createAlbum(
        _nameController.text.trim(),
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create album.'),
        ),
      );

      setState(() {
        _isCreating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Album'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Album name',
                  hintText: 'Enter album name',
                  border: OutlineInputBorder(),
                ),
                onFieldSubmitted: (_) {
                  if (!_isCreating) {
                    _createAlbum();
                  }
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an album name';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isCreating ? null : _createAlbum,
                child: _isCreating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Create Album'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}