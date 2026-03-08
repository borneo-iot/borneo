import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:borneo_common/exceptions.dart';
import 'package:borneo_common/io/net/host_resolution.dart';
import 'package:borneo_kernel_abstractions/events.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:event_bus/event_bus.dart';

import 'package:borneo_kernel_abstractions/mdns.dart';
import 'package:borneo_kernel_abstractions/models/discovered_device.dart';

final class NsdMdnsDiscovery implements IMdnsDiscovery {
  bool _isDisposed = false;
  bool _isStopped = false;
  final String _serviceType;
  final BonsoirDiscovery _discovery;
  final EventBus _eventBus;
  StreamSubscription<BonsoirDiscoveryEvent>? _eventSub;

  NsdMdnsDiscovery(this._discovery, this._serviceType, this._eventBus) {
    _eventSub = _discovery.eventStream!.listen(_onServiceDiscovered);
    assert(_discovery.isReady);
    _discovery.start();
  }

  @override
  Future<void> stop({CancellationToken? cancelToken}) async {
    assert(!_isStopped);
    if (_isDisposed) {
      throw ObjectDisposedException(message: 'The object has been disposed!');
    }
    _discovery.stop();
    _isStopped = true;
  }

  void _onServiceDiscovered(BonsoirDiscoveryEvent event) {
    if (_isDisposed) {
      return;
    }
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        {
          event.service.resolve(_discovery.serviceResolver);
        }
        break;
      case BonsoirDiscoveryServiceResolvedEvent():
        {
          unawaited(_emitFoundDevice(event.service));
        }
        break;
      case BonsoirDiscoveryServiceUpdatedEvent():
        {
          unawaited(_emitFoundDevice(event.service));
        }
        break;
      case BonsoirDiscoveryServiceLostEvent():
        {
          unawaited(_emitLostDevice(event.service));
        }
        break;
      default:
        break;
    }
  }

  Future<void> _emitFoundDevice(BonsoirService service) async {
    final discovered = await _toDiscoveredDevice(service, normalizeHost: true);
    if (_isDisposed) {
      return;
    }
    _eventBus.fire(FoundDeviceEvent(discovered));
  }

  Future<void> _emitLostDevice(BonsoirService service) async {
    final discovered = await _toDiscoveredDevice(service, normalizeHost: false);
    if (_isDisposed) {
      return;
    }
    _eventBus.fire(LostDeviceEvent(discovered));
  }

  Future<MdnsDiscoveredDevice> _toDiscoveredDevice(BonsoirService service, {required bool normalizeHost}) async {
    final rawHost = service.host ?? 'UNKNOWN';
    final host = normalizeHost && rawHost != 'UNKNOWN' ? await resolveHostToPreferredAddress(rawHost) : rawHost;

    return MdnsDiscoveredDevice(
      host: host,
      port: service.port,
      serviceType: service.type,
      name: service.name,
      txt: service.attributes,
    );
  }

  @override
  String get serviceType => _serviceType;

  @override
  void dispose() {
    assert(_isStopped);
    if (!_isDisposed) {
      _eventSub?.cancel();
      _isDisposed = true;
    }
  }
}

final class NsdMdnsProvider implements IMdnsProvider {
  @override
  Future<IMdnsDiscovery> startDiscovery(String serviceType, EventBus eventBus, {CancellationToken? cancelToken}) async {
    BonsoirDiscovery discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
    await discovery.initialize().asCancellable(cancelToken);
    return NsdMdnsDiscovery(discovery, serviceType, eventBus);
  }
}
