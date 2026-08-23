// ignore_for_file: avoid_print, no_leading_underscores_for_local_identifiers
void main() {
  String cleanTitle(String t) {
    t = t.replaceAll(RegExp(r'\[.*?\]'), '');
    t = t.replaceAll(RegExp(r'\(.*?\)'), '');
    t = t.replaceAll(RegExp(r'From\s+S\d+\s*-\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'From\s+S\d+\s*to\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+\s*-\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+\s*to\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Season\s+\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Episode\s+\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Hindi\s+Dub\w*', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Eng\w*\s+Sub\w*', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'[^\w\s]'), '');
    return t.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  print('Clean: "${cleanTitle("From")}"');
  print('Clean: "${cleanTitle("from")}"');
  print('Clean: "${cleanTitle(" From ")}"');
  
  String getRefinedDisplayName(String t) {
    t = t.replaceAll(RegExp(r'\[.*?\]'), '');
    t = t.replaceAll(RegExp(r'\(.*?\)'), '');
    t = t.replaceAll(RegExp(r'From\s+S\d+\s*-\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'From\s+S\d+\s*to\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+\s*-\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+\s*to\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Season\s+\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Episode\s+\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s*[:-]\s*$'), '');
    return t.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  print('Refined: "${getRefinedDisplayName("From")}"');
}
