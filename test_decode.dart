import 'dart:convert';

void main() {
  String input = 'dGIr6w/jgYLjgYTjgbvjgpPjga';
  
  List<int>? decoded;
  
  while (input.isNotEmpty) {
    String padded = input.padRight(input.length + (4 - input.length % 4) % 4, '=');
    try {
      decoded = base64Decode(padded);
      print('Success with input length \${input.length}, string: \$input');
      break;
    } catch (e) {
      input = input.substring(0, input.length - 1);
    }
  }

  if (decoded == null) {
      print('Could not decode at all');
      return;
  }
  
  print('Decoded size: ${decoded.length}');
  print('Decoded bytes: $decoded');
  
  if (decoded.length >= 5) {
    int magic = decoded[0] | (decoded[1] << 8);
    int nonce = decoded[2] | (decoded[3] << 8);
    int len = decoded[4];
    
    print('Magic: ${magic.toRadixString(16)}, Nonce: $nonce, Len: $len');
      
    if (decoded.length >= 5 + len) {
      String teaser = utf8.decode(decoded.sublist(5, 5 + len));
      print('Teaser: $teaser');
    } else {
      print('ERR: Decoded size ${decoded.length} is smaller than 5 + len ${5+len}');
    }
  }
}
