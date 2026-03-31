import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../core/providers/location_provider.dart';
import '../core/providers/responder_provider.dart';
import '../core/models/responder_model.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController _mapController;
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    // Don't initialize map here, wait for onMapCreated callback
  }

  /// Initialize map markers and circles
  void _initializeMap(double userLat, double userLng,
      List<ResponderModel> responders) {
    // Clear existing markers and circles
    _markers.clear();
    _circles.clear();

    _addUserMarker(userLat, userLng);
    _addResponderMarkers(responders, userLat, userLng);

    // Add 5km circle around user
    _circles.add(
      Circle(
        circleId: const CircleId('search_radius'),
        center: LatLng(userLat, userLng),
        radius: 5000, // 5km in meters
        fillColor: Colors.blue.withOpacity(0.1),
        strokeColor: Colors.blue.withOpacity(0.5),
        strokeWidth: 2,
      ),
    );
  }

  /// Add user location marker (blue)
  void _addUserMarker(double latitude, double longitude) {
    _markers.add(
      Marker(
        markerId: const MarkerId('user_location'),
        position: LatLng(latitude, longitude),
        infoWindow: const InfoWindow(
          title: 'Your Location',
          snippet: 'You are here',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueBlue,
        ),
      ),
    );
  }

  /// Add responder markers (red/orange)
  void _addResponderMarkers(List<ResponderModel> responders, double userLat,
      double userLng) {
    for (int i = 0; i < responders.length; i++) {
      final responder = responders[i];
      _markers.add(
        Marker(
          markerId: MarkerId('responder_${responder.id}'),
          position: LatLng(responder.latitude, responder.longitude),
          infoWindow: InfoWindow(
            title: responder.name,
            snippet:
                '${responder.skillsArea} • ${responder.distanceToLocation(userLat, userLng).toStringAsFixed(1)} km away',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        ),
      );
    }
  }

  /// Animate camera to user location
  void _focusUserLocation() {
    final locationProvider = context.read<LocationProvider>();
    if (locationProvider.hasLocation) {
      _mapController.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(
            locationProvider.latitude!,
            locationProvider.longitude!,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Responders Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _focusUserLocation,
            tooltip: 'Center on my location',
          ),
        ],
      ),
      body: Consumer2<LocationProvider, ResponderProvider>(
        builder: (context, locationProvider, responderProvider, _) {
          if (!locationProvider.hasLocation) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_off, size: 50),
                  const SizedBox(height: 16),
                  Text(
                    'Location not available',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              // Google Map
              GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                  // Initialize markers after map is created
                  _initializeMap(
                    locationProvider.latitude!,
                    locationProvider.longitude!,
                    responderProvider.nearbyResponders,
                  );
                  setState(() {});
                },
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    locationProvider.latitude!,
                    locationProvider.longitude!,
                  ),
                  zoom: 15,
                ),
                markers: _markers,
                circles: _circles,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomGesturesEnabled: true,
                scrollGesturesEnabled: true,
              ),
              // Info panel at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nearby Responders (5km radius)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (responderProvider.nearbyResponders.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No responders nearby',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          )
                        else
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount:
                                  responderProvider.nearbyResponders.length,
                              itemBuilder: (context, index) {
                                final responder =
                                    responderProvider.nearbyResponders[index];
                                final distance = responder.distanceToLocation(
                                  locationProvider.latitude!,
                                  locationProvider.longitude!,
                                );

                                return Container(
                                  margin: const EdgeInsets.only(right: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Colors.red.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      SizedBox(
                                        width: 120,
                                        child: Text(
                                          responder.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge,
                                        ),
                                      ),
                                      Text(
                                        responder.skillsArea,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                          color: Colors.red.shade600,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${distance.toStringAsFixed(1)} km away',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
