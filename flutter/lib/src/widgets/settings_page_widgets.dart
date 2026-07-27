import 'package:flutter/material.dart';

import '../app_theme.dart';

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: ExampleTheme.primary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class SettingsSurface extends StatelessWidget {
  const SettingsSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleTheme.surface.withAlpha(224),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

final class PreferenceOption<T> {
  const PreferenceOption({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

class PreferenceSheet<T> extends StatelessWidget {
  const PreferenceSheet({
    super.key,
    required this.title,
    required this.currentValue,
    required this.options,
  });

  final String title;
  final T currentValue;
  final List<PreferenceOption<T>> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: options
                  .map(
                    (PreferenceOption<T> option) => _PreferenceTile<T>(
                      value: option.value,
                      groupValue: currentValue,
                      label: option.label,
                      onChanged: (T? value) {
                        if (value != null) {
                          Navigator.of(context).pop(value);
                        }
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceTile<T> extends StatelessWidget {
  const _PreferenceTile({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
  });

  final T value;
  final T groupValue;
  final String label;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<T>(
      value: value,
      // ignore: deprecated_member_use
      groupValue: groupValue,
      // ignore: deprecated_member_use
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(label),
    );
  }
}
