import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapLocationPicker extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final double initialRadiusKm;
  final String initialLabel;

  const MapLocationPicker({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialRadiusKm = 25,
    this.initialLabel = 'Cerca de mi ubicación',
  });

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  late double _radiusKm;
  late TextEditingController _labelC;

  LatLng? _center; // centro actual del mapa
  LatLng? _currentLocation; // ubicación real del usuario (si la tenemos)
  GoogleMapController? _mapController;
  bool _loadingLocation = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _radiusKm = widget.initialRadiusKm;
    _labelC = TextEditingController(text: widget.initialLabel);
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      // Si ya viene una posición inicial, la usamos
      if (widget.initialLat != null && widget.initialLng != null) {
        final latLng = LatLng(widget.initialLat!, widget.initialLng!);
        setState(() {
          _center = latLng;
          _currentLocation = latLng;
          _loadingLocation = false;
        });
        return;
      }

      // Si no, intentamos obtener la ubicación real del usuario
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Servicios de ubicación apagados → fallback a CDMX
        setState(() {
          _center = const LatLng(19.432608, -99.133209); // CDMX
          _currentLocation = _center;
          _loadingLocation = false;
          _error =
              'No pudimos acceder a tu ubicación. Ajusta la zona moviendo el mapa.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _center = const LatLng(19.432608, -99.133209); // CDMX
          _currentLocation = _center;
          _loadingLocation = false;
          _error =
              'No pudimos acceder a tu ubicación. Ajusta la zona moviendo el mapa.';
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = latLng;
        _currentLocation = latLng;
        _loadingLocation = false;
      });

      // Mover la cámara si el mapa ya está listo
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: latLng, zoom: 12),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _center = const LatLng(19.432608, -99.133209); // CDMX
        _currentLocation = _center;
        _loadingLocation = false;
        _error =
            'Ocurrió un problema al obtener tu ubicación. Ajusta la zona moviendo el mapa.';
      });
    }
  }

  @override
  void dispose() {
    _labelC.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onCameraMove(CameraPosition position) {
    // Conforme el usuario mueve el mapa, actualizamos el centro
    setState(() {
      _center = position.target;
    });
  }

  void _goToCurrentLocation() {
    if (_currentLocation == null || _mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _currentLocation!, zoom: 12),
      ),
    );
  }

  void _confirmSelection() {
    if (_center == null) return;

    final label = _labelC.text.trim().isEmpty
        ? 'Zona personalizada'
        : _labelC.text.trim();

    Navigator.of(context).pop({
      'lat': _center!.latitude,
      'lng': _center!.longitude,
      'radiusKm': _radiusKm,
      'label': label,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecciona la zona'),
        actions: [
          TextButton(
            onPressed: _confirmSelection,
            child: const Text(
              'Usar zona',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _loadingLocation || _center == null
          ? Center(
              child: _loadingLocation
                  ? const CircularProgressIndicator()
                  : const Text('Cargando mapa...'),
            )
          : Column(
              children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    color: Colors.amber[800],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(_error!, style: const TextStyle(fontSize: 12)),
                  ),
                ],
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _center!,
                          zoom: 11,
                        ),
                        onMapCreated: _onMapCreated,
                        onCameraMove: _onCameraMove,
                        myLocationEnabled: _currentLocation != null,
                        myLocationButtonEnabled: false,
                        circles: {
                          Circle(
                            circleId: const CircleId('radius'),
                            center: _center!,
                            radius: _radiusKm * 1000, // km → metros
                            strokeWidth: 1,
                            strokeColor: Colors.blueAccent.withOpacity(0.7),
                            fillColor: Colors.blueAccent.withOpacity(0.15),
                          ),
                        },
                      ),
                      // Punto fijo en el centro (pin)
                      Center(
                        child: IgnorePointer(
                          ignoring: true,
                          child: Icon(
                            Icons.place,
                            size: 40,
                            color: Colors.redAccent.shade400,
                          ),
                        ),
                      ),
                      // Botón para ir a mi ubicación
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: FloatingActionButton(
                          mini: true,
                          onPressed: _goToCurrentLocation,
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Radio de alcance',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Slider(
                        value: _radiusKm.clamp(5, 200),
                        min: 5,
                        max: 200,
                        divisions: 39,
                        label: '${_radiusKm.round()} km',
                        onChanged: (val) {
                          setState(() {
                            _radiusKm = val;
                          });
                        },
                      ),
                      Text(
                        'Aproximadamente ${_radiusKm.round()} km a la redonda.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _labelC,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la zona (opcional)',
                          hintText:
                              'Ej: “Zona Monterrey”, “CDMX y alrededores”…',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
