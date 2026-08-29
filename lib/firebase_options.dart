import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb) {
      throw UnsupportedError(
        'Firebase is currently configured for the Wattly web dashboard only.',
      );
    }
    return web;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDEBY4s4s2XP_S1qmZyDXEYY2m2rwlFQsI',
    authDomain: 'wattly-smart-energy-2026.firebaseapp.com',
    projectId: 'wattly-smart-energy-2026',
    storageBucket: 'wattly-smart-energy-2026.firebasestorage.app',
    messagingSenderId: '966993040250',
    appId: '1:966993040250:web:aa587212708550e9e83cc3',
  );
}
