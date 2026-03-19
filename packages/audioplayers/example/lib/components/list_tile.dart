import 'package:flutter/material.dart';

class WrappedListTile extends StatelessWidget {
  const WrappedListTile({
    required this.children,
    this.leading,
    this.trailing,
    super.key,
  });
  final List<Widget> children;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Wrap(alignment: WrapAlignment.end, children: children),
      leading: leading,
      trailing: trailing,
    );
  }
}
