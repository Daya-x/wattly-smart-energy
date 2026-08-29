import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class FirebaseAuthClient extends http.BaseClient {
  final http.Client _inner;
  final FirebaseAuth? _auth;

  FirebaseAuthClient({http.Client? inner, FirebaseAuth? auth})
    : _inner = inner ?? http.Client(),
      _auth = auth;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw StateError('Sign in is required to access the Wattly API');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Unable to obtain a Firebase login token');
    }
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
