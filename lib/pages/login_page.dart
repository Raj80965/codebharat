import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool loading = false;

  final AuthService auth = AuthService();

  void login() async {
    setState(() => loading = true);

    final msg = await auth.login(_email.text.trim(), _pass.text.trim());

    setState(() => loading = false);

    if (msg == null) {
      // success → navigate to home page
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Login")),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(children: [
          TextField(
              controller: _email,
              decoration: InputDecoration(labelText: "Email")),
          TextField(
              controller: _pass,
              decoration: InputDecoration(labelText: "Password"),
              obscureText: true),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: loading ? null : login,
            child: Text("Login"),
          ),
          TextButton(
            child: Text("Create new account"),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RegisterPage()),
              );
            },
          )
        ]),
      ),
    );
  }
}
