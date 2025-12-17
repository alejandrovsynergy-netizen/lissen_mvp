import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfilePhotoService {
  static Future<String> uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
  }) async {
    final storageRef =
        FirebaseStorage.instance.ref().child('users/$uid/profile_photo.jpg');

    await storageRef.putData(bytes);
    return storageRef.getDownloadURL();
  }

  static Future<void> saveProfilePhotoToUser({
    required String uid,
    required String url,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'photoUrl': url,
    }, SetOptions(merge: true));
  }

  static Future<void> addPhotoToGallery({
    required String uid,
    required String url,
    bool fromProfile = true,
  }) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('gallery')
        .add({
      'url': url,
      'type': 'photo',
      'fromProfile': fromProfile,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setNewProfilePhotoFromBytes({
    required String uid,
    required Uint8List bytes,
  }) async {
    final url = await uploadProfilePhoto(uid: uid, bytes: bytes);
    await saveProfilePhotoToUser(uid: uid, url: url);
    await addPhotoToGallery(uid: uid, url: url, fromProfile: true);
  }
}
