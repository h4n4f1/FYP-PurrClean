import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CatListWidget extends StatelessWidget {
  final String userId; // Pass the current user's ID

  const CatListWidget({Key? key, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      // Listen to cats collection filtered by the current user
      stream: FirebaseFirestore.instance
          .collection('cats')
          .where('user_id', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        // 1. Handle loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // 2. Handle errors
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        // 3. Handle empty state
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('No cats added yet! Tap the button below to add one.'),
          );
        }

        // 4. Display the list of cats
        final catDocs = snapshot.data!.docs;

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: catDocs.length,
          itemBuilder: (context, index) {
            final catData = catDocs[index].data() as Map;
            
            final catName = catData['cat_name'] ?? 'Unknown';
            final breed = catData['breed'] ?? 'Unknown Breed';
            final weight = catData['weight'] ?? 0.0;
            final age = catData['age'] ?? 0;
            final base64Image = catData['image_base64'] ?? '';

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              elevation: 2,
              child: ListTile(
                // Display cat picture
                leading: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: base64Image.isNotEmpty
                      ? MemoryImage(base64Decode(base64Image))
                      : null,
                  child: base64Image.isEmpty
                      ? const Icon(Icons.pets, color: Colors.grey)
                      : null,
                ),
                // Display cat name and breed
                title: Text(
                  catName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Text('\(breed •\)age yrs • $weight kg'), // Fixed subtitle string
                // Optional: Delete button
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () async {
                    // Delete document from Firestore
                    await catDocs[index].reference.delete();
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}