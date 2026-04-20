import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/location_provider.dart';
import '../core/providers/app_settings_provider.dart';
import '../core/providers/responder_provider.dart';
import '../core/models/responder_model.dart';
import 'responder_chat_list_screen.dart';
import 'victim_chat_list_screen.dart';
import 'responder_profile_screen.dart';

class MapScreen extends StatefulWidget {
  final double? targetLatitude;
  final double? targetLongitude;
  final String? targetTitle;

  const MapScreen({
    super.key,
    this.targetLatitude,
    this.targetLongitude,
    this.targetTitle,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  IconData _iconForSkill(String skill) {
    final normalized = skill.toLowerCase();
    if (normalized.contains('medical')) return Icons.medical_services;
    if (normalized.contains('fire')) return Icons.local_fire_department;
    if (normalized.contains('search') || normalized.contains('rescue')) {
      return Icons.travel_explore;
    }
    if (normalized.contains('shelter') || normalized.contains('evacuation')) {
      return Icons.home;
    }
    if (normalized.contains('food') || normalized.contains('water')) {
      return Icons.restaurant;
    }
    if (normalized.contains('women')) return Icons.shield;
    if (normalized.contains('child') || normalized.contains('kid')) {
      return Icons.child_care;
    }
    if (normalized.contains('elderly')) return Icons.elderly;
    if (normalized.contains('communication')) return Icons.wifi_tethering;
    return Icons.support_agent;
  }

  Color _colorForSkill(String skill) {
    final normalized = skill.toLowerCase();
    if (normalized.contains('medical')) return Colors.teal;
    if (normalized.contains('fire')) return Colors.deepOrange;
    if (normalized.contains('search') || normalized.contains('rescue')) {
      return Colors.indigo;
    }
    if (normalized.contains('women') || normalized.contains('child')) {
      return Colors.pink.shade700;
    }
    return Colors.red;
  }

  @override
  void initState() {
    super.initState();
    // Don't initialize map here, wait for onMapCreated callback
  }

  bool get _hasTarget =>
      widget.targetLatitude != null && widget.targetLongitude != null;

  Future<void> _openExternalNavigation() async {
    if (!_hasTarget) {
      return;
    }

    final targetLat = widget.targetLatitude!;
    final targetLng = widget.targetLongitude!;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$targetLat,$targetLng&travelmode=driving',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Animate camera to user location
  void _focusUserLocation() {
    final locationProvider = context.read<LocationProvider>();
    if (locationProvider.hasLocation) {
      _mapController.move(
        LatLng(locationProvider.latitude!, locationProvider.longitude!),
        15,
      );
    }
  }

  List<Marker> _buildMarkers(
    double userLat,
    double userLng,
    List<ResponderModel> responders,
  ) {
    final settings = context.read<AppSettingsProvider>();
    final markers = <Marker>[
      Marker(
        point: LatLng(userLat, userLng),
        width: 44,
        height: 44,
        child: const Icon(Icons.my_location, color: Colors.blue, size: 34),
      ),
    ];

    for (final responder in responders) {
      markers.add(
        Marker(
          point: LatLng(responder.latitude, responder.longitude),
          width: 48,
          height: 48,
          child: Tooltip(
            message:
                '${settings.localizedDisplayName(responder.name)}\n${settings.localizedSkill(responder.skillsArea)} • ${settings.localizedResponderType(responder.responderType)}\n${settings.t('map_away_km').replaceAll('{distance}', responder.distanceToLocation(userLat, userLng).toStringAsFixed(1))}',
            child: Icon(
              _iconForSkill(responder.skillsArea),
              color: _colorForSkill(responder.skillsArea),
              size: 34,
            ),
          ),
        ),
      );
    }

    if (_hasTarget) {
      markers.add(
        Marker(
          point: LatLng(widget.targetLatitude!, widget.targetLongitude!),
          width: 52,
          height: 52,
          child: Tooltip(
            message: widget.targetTitle ?? settings.t('map_help_request'),
            child: const Icon(Icons.emergency, color: Colors.deepOrange, size: 38),
          ),
        ),
      );
    }

    return markers;
  }

  void _openResponderProfile(
    BuildContext context,
    ResponderModel responder,
    double viewerLatitude,
    double viewerLongitude,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResponderProfileScreen(
          responder: responder,
          viewerLatitude: viewerLatitude,
          viewerLongitude: viewerLongitude,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final navigator = Navigator.of(context);
            final auth = context.read<AuthProvider>();
            final didPop = await navigator.maybePop();
            if (didPop) return;
            if (!mounted) return;

            if (auth.currentUser?.isResponder == true) {
              navigator.pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ResponderChatListScreen(
                    currentUserId: auth.currentUser!.id,
                    currentUserName: auth.currentUser!.displayName,
                  ),
                ),
              );
            } else {
              navigator.pushReplacement(
                MaterialPageRoute(
                  builder: (_) => VictimChatListScreen(
                    currentUserId: auth.currentUser?.id ?? '',
                    currentUserName: auth.currentUser?.displayName ?? '',
                  ),
                ),
              );
            }
          },
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        title: Text(_hasTarget ? settings.t('map_navigation_map') : settings.t('map_responders_map')),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _focusUserLocation,
            tooltip: settings.t('map_center_location'),
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
                    settings.t('map_location_not_available'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (locationProvider.error != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        locationProvider.error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[700]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          await locationProvider.openLocationSettings();
                        },
                        icon: const Icon(Icons.gps_fixed),
                        label: Text(settings.t('map_turn_on_location')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await locationProvider.openPermissionSettings();
                        },
                        icon: const Icon(Icons.app_settings_alt),
                        label: Text(settings.t('map_grant_permission')),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await locationProvider.refreshLocationStatus(
                            fetchLocation: true,
                          );
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(settings.t('map_retry')),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(
                    locationProvider.latitude!,
                    locationProvider.longitude!,
                  ),
                  initialZoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.gdg.rescue_link',
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(
                          locationProvider.latitude!,
                          locationProvider.longitude!,
                        ),
                        radius: 120,
                        useRadiusInMeter: true,
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderColor: Colors.blue.withValues(alpha: 0.55),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                  if (_hasTarget)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [
                            LatLng(
                              locationProvider.latitude!,
                              locationProvider.longitude!,
                            ),
                            LatLng(widget.targetLatitude!, widget.targetLongitude!),
                          ],
                          strokeWidth: 5,
                          color: Colors.deepOrange,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: _buildMarkers(
                      locationProvider.latitude!,
                      locationProvider.longitude!,
                      responderProvider.nearbyResponders,
                    ),
                  ),
                ],
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
                        color: Colors.black.withValues(alpha: 0.1),
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
                          _hasTarget
                              ? settings.t('map_destination').replaceAll('{title}', widget.targetTitle ?? settings.t('map_help_request'))
                              : settings.t('map_nearby_responders'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_hasTarget)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _openExternalNavigation,
                                icon: const Icon(Icons.directions),
                                label: Text(settings.t('map_open_navigation')),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (responderProvider.nearbyResponders.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              settings.t('map_no_responders_nearby'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          )
                        else
                          SizedBox(
                            height: 132,
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

                                return InkWell(
                                  onTap: () => _openResponderProfile(
                                    context,
                                    responder,
                                    locationProvider.latitude!,
                                    locationProvider.longitude!,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 170,
                                    margin: const EdgeInsets.only(right: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.red.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.white,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        SizedBox(
                                          width: 148,
                                          child: Text(
                                            responder.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                        ),
                                        Text(
                                          settings.localizedSkill(responder.skillsArea),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                            color: Colors.red.shade600,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          settings.localizedResponderType(responder.responderType),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                        Text(
                                          settings
                                              .t('map_away_km')
                                              .replaceAll('{distance}', distance.toStringAsFixed(1)),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () => _openResponderProfile(
                                              context,
                                              responder,
                                              locationProvider.latitude!,
                                              locationProvider.longitude!,
                                            ),
                                            icon: const Icon(Icons.person, size: 16),
                                            label: Text(settings.t('map_view_profile')),
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(0, 0),
                                              tapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
    super.dispose();
  }
}
