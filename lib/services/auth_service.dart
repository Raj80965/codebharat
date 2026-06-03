import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AuthService {
  static Map<String, Map<String, dynamic>> _users = {};
  static String? _currentUser;
  static SharedPreferences? _prefs;

  // Initialize the service
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Load users from shared preferences
    final usersString = _prefs!.getString('users');
    if (usersString != null) {
      final usersJson = jsonDecode(usersString);
      _users = Map<String, Map<String, dynamic>>.from(
        usersJson.map(
            (key, value) => MapEntry(key, Map<String, dynamic>.from(value))),
      );
    }

    // Load current user
    _currentUser = _prefs!.getString('current_user');
  }

  // Save users to shared preferences
  static Future<void> _saveUsers() async {
    if (_prefs != null) {
      await _prefs!.setString('users', jsonEncode(_users));
      await _prefs!.setString('current_user', _currentUser ?? '');
    }
  }

  // REGISTER
  Future<String?> register(String name, String email, String pass) async {
    try {
      // Check if user already exists
      if (_users.containsKey(email)) {
        return "User already exists";
      }

      // Create new user
      _users[email] = {
        "name": name,
        "email": email,
        "password": pass, // In a real app, this should be hashed
        "createdAt": DateTime.now().toIso8601String(),
      };

      // Save to persistent storage
      await _saveUsers();

      return null; // success
    } catch (e) {
      return e.toString();
    }
  }

  // LOGIN
  Future<String?> login(String email, String pass) async {
    try {
      // Check if user exists and password matches
      if (_users.containsKey(email) && _users[email]!['password'] == pass) {
        _currentUser = email;
        // Save to persistent storage
        await _saveUsers();
        return null; // success
      } else if (!_users.containsKey(email)) {
        return "No user found with this email";
      } else {
        return "Incorrect password";
      }
    } catch (e) {
      return e.toString();
    }
  }

  // LOGOUT
  Future<void> logout() async {
    _currentUser = null;
    await _saveUsers();
  }

  // Check if user is logged in
  bool get isLoggedIn => _currentUser != null;

  // Get current user email
  String? get currentUserEmail => _currentUser;

  // Get current user data
  Map<String, dynamic>? get currentUserData =>
      _currentUser != null ? _users[_currentUser] : null;
}
