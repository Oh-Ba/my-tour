import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../poi/poi_style.dart' show formatDistance;
import 'guide_controller.dart';
import 'rest_spot_service.dart';

/// Shows the guide's offer of somewhere nice to sit whenever one is made.
/// Call from `build` of any page that plays stories.
void watchSeatOffers(WidgetRef ref, BuildContext context) {
  ref.listen(guideControllerProvider, (previous, next) {
    final offeredNow = (previous?.seatOffer.isEmpty ?? true) && next.seatOffer.isNotEmpty;
    if (offeredNow) _showSeatOffer(context, ref.read(guideControllerProvider.notifier), next);
  });
}

Future<void> _showSeatOffer(BuildContext context, GuideController controller, GuideState state) async {
  final chosen = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SeatOfferSheet(
      minutes: state.minutes ?? seatOfferMinMinutes,
      spots: state.seatOffer,
      onExplainHere: controller.explainHere,
      onGoTo: controller.goTo,
    ),
  );
  if (chosen != true) await controller.dismissOffer();
}

/// "This takes N minutes - sit somewhere nice, or hear it right here?"
class SeatOfferSheet extends StatelessWidget {
  const SeatOfferSheet({
    super.key,
    required this.minutes,
    required this.spots,
    required this.onExplainHere,
    required this.onGoTo,
  });

  final int minutes;
  final List<RestSpot> spots;
  final VoidCallback onExplainHere;
  final ValueChanged<RestSpot> onGoTo;

  /// Close the sheet, then do what was chosen.
  void _choose(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop(true);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This explanation takes about $minutes minutes.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text('Would you like to sit somewhere nice nearby while you listen?'),
            const SizedBox(height: 8),
            for (final spot in spots)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(spot.kind.icon, color: theme.colorScheme.primary),
                title: Text(spot.name),
                subtitle: Text('${spot.kind.label} · ${formatDistance(spot.distance)}'),
                trailing: TextButton(
                  key: Key('goTo_${spot.id}'),
                  onPressed: () => _choose(context, () => onGoTo(spot)),
                  child: const Text('Take me there'),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('explainHereButton'),
              onPressed: () => _choose(context, onExplainHere),
              icon: const Icon(Icons.volume_up),
              label: const Text("It's fine, explain here"),
            ),
          ],
        ),
      ),
    );
  }
}
