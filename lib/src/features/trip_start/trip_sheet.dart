import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trip_state.dart';

/// Bottom sheet for starting a tour or changing the one that is running.
class TripStartSheet extends ConsumerStatefulWidget {
  const TripStartSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<TripStartSheet> createState() => _TripStartSheetState();
}

class _TripStartSheetState extends ConsumerState<TripStartSheet> {
  late TripConfig _draft;
  final TextEditingController _customInterest = TextEditingController();

  @override
  void initState() {
    super.initState();
    // A tour that ended already has the classics re-checked (TripConfig.ended).
    _draft = ref.read(tripStateProvider);
    _customInterest.addListener(_refresh);
  }

  @override
  void dispose() {
    _customInterest.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _update(TripConfig draft) => setState(() => _draft = draft);

  /// The draft including whatever is typed but not added yet.
  TripConfig get _complete => _draft.copyWith(
        customInterests: addCustomInterest(_draft.customInterests, _customInterest.text),
      );

  void _toggleInterest(String interest) {
    final selected = _draft.interests.contains(interest);
    _update(_draft.copyWith(
      interests: selected
          ? _draft.interests.where((i) => i != interest).toList()
          : [..._draft.interests, interest],
    ));
  }

  void _addCustomInterest() {
    _update(_complete);
    _customInterest.clear();
  }

  void _removeCustomInterest(String interest) {
    _update(_draft.copyWith(
      customInterests: _draft.customInterests.where((i) => i != interest).toList(),
    ));
  }

  Future<void> _save() async {
    final trip = _complete;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    await ref.read(tripStateProvider.notifier).startTrip(trip);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Exploring within ${trip.radiusKm.toStringAsFixed(1)} km'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = _draft.isActive;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        controller: widget.scrollController,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          const _DragHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              editing ? 'Edit Your Tour' : 'Start Your Tour',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const _SectionTitle('What interests you?'),
          _InterestChips(selected: _draft.interests, onToggle: _toggleInterest),
          const SizedBox(height: 16),
          _CustomInterests(
            controller: _customInterest,
            interests: _draft.customInterests,
            onAdd: _addCustomInterest,
            onRemove: _removeCustomInterest,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('classicsCheckbox'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _draft.includeClassics,
            onChanged: (value) => _update(_draft.copyWith(includeClassics: value)),
            title: const Text('Classic recommendations'),
            subtitle: const Text('Always suggest museums, archaeology and historical places'),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Search radius'),
          _RadiusSlider(
            radiusKm: _draft.radiusKm,
            onChanged: (value) => _update(_draft.copyWith(radiusKm: value)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const Key('startTripButton'),
            onPressed: _complete.canStart ? _save : null,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(editing ? 'Update Tour' : 'Start Tour'),
          ),
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The ready-made interests, as toggle chips.
class _InterestChips extends StatelessWidget {
  const _InterestChips({required this.selected, required this.onToggle});

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final interest in availableInterests)
          FilterChip(
            label: Text(interest),
            selected: selected.contains(interest),
            onSelected: (_) => onToggle(interest),
            selectedColor: colors.primaryContainer,
            checkmarkColor: colors.primary,
          ),
      ],
    );
  }
}

/// A field for typing any other interest, and the ones typed so far.
class _CustomInterests extends StatelessWidget {
  const _CustomInterests({
    required this.controller,
    required this.interests,
    required this.onAdd,
    required this.onRemove,
  });

  final TextEditingController controller;
  final List<String> interests;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('customInterestField'),
          controller: controller,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onAdd(),
          decoration: InputDecoration(
            labelText: 'Anything else?',
            hintText: 'e.g. second hand stores',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              key: const Key('addCustomInterestButton'),
              icon: const Icon(Icons.add),
              tooltip: 'Add interest',
              onPressed: onAdd,
            ),
          ),
        ),
        if (interests.isNotEmpty) const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final interest in interests)
              InputChip(label: Text(interest), onDeleted: () => onRemove(interest)),
          ],
        ),
      ],
    );
  }
}

class _RadiusSlider extends StatelessWidget {
  const _RadiusSlider({required this.radiusKm, required this.onChanged});

  final double radiusKm;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = '${radiusKm.toStringAsFixed(1)} km';
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: radiusKm.clamp(1.0, 50.0),
            min: 1.0,
            max: 50.0,
            divisions: 49,
            label: label,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Helper function to show the trip sheet
void showTripSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) =>
          TripStartSheet(scrollController: scrollController),
    ),
  );
}
