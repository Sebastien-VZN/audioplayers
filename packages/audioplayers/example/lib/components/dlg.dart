import 'package:audioplayers_example/components/btn.dart';
import 'package:flutter/material.dart';

class SimpleDlg extends StatelessWidget {
  const SimpleDlg({required this.message, required this.action, super.key});
  final String message;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Dlg(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          Btn(txt: action, onPressed: Navigator.of(context).pop),
        ],
      ),
    );
  }
}

class Dlg extends StatelessWidget {
  const Dlg({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
