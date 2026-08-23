// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final cleanTitle = "from";
  final searchApi = 'https://hqkkwzafev6lvngmejpksui3mi0bbnoj.lambda-url.ap-south-1.on.aws/search?title=$cleanTitle';
  final res = await http.get(Uri.parse(searchApi), headers: {
    'User-Agent': 'Mozilla/5.0'
  });
  if (res.statusCode == 200) {
    final body = json.decode(res.body);
    final data = body['data'] as List?;
    if (data != null) {
      for (var d in data) {
        print('Found: ${d['title']} - subjectType: ${d['subjectType']} - detailPath: ${d['detailPath']}');
      }
    } else {
      print('Data is null');
    }
  } else {
    print('Failed: ${res.statusCode}');
  }
}
