import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class SignOutService {
  static Future<void> signOutHard() async {
    // Google
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await GoogleSignIn().disconnect();
    } catch (_) {}

    // Facebook
    try {
      await FacebookAuth.instance.logOut();
    } catch (_) {}

    // Firebase
    await FirebaseAuth.instance.signOut();
  }
}
