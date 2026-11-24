import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/voice_input.dart';
import 'guide_controller.dart';
import 'guide_language.dart';

/// What the "More thorough" shortcut asks for.
const String moreThoroughRequest = 'Please give me a longer, more thorough explanation.';

/// Lets the traveller write or say something to the guide: a wish for a more
/// thorough explanation, or any question about what they are looking at.
class AskGuideBar extends ConsumerStatefulWidget {
  const AskGuideBar({super.key});

  @override
  ConsumerState<AskGuideBar> createState() => _AskGuideBarState();
}

class _AskGuideBarState extends ConsumerState<AskGuideBar> {
  final TextEditingController _text = TextEditingController();
  bool _listening = false;

  GuideController get _guide => ref.read(guideControllerProvider.notifier);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _sendTyped() {
    _guide.ask(_text.text);
    _text.clear();
    FocusScope.of(context).unfocus();
  }

  /// Listen to the traveller, then pass on what they said. A spoken request
  /// gets a spoken answer.
  Future<void> _sendSpoken() async {
    setState(() => _listening = true);
    try {
      final said = await ref
          .read(voiceInputProvider)
          .listen(languageCode: ref.read(guideLanguageProvider).code);
      if (said != null) await _guide.ask(said, speak: true);
    } catch (_) {
      _report('Voice input is not available. You can type your request instead.');
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(guideControllerProvider.select((state) => state.status));
    final enabled = status == GuideStatus.ready || status == GuideStatus.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('askField'),
          controller: _text,
          enabled: enabled,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendTyped(),
          decoration: InputDecoration(
            hintText: _listening ? 'Listening…' : 'Ask for more detail, or anything else',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('askMicButton'),
                  tooltip: 'Say it',
                  icon: Icon(_listening ? Icons.hearing : Icons.mic),
                  onPressed: enabled && !_listening ? _sendSpoken : null,
                ),
                IconButton(
                  key: const Key('askSendButton'),
                  tooltip: 'Send',
                  icon: const Icon(Icons.send),
                  onPressed: enabled ? _sendTyped : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        ActionChip(
          key: const Key('moreThoroughChip'),
          avatar: const Icon(Icons.unfold_more, size: 18),
          label: const Text('More thorough'),
          onPressed: enabled ? () => _guide.ask(moreThoroughRequest) : null,
        ),
      ],
    );
  }
}
