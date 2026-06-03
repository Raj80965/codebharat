import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  // Test MyMemory directly
  final url = Uri.parse('https://thingproxy.freeboard.io/fetch/' + 'https://api.mymemory.translated.net/get?q=hello&langpair=en|hi');
  print('Testing MyMemory with thingproxy: $url');
  try {
    final res = await http.get(url);
    print('MyMemory Status: ${res.statusCode}');
    print('MyMemory Body: ${res.body}');
  } catch(e) {
    print('MyMemory Error: $e');
  }

  // Test InputTools directly
  final rawUrl = 'https://inputtools.google.com/request?text=hello&itc=hi-t-i0-und&num=5&cp=0&cs=1&ie=utf-8&oe=utf-8';
  final inputUrl = Uri.parse('https://thingproxy.freeboard.io/fetch/$rawUrl');
  print('Testing InputTools: $inputUrl');
  try {
    final res = await http.get(inputUrl);
    print('InputTools Status: ${res.statusCode}');
    print('InputTools Body: ${res.body}');
  } catch(e) {
    print('InputTools Error: $e');
  }
}
