import 'package:flutter/material.dart';

extension UriCoder on Uri {
  static String encodeOnce(String uri) {
    try {
      // If decoded differs, the uri was already encoded.
      final decodedUri = Uri.decodeFull(uri);
      if (decodedUri != uri) {
        return uri;
      }
    } on Exception catch (args) {
      debugPrint("ERROR encodeOnce $args");
    }
    return Uri.encodeFull(uri);
  }
}
