import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddCatPage extends StatefulWidget {
  final String userId; // Pass the current logged-in user's ID

  const AddCatPage({Key? key, required this.userId}) : super(key: key);

  @override
  _AddCatPageState createState() => _AddCatPageState();
}

class _AddCatPageState extends State<AddCatPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();

  File? _imageFile;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  // Function to pick image from Camera or Gallery
  Future _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source, 
      imageQuality: 50, // Compressed slightly to fit nicely in Firestore
      maxWidth: 500,
      maxHeight: 500,
    );
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  // Save cat profile details and Base64 image directly to Firestore
  Future _saveCatProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String base64Image = '';

      // Convert image to Base64 string if selected
      if (_imageFile != null) {
        List<int> imageBytes = await _imageFile!.readAsBytes();
        base64Image = base64Encode(imageBytes);
      }

      // Save cat details to Cloud Firestore
      await FirebaseFirestore.instance.collection('cats').add({
        'user_id': widget.userId,
        'cat_name': _nameController.text.trim(),
        'breed': _breedController.text.trim(),
        'weight': double.tryParse(_weightController.text) ?? 0.0,
        'age': int.tryParse(_ageController.text) ?? 0,
        'image_base64': base64Image,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cat profile added successfully!')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Cat Personalise')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Image Picker Section
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Wrap(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.camera_alt),
                            title: const Text('Take a Photo'),
                            onTap: () {
                              Navigator.pop(context);
                              _pickImage(ImageSource.camera);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.photo_library),
                            title: const Text('Choose from Gallery'),
                            onTap: () {
                              Navigator.pop(context);
                              _pickImage(ImageSource.gallery);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null,
                  child: _imageFile == null
                      ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey)
                      : null,
                ),
              ),
              const SizedBox(height: 20),

              // Cat Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Cat's Name", border: OutlineInputBorder()),
                validator: (value) => value!.isEmpty ? 'Please enter a name' : null,
              ),
              const SizedBox(height: 15),

              // Breed
              TextFormField(
                controller: _breedController,
                decoration: const InputDecoration(labelText: 'Breed', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 15),

              // Weight
              TextFormField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 15),

              // Age
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age (Years)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 30),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveCatProfile,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Cat Profile', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}