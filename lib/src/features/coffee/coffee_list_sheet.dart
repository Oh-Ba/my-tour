import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'coffee_service.dart';

/// Presents a modal list of nearby coffee spots fetched from the backend
class CoffeeListSheet extends ConsumerStatefulWidget {
  final double lat;
  final double lon;
  final int radiusM;
  final String? anchorPoiName;

  const CoffeeListSheet({
    super.key,
    required this.lat,
    required this.lon,
    this.radiusM = 800,
    this.anchorPoiName,
  });

  @override
  ConsumerState<CoffeeListSheet> createState() => _CoffeeListSheetState();
}

class _CoffeeListSheetState extends ConsumerState<CoffeeListSheet> {
  late Future<List<CoffeeSpot>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CoffeeSpot>> _load() async {
    final service = ref.read(coffeeServiceProvider);
    final response = await service.fetchCoffee(
      lat: widget.lat,
      lon: widget.lon,
      radiusM: widget.radiusM,
    );
    return response.spots;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.anchorPoiName != null
                  ? 'Need a break near ${widget.anchorPoiName}?'
                  : 'Coffee nearby',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Showing cafes within ${(widget.radiusM / 1000).toStringAsFixed(1)} km',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<CoffeeSpot>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(height: 8),
                          Text(
                            'Unable to load coffee spots:\n${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _future = _load();
                              });
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  final spots = snapshot.data ?? [];
                  if (spots.isEmpty) {
                    return Center(
                      child: Text(
                        'No coffee spots found nearby.\nTry expanding your search radius.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: spots.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final spot = spots[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(Icons.local_cafe),
                        ),
                        title: Text(
                          spot.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(spot.snippet),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.star, size: 16, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(spot.rating.toStringAsFixed(1)),
                                const SizedBox(width: 12),
                                const Icon(Icons.location_on, size: 16, color: Colors.blueGrey),
                                const SizedBox(width: 4),
                                Text('${spot.distance} m'),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCoffeeListSheet(
  BuildContext context, {
  required double lat,
  required double lon,
  int radiusM = 800,
  String? anchorPoiName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: CoffeeListSheet(
        lat: lat,
        lon: lon,
        radiusM: radiusM,
        anchorPoiName: anchorPoiName,
      ),
    ),
  );
}


