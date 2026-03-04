import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uvccamera/uvccamera.dart';

List<CameraDescription> internalCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [Permission.camera, Permission.microphone].request();
  try {
    internalCameras = await availableCameras();
  } catch (e) {
    debugPrint('Internal camera error: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Camera App',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ════════════════════════════════════════════
// HOME SCREEN
// ════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _uvcSupported = false;
  final Map<String, UvcCameraDevice> _uvcDevices = {};
  StreamSubscription<UvcCameraDeviceEvent>? _deviceEventSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final supported = await UvcCamera.isSupported();
    if (!mounted) return;
    setState(() => _uvcSupported = supported);

    if (supported) {
      final devices = await UvcCamera.getDevices();
      if (!mounted) return;
      setState(() => _uvcDevices.addAll(devices));

      _deviceEventSub = UvcCamera.deviceEventStream.listen((event) {
        if (!mounted) return;
        setState(() {
          if (event.type == UvcCameraDeviceEventType.attached) {
            _uvcDevices[event.device.name] = event.device;
          } else if (event.type == UvcCameraDeviceEventType.detached) {
            _uvcDevices.remove(event.device.name);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _deviceEventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Camera App', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Buttons ──
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Internal Camera'),
                    onPressed: internalCameras.isEmpty
                        ? null
                        : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                          const InternalCameraScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.usb),
                    label: const Text('USB Camera'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => UsbCameraListScreen(
                            devices: _uvcDevices,
                            isSupported: _uvcSupported,
                          )),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Status ──
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt,
                      size: 80, color: Colors.white38),
                  const SizedBox(height: 16),
                  _StatusRow(
                    icon: internalCameras.isNotEmpty
                        ? Icons.check_circle
                        : Icons.error_outline,
                    label: internalCameras.isNotEmpty
                        ? 'Internal cameras: ${internalCameras.length}'
                        : 'No internal cameras',
                    color: internalCameras.isNotEmpty
                        ? Colors.teal
                        : Colors.redAccent,
                  ),
                  const SizedBox(height: 10),
                  _StatusRow(
                    icon: _uvcSupported
                        ? Icons.check_circle
                        : Icons.error_outline,
                    label: _uvcSupported
                        ? 'UVC supported — devices: ${_uvcDevices.length}'
                        : 'UVC not supported on this device',
                    color:
                    _uvcSupported ? Colors.deepPurple : Colors.redAccent,
                  ),
                  if (_uvcDevices.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ..._uvcDevices.values.map(
                          (d) => _StatusRow(
                        icon: Icons.videocam,
                        label: '${d.name} (VID:${d.vendorId} PID:${d.productId})',
                        color: Colors.greenAccent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusRow(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              style: TextStyle(color: color, fontSize: 14),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════
// INTERNAL CAMERA SCREEN
// ════════════════════════════════════════════
class InternalCameraScreen extends StatefulWidget {
  const InternalCameraScreen({super.key});

  @override
  State<InternalCameraScreen> createState() => _InternalCameraScreenState();
}

class _InternalCameraScreenState extends State<InternalCameraScreen> {
  CameraController? _controller;
  int _selectedIndex = 0;
  bool _isInitializing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (internalCameras.isNotEmpty) _initCamera(0);
  }

  Future<void> _initCamera(int index) async {
    if (_isInitializing) return;
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    await _controller?.dispose();
    _controller = null;

    try {
      _controller = CameraController(
        internalCameras[index],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _selectedIndex = index;
          _isInitializing = false;
        });
      }
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Camera error: ${e.description}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Error: $e';
        });
      }
    }
  }

  void _toggleFrontBack() {
    if (internalCameras.length < 2) return;
    final current = internalCameras[_selectedIndex].lensDirection;
    final nextIndex =
    internalCameras.indexWhere((c) => c.lensDirection != current);
    if (nextIndex != -1) _initCamera(nextIndex);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Internal Camera'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(child: _buildPreview()),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ...List.generate(internalCameras.length, (i) {
                  final dir = internalCameras[i].lensDirection;
                  final label = dir == CameraLensDirection.front
                      ? 'Front'
                      : dir == CameraLensDirection.back
                      ? 'Back'
                      : 'Ext $i';
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: i == _selectedIndex
                          ? Colors.teal
                          : Colors.white24,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed:
                    _isInitializing ? null : () => _initCamera(i),
                    child: Text(label),
                  );
                }),
                IconButton(
                  onPressed: _isInitializing ? null : _toggleFrontBack,
                  icon: Icon(
                    Icons.flip_camera_android,
                    color:
                    _isInitializing ? Colors.white24 : Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.teal),
            SizedBox(height: 16),
            Text('Initializing...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _initCamera(_selectedIndex),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.teal));
    }

    final lensDir = internalCameras[_selectedIndex].lensDirection;
    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: CameraPreview(_controller!),
          ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Colors.tealAccent.withOpacity(0.4)),
            ),
            child: Text(
              lensDir == CameraLensDirection.front
                  ? '🤳 Front'
                  : '📷 Back',
              style: const TextStyle(
                  color: Colors.tealAccent, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════
// USB CAMERA LIST SCREEN
// ════════════════════════════════════════════
class UsbCameraListScreen extends StatefulWidget {
  final Map<String, UvcCameraDevice> devices;
  final bool isSupported;

  const UsbCameraListScreen(
      {super.key, required this.devices, required this.isSupported});

  @override
  State<UsbCameraListScreen> createState() => _UsbCameraListScreenState();
}

class _UsbCameraListScreenState extends State<UsbCameraListScreen> {
  late Map<String, UvcCameraDevice> _devices;
  StreamSubscription<UvcCameraDeviceEvent>? _deviceEventSub;

  @override
  void initState() {
    super.initState();
    _devices = Map.from(widget.devices);

    _deviceEventSub = UvcCamera.deviceEventStream.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event.type == UvcCameraDeviceEventType.attached) {
          _devices[event.device.name] = event.device;
        } else if (event.type == UvcCameraDeviceEventType.detached) {
          _devices.remove(event.device.name);
        }
      });
    });
  }

  @override
  void dispose() {
    _deviceEventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('USB Cameras'),
        centerTitle: true,
      ),
      body: !widget.isSupported
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 60, color: Colors.redAccent),
            SizedBox(height: 16),
            Text(
              'UVC Camera is not\nsupported on this device',
              textAlign: TextAlign.center,
              style:
              TextStyle(color: Colors.redAccent, fontSize: 16),
            ),
          ],
        ),
      )
          : _devices.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.usb_off,
                size: 80, color: Colors.white24),
            const SizedBox(height: 20),
            const Text(
              'Koi USB camera nahi mila\nOTG cable se connect karo',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: () async {
                final devices = await UvcCamera.getDevices();
                if (mounted) {
                  setState(() {
                    _devices.clear();
                    _devices.addAll(devices);
                  });
                }
              },
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices.values.elementAt(index);
          return Card(
            color: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.deepPurple,
                child: Icon(Icons.videocam, color: Colors.white),
              ),
              title: Text(
                device.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'VID: ${device.vendorId}  |  PID: ${device.productId}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios,
                  color: Colors.white38, size: 16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      UsbCameraPreviewScreen(device: device),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════
// USB CAMERA PREVIEW SCREEN
// ════════════════════════════════════════════
class UsbCameraPreviewScreen extends StatefulWidget {
  final UvcCameraDevice device;

  const UsbCameraPreviewScreen({super.key, required this.device});

  @override
  State<UsbCameraPreviewScreen> createState() =>
      _UsbCameraPreviewScreenState();
}

class _UsbCameraPreviewScreenState extends State<UsbCameraPreviewScreen>
    with WidgetsBindingObserver {
  bool _isAttached = false;
  bool _hasDevicePermission = false;
  bool _hasCameraPermission = false;
  bool _isDeviceAttached = false;
  bool _isDeviceConnected = false;
  UvcCameraController? _cameraController;
  Future<void>? _initFuture;
  StreamSubscription<UvcCameraDeviceEvent>? _deviceEventSub;
  StreamSubscription<UvcCameraErrorEvent>? _errorEventSub;
  StreamSubscription<UvcCameraStatusEvent>? _statusEventSub;
  String _statusMessage = 'Connecting...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detach(force: true);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _attach();
    } else if (state == AppLifecycleState.paused) {
      _detach();
    }
  }

  void _attach({bool force = false}) {
    if (_isAttached && !force) return;

    UvcCamera.getDevices().then((devices) {
      if (!devices.containsKey(widget.device.name)) {
        if (mounted) {
          setState(() => _statusMessage = 'Device not found. Reconnect karo.');
        }
        return;
      }
      setState(() => _isDeviceAttached = true);
      _requestPermissions();
    });

    _deviceEventSub = UvcCamera.deviceEventStream.listen((event) {
      if (event.device.name != widget.device.name) return;
      if (!mounted) return;

      if (event.type == UvcCameraDeviceEventType.attached && !_isDeviceAttached) {
        _requestPermissions();
      }

      setState(() {
        switch (event.type) {
          case UvcCameraDeviceEventType.attached:
            _isDeviceAttached = true;
            _isDeviceConnected = false;
            _statusMessage = 'Device attached. Permission maang raha hai...';
            break;
          case UvcCameraDeviceEventType.detached:
            _hasCameraPermission = false;
            _hasDevicePermission = false;
            _isDeviceAttached = false;
            _isDeviceConnected = false;
            _statusMessage = 'Device disconnected.';
            _cleanupCamera();
            break;
          case UvcCameraDeviceEventType.connected:
            _hasCameraPermission = true;
            _hasDevicePermission = true;
            _isDeviceAttached = true;
            _isDeviceConnected = true;
            _statusMessage = 'Connected! Preview load ho raha hai...';
            _setupCamera();
            break;
          case UvcCameraDeviceEventType.disconnected:
            _hasCameraPermission = false;
            _hasDevicePermission = false;
            _isDeviceConnected = false;
            _statusMessage = 'Disconnected.';
            _cleanupCamera();
            break;
          default:
            break;
        }
      });
    });

    _isAttached = true;
  }

  void _detach({bool force = false}) {
    if (!_isAttached && !force) return;
    _hasDevicePermission = false;
    _hasCameraPermission = false;
    _isDeviceAttached = false;
    _isDeviceConnected = false;
    _cleanupCamera();
    _deviceEventSub?.cancel();
    _deviceEventSub = null;
    _isAttached = false;
  }

  void _cleanupCamera() {
    _errorEventSub?.cancel();
    _errorEventSub = null;
    _statusEventSub?.cancel();
    _statusEventSub = null;
    _cameraController?.dispose();
    _cameraController = null;
    _initFuture = null;
  }

  void _setupCamera() {
    _cameraController = UvcCameraController(device: widget.device);
    _initFuture = _cameraController!.initialize().then((_) {
      _errorEventSub = _cameraController!.cameraErrorEvents.listen((event) {
        if (mounted) {
          setState(() => _statusMessage = 'Error: ${event.error}');
        }
        // Auto reconnect on preview interrupted
        if (event.error.type == UvcCameraErrorType.previewInterrupted) {
          _detach();
          _attach();
        }
      });

      _statusEventSub =
          _cameraController!.cameraStatusEvents.listen((event) {
            debugPrint('UVC status: ${event.payload}');
          });
    });

    if (mounted) setState(() {});
  }

  Future<void> _requestPermissions() async {
    // Step 1: Camera permission
    var camStatus = await Permission.camera.status;
    if (!camStatus.isGranted) {
      camStatus = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      _hasCameraPermission = camStatus.isGranted;
      _statusMessage = camStatus.isGranted
          ? 'USB device permission maang raha hai...'
          : 'Camera permission denied!';
    });

    if (!camStatus.isGranted) return;

    // Step 2: USB device permission
    final devicePermission =
    await UvcCamera.requestDevicePermission(widget.device);
    if (!mounted) return;
    setState(() {
      _hasDevicePermission = devicePermission;
      if (!devicePermission) {
        _statusMessage = 'USB device permission denied!';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.device.name),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 14),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _isDeviceConnected
                    ? Colors.greenAccent
                    : Colors.white30,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isDeviceConnected
                        ? Colors.greenAccent
                        : Colors.white30)
                        .withOpacity(0.6),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Not connected yet — show status
    if (!_isDeviceConnected || _cameraController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.deepPurple),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 15, height: 1.5),
              ),
            ),
            if (!_isDeviceAttached) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () {
                  _detach(force: true);
                  _attach(force: true);
                },
              ),
            ],
          ],
        ),
      );
    }

    // Connected — show preview
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.deepPurple),
                SizedBox(height: 16),
                Text('Preview load ho raha hai...',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 60, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  'Preview error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    _detach(force: true);
                    _attach(force: true);
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return Stack(
          children: [
            // Preview
            Positioned.fill(
              child: UvcCameraPreview(_cameraController!),
            ),
            // Live label
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.greenAccent.withOpacity(0.4)),
                ),
                child: const Text(
                  '🟢 USB Live',
                  style: TextStyle(
                      color: Colors.greenAccent, fontSize: 13),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}