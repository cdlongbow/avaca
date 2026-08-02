import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

class JavBusVerificationOption {
  const JavBusVerificationOption({required this.value, required this.label});

  final String value;
  final String label;
}

class JavBusVerificationQuestion {
  const JavBusVerificationQuestion({
    required this.name,
    required this.prompt,
    required this.options,
  });

  final String name;
  final String prompt;
  final List<JavBusVerificationOption> options;
}

class JavBusVerificationChallenge {
  const JavBusVerificationChallenge({
    required this.submitUri,
    required this.hiddenFields,
    required this.submitFields,
    required this.questions,
  });

  final Uri submitUri;
  final Map<String, String> hiddenFields;
  final Map<String, String> submitFields;
  final List<JavBusVerificationQuestion> questions;

  static JavBusVerificationChallenge? parse(
    String source, {
    required Uri pageUri,
  }) {
    final document = html.parse(source);
    final form =
        document.querySelector('form[action*="driver-verify.php"]') ??
        document.querySelector('form#form1');
    if (form == null) {
      return null;
    }
    final action = form.attributes['action']?.trim();

    final hiddenFields = <String, String>{};
    for (final input in form.querySelectorAll('input[type="hidden"]')) {
      final name = input.attributes['name']?.trim();
      if (name != null && name.isNotEmpty) {
        hiddenFields[name] = input.attributes['value'] ?? '';
      }
    }

    final submitFields = <String, String>{};
    for (final control in form.querySelectorAll(
      'input[type="submit"], button[type="submit"], button:not([type])',
    )) {
      final name = control.attributes['name']?.trim();
      if (name != null && name.isNotEmpty) {
        submitFields[name] = control.attributes['value'] ?? '';
      }
    }

    final questions = form
        .querySelectorAll('li')
        .map(_parseQuestion)
        .whereType<JavBusVerificationQuestion>()
        .toList(growable: false);
    if (questions.isEmpty && submitFields.isEmpty) {
      return null;
    }
    return JavBusVerificationChallenge(
      submitUri: action == null || action.isEmpty
          ? pageUri
          : pageUri.resolve(action),
      hiddenFields: hiddenFields,
      submitFields: submitFields,
      questions: questions,
    );
  }

  static JavBusVerificationQuestion? _parseQuestion(Element item) {
    final label = item.querySelector('label') ?? item;
    final radios = label.querySelectorAll('input[type="radio"]');
    if (radios.isEmpty) {
      return null;
    }
    final name = radios.first.attributes['name']?.trim();
    if (name == null || name.isEmpty) {
      return null;
    }

    final promptParts = <String>[];
    final optionLabels = <Element, String>{};
    Element? currentRadio;
    for (final node in label.nodes) {
      if (node is Element &&
          node.localName == 'input' &&
          node.attributes['type'] == 'radio') {
        currentRadio = node;
        continue;
      }
      if (node is Text) {
        final text = node.data.trim();
        if (text.isEmpty) {
          continue;
        }
        if (currentRadio == null) {
          promptParts.add(text);
        } else {
          optionLabels.putIfAbsent(currentRadio, () => text);
        }
      }
    }

    final options = radios
        .map(
          (radio) => JavBusVerificationOption(
            value: radio.attributes['value'] ?? '',
            label: optionLabels[radio] ?? radio.attributes['value'] ?? '',
          ),
        )
        .where((option) => option.value.isNotEmpty)
        .toList(growable: false);
    if (options.isEmpty) {
      return null;
    }
    return JavBusVerificationQuestion(
      name: name,
      prompt: promptParts.join(' ').trim(),
      options: options,
    );
  }
}

typedef JavBusVerificationHandler =
    Future<Map<String, String>?> Function(
      JavBusVerificationChallenge challenge,
    );

class JavBusVerificationCancelledException implements Exception {
  const JavBusVerificationCancelledException();

  @override
  String toString() => 'JavBus verification was cancelled.';
}
