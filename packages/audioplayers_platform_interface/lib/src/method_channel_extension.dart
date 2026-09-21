import 'package:flutter/services.dart';

extension StandardMethodChannel on MethodChannel {
  Future<void> call(String method, [Map<String, dynamic> args = const {}]) async {
    return await invokeMethod<void>(method, args);
  }

  Future<T?> compute<T>(String method, Map<String, dynamic> args) async {
    return await invokeMethod<T>(method, args);
  }
}
