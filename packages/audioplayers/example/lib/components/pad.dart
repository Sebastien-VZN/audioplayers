import 'package:flutter/material.dart';

class Pad extends StatelessWidget {
  const Pad({super.key, this.width = 0, this.height = 0});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height);
  }
}
