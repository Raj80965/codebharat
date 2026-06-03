import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class RegisterPage extends StatefulWidget {
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool loading = false;

  final AuthService auth = AuthService();

  void register() async {
    setState(() => loading = true);

    final msg = await auth.register(
      _name.text.trim(),
      _email.text.trim(),
      _pass.text.trim(),
    );

    setState(() => loading = false);

    if (msg == null) {
      Navigator.pop(context); // back to login
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Register")),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _name, decoration: InputDecoration(labelText: "Name")),
          TextField(controller: _email, decoration: InputDecoration(labelText: "Email")),
          TextField(controller: _pass, decoration: InputDecoration(labelText: "Password"), obscureText: true),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: loading ? null : register,
            child: Text("Create Account"),
          ),
        ]),
      ),
    );
  }
}
