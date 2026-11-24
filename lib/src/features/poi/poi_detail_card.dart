import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../guide/open_guide.dart';
import 'poi_model.dart';
import 'poi_style.dart';

/// A card displaying detailed information about a POI
class PoiDetailCard extends ConsumerWidget {
  final Poi poi;
  final VoidCallback? onClose;

  /// Opens the AI guide for [poi].
  final VoidCallback? onGuide;

  const PoiDetailCard({super.key, required this.poi, this.onClose, this.onGuide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = styleFor(poi.categories).color;
    final note = reasonLabel(poi);

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(title: poi.name, color: color, onClose: onClose),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DistanceRow(distance: poi.distance, note: note),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in poi.categories)
                      Chip(
                        label: Text(categoryLabel(category), style: const TextStyle(fontSize: 12)),
                        backgroundColor: color.withValues(alpha: 0.2),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  poi.snippet,
                  style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    key: const Key('guideButton'),
                    onPressed: onGuide,
                    icon: const Icon(Icons.headphones),
                    label: const Text('Hear the story'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.color, this.onClose});

  final String title;
  final Color color;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

class _DistanceRow extends StatelessWidget {
  const _DistanceRow({required this.distance, this.note});

  final int distance;

  /// Why the place is recommended, e.g. "Classic".
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.directions_walk, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          formatDistance(distance),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        if (note != null) ...[
          const SizedBox(width: 12),
          Flexible(child: ReasonBadge(label: note!)),
        ],
      ],
    );
  }
}

/// A small pill saying why a place is recommended.
class ReasonBadge extends StatelessWidget {
  const ReasonBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: colors.onSecondaryContainer),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Show the details of [poi] in a dialog, from which the guide can be opened.
void showPoiDetailDialog(BuildContext context, WidgetRef ref, Poi poi) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: PoiDetailCard(
        poi: poi,
        onClose: () => Navigator.of(dialogContext).pop(),
        onGuide: () {
          Navigator.of(dialogContext).pop();
          openGuide(context, ref, poi: poi);
        },
      ),
    ),
  );
}
