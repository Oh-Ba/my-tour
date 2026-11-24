import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../guide/open_guide.dart';
import 'poi_detail_card.dart';
import 'poi_repository.dart';
import 'poi_style.dart';

/// Bottom sheet displaying a list of POIs
class PoiListSheet extends ConsumerWidget {
  final void Function(String poiId) onPoiTap;

  /// Change the interests or radius of the running tour.
  final VoidCallback onEditTrip;

  final VoidCallback onEndTrip;

  /// Look for places again after a failed search.
  final VoidCallback onRetry;

  const PoiListSheet({
    super.key,
    required this.onPoiTap,
    required this.onEditTrip,
    required this.onEndTrip,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poiState = ref.watch(poiRepositoryProvider);
    final sortedPois = ref.watch(sortedPoisProvider);
    final repository = ref.read(poiRepositoryProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.3,
      minChildSize: 0.12,
      maxChildSize: 0.7,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2)),
            ],
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: _SheetHeader(
                  count: sortedPois.length,
                  isLoading: poiState.isLoading,
                  onEditTrip: onEditTrip,
                  onEndTrip: onEndTrip,
                ),
              ),
              if (poiState.error != null && !poiState.isLoading)
                SliverToBoxAdapter(
                  child: _ErrorRow(message: poiState.error!, onRetry: onRetry),
                ),
              if (sortedPois.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyList(isLoading: poiState.isLoading),
                )
              else
                SliverList.separated(
                  itemCount: sortedPois.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final poi = sortedPois[index];
                    return PoiListTile(
                      poi: poi,
                      isSelected: poiState.selectedPoiId == poi.id,
                      onTap: () {
                        repository.selectPoi(poi.id);
                        onPoiTap(poi.id);
                      },
                      onInfoTap: () => showPoiDetailDialog(context, ref, poi),
                      onGuideTap: () => openGuide(context, ref, poi: poi, autoPlay: true),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.count,
    required this.isLoading,
    required this.onEditTrip,
    required this.onEndTrip,
  });

  final int count;
  final bool isLoading;
  final VoidCallback onEditTrip;
  final VoidCallback onEndTrip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              Text(
                'Nearby Places',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  '$count found',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
              const Spacer(),
              IconButton(
                key: const Key('editTripButton'),
                tooltip: 'Edit tour',
                icon: const Icon(Icons.tune),
                onPressed: onEditTrip,
              ),
              IconButton(
                key: const Key('endTripButton'),
                tooltip: 'End tour',
                icon: const Icon(Icons.flag_outlined),
                onPressed: onEndTrip,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.red))),
          TextButton(
            key: const Key('retryPlacesButton'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(isLoading ? Icons.travel_explore : Icons.location_off, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          isLoading ? 'Looking for places around you…' : 'No places found nearby',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

/// Individual POI list item
class PoiListTile extends StatelessWidget {
  final Poi poi;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  /// Opens the AI guide and starts reading.
  final VoidCallback onGuideTap;

  const PoiListTile({
    super.key,
    required this.poi,
    required this.isSelected,
    required this.onTap,
    required this.onInfoTap,
    required this.onGuideTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleFor(poi.categories);
    final note = reasonLabel(poi);

    return Material(
      color: isSelected ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4, top: 12, bottom: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(style.icon, color: style.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      poi.snippet,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.directions_walk, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          formatDistance(poi.distance),
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        if (note != null) ...[
                          const SizedBox(width: 8),
                          Flexible(child: ReasonBadge(label: note)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hear the story',
                icon: const Icon(Icons.headphones),
                onPressed: onGuideTap,
                color: Theme.of(context).colorScheme.primary,
              ),
              IconButton(
                tooltip: 'Details',
                icon: const Icon(Icons.info_outline),
                onPressed: onInfoTap,
                color: Colors.grey[600],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
