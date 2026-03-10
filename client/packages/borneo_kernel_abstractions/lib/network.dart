import 'dart:async';

abstract class INetworkMonitor {
  Stream<NetworkSnapshot> get onNetworkChanged;

  Future<NetworkSnapshot> getCurrentSnapshot();
}

final class NetworkSnapshot {
  final bool localDiscoveryAvailable;
  final String? fingerprint;

  const NetworkSnapshot({required this.localDiscoveryAvailable, this.fingerprint});

  static const unavailable = NetworkSnapshot(localDiscoveryAvailable: false, fingerprint: 'unavailable');

  @override
  bool operator ==(Object other) {
    return other is NetworkSnapshot &&
        other.localDiscoveryAvailable == localDiscoveryAvailable &&
        other.fingerprint == fingerprint;
  }

  @override
  int get hashCode => Object.hash(localDiscoveryAvailable, fingerprint);
}

final class NullNetworkMonitor implements INetworkMonitor {
  const NullNetworkMonitor();

  @override
  Stream<NetworkSnapshot> get onNetworkChanged => const Stream.empty();

  @override
  Future<NetworkSnapshot> getCurrentSnapshot() async => NetworkSnapshot.unavailable;
}
