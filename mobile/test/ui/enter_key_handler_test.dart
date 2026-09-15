import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Enter key sends and Shift+Enter inserts newline simulation', (tester) async {
    final controller = TextEditingController(text: 'Hello Memento');
    final focusNode = FocusNode();
    bool sendTriggered = false;

    void insertNewline() {
      final text = controller.text;
      final selection = controller.selection;
      if (selection.isValid && selection.start >= 0 && selection.end >= 0) {
        final newText = text.replaceRange(selection.start, selection.end, '\n');
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: selection.start + 1),
        );
      } else {
        final newText = '$text\n';
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }

    focusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        final isComposing = controller.value.composing.isValid &&
            !controller.value.composing.isCollapsed;
        if (isComposing) {
          return KeyEventResult.ignored;
        }

        final isShift = HardwareKeyboard.instance.isShiftPressed;
        final isAlt = HardwareKeyboard.instance.isAltPressed;
        if (isShift || isAlt) {
          insertNewline();
          return KeyEventResult.handled;
        }

        sendTriggered = true;
        controller.clear();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 4,
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    // 1. Test Enter key triggers send and clears text
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sendTriggered, isTrue);
    expect(controller.text, isEmpty);

    // 2. Test Shift + Enter inserts newline
    controller.text = 'Line 1';
    controller.selection = const TextSelection.collapsed(offset: 6);
    sendTriggered = false;

    // Simulate Shift Down, Enter Down, Enter Up, Shift Up
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sendTriggered, isFalse);
    expect(controller.text, equals('Line 1\n'));
  });
}
