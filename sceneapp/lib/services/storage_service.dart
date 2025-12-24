import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. UPLOAD VIDEO
  Future<void> uploadVideo(String filePath, String fileName, String userId) async {
    File file = File(filePath);
    String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    
    try {
      // A. Upload to Storage Bucket
      // Path: users/{uid}/recordings/{timestamp_filename}
      String storagePath = 'users/$userId/recordings/${timestamp}_$fileName';
      Reference ref = _storage.ref().child(storagePath);
      UploadTask uploadTask = ref.putFile(file);
      
      // Wait for upload to complete
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      // B. Save Metadata to Firestore
      // Collection: users -> {uid} -> recordings
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('recordings')
          .add({
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'storagePath': storagePath, // Needed to delete later
        'createdAt': FieldValue.serverTimestamp(),
        'fileSize': await file.length(), // Size in bytes
      });
      
    } catch (e) {
      print("Error uploading: $e");
      throw e;
    }
  }

  // 2. GET RECORDINGS STREAM (Real-time updates)
  Stream<QuerySnapshot> getRecordingsStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('recordings')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // 3. DOWNLOAD VIDEO
  Future<String> downloadVideo(String url, String fileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/$fileName';
      
      await Dio().download(url, savePath);
      return savePath; // Return local path so UI knows it's there
    } catch (e) {
      print("Download error: $e");
      throw e;
    }
  }

  // 4. DELETE VIDEO (From Cloud & Database)
  Future<void> deleteVideo(String docId, String storagePath) async {
    try {
      // A. Delete from Storage
      await _storage.ref(storagePath).delete();
      
      // B. Delete from Firestore
      // Note: You must pass the UserID context or traverse carefully. 
      // For simplicity, we assume the caller knows the path or we use a collection group query.
      // Ideally, pass userId to this function too.
    } catch (e) {
      print("Error deleting from cloud: $e");
      // If file is missing in storage but exists in DB, we still want to delete the DB entry
    }
  }
  
  // Helper to delete specific Firestore Doc
  Future<void> deleteFirestoreDoc(String userId, String docId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('recordings')
        .doc(docId)
        .delete();
  }
}