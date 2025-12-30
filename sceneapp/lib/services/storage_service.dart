import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:gal/gal.dart';
import 'package:video_compress/video_compress.dart'; // <--- Import this
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
     app: Firebase.app(), 
     databaseId: 'selftape-ai' // <--- MUST MATCH EXACTLY
  );


  // UPDATED: Now accepts an 'onProgress' callback
  Future<void> uploadVideo(
      String filePath, 
      String fileName, 
      String userId, 
      Function(double) onProgress // <--- New Parameter
  ) async {
    
    File originalFile = File(filePath);
    if (!originalFile.existsSync()) return;

    try {
      // A. COMPRESSION (Report 0-30% progress conceptually)
      // Compression doesn't give granular updates, so we fake the start
      onProgress(0.1); 
      
      MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        originalFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );

      if (mediaInfo == null || mediaInfo.file == null) {
        throw Exception("Compression failed");
      }

      File fileToUpload = mediaInfo.file!;
      onProgress(0.2); // Compression done, starting upload

      // B. UPLOAD (Report 20-100% progress)
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String storagePath = 'users/$userId/recordings/${timestamp}_$fileName';
      Reference ref = _storage.ref().child(storagePath);

      UploadTask uploadTask = ref.putFile(fileToUpload);

      // Listen to the upload stream
      uploadTask.snapshotEvents.listen((event) {
        double uploadPercentage = event.bytesTransferred / event.totalBytes;
        // Map upload (0-1.0) to overall progress (0.2-1.0)
        double totalProgress = 0.2 + (uploadPercentage * 0.8);
        onProgress(totalProgress);
      });

      // Wait for completion
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      // C. SAVE DATABASE ENTRY
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('recordings')
          .add({
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'storagePath': storagePath,
        'createdAt': FieldValue.serverTimestamp(),
        'fileSize': await fileToUpload.length(),
      });

      // D. CLEANUP (Manual delete to avoid crash)
      if (fileToUpload.existsSync()) {
        await fileToUpload.delete();
      }
      
      onProgress(1.0); // Done

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
Future<void> downloadVideo(String url, String fileName) async {
    try {
      // 1. Request Permission (Required for some Android versions)
      bool hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      // 2. Get a temporary path to store the download securely first
      final dir = await getTemporaryDirectory(); // Uses path_provider
      final tempPath = '${dir.path}/$fileName';

      // 3. Download to that temp path
      await Dio().download(url, tempPath);

      // 4. Move it to the Gallery (This makes it visible in Photos app)
      await Gal.putVideo(tempPath);
      
      // 5. Cleanup: Delete the temp file to save space
      File(tempPath).delete();

    } catch (e) {
      print("Download error: $e");
      throw Exception("Could not save to gallery: $e");
    }
  }

Future<void> deleteVideo(String userId, String docId, String storagePath) async {
    try {
      // A. Delete from Storage (The actual file)
      try {
        await _storage.ref(storagePath).delete();
      } catch (e) {
        // If file is not found (404), just print it but continue. 
        // We still want to remove the database entry.
        print("File not found in storage (already deleted?): $e");
      }

      // B. Delete from Firestore (The history entry)
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('recordings')
          .doc(docId)
          .delete();
          
    } catch (e) {
      print("Error deleting video: $e");
      throw e;
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