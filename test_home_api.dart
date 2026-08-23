import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse('https://hqkkwzafev6lvngmejpksui3mi0bbnoj.lambda-url.ap-south-1.on.aws/home');
  final request = await HttpClient().getUrl(url);
  request.headers.add('User-Agent', 'Mozilla/5.0');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  final data = json.decode(body)['data'];
  final ops = data['operatingList'] as List;
  
  for (final op in ops) {
    if (op['type'] == 'BANNER') {
      final items = op['banner']['items'] as List;
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        print('\n--- Banner Item $i ---');
        print('Title: ${item['title']}');
        
        if (item['image'] != null && item['image'] is Map) {
          print('Item Image URL: ${item['image']['url']}');
        } else {
          print('Item Image: ${item['image']}');
        }

        final subject = item['subject'];
        if (subject != null && subject is Map) {
          final cover = subject['cover'];
          if (cover != null && cover is Map) {
             print('Subject Cover URL: ${cover['url']}');
          } else {
             print('Subject Cover: $cover');
          }
        } else {
          print('Subject: None');
        }
      }
    }
  }
}
