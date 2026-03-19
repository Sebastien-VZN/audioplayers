import 'package:flutter/material.dart';

class LabeledDropDown<T> extends StatelessWidget {
  const LabeledDropDown({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChange,
    super.key,
  });
  final String label;
  final Map<T, String> options;
  final T selected;
  final void Function(T?) onChange;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: CustomDropDown<T>(
        options: options,
        selected: selected,
        onChange: onChange,
      ),
    );
  }
}

class CustomDropDown<T> extends StatelessWidget {
  const CustomDropDown({
    required this.options,
    required this.selected,
    required this.onChange,
    this.isExpanded = false,
    super.key,
  });
  final Map<T, String> options;
  final T selected;
  final void Function(T?) onChange;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      isExpanded: isExpanded,
      value: selected,
      onChanged: onChange,
      items: options.entries
          .map<DropdownMenuItem<T>>(
            (entry) =>
                DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
          )
          .toList(),
    );
  }
}
