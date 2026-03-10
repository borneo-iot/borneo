import 'package:borneo_kernel_abstractions/network.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

final class ConnectivityNetworkChangeMonitor implements INetworkMonitor {
  final Connectivity _connectivity;

  ConnectivityNetworkChangeMonitor({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  @override
  Stream<NetworkSnapshot> get onNetworkChanged => _connectivity.onConnectivityChanged.map(_toSnapshot);

  @override
  Future<NetworkSnapshot> getCurrentSnapshot() async => _toSnapshot(await _connectivity.checkConnectivity());

  NetworkSnapshot _toSnapshot(List<ConnectivityResult> connectivity) {
    final normalized = connectivity.toSet().toList()..sort((left, right) => left.name.compareTo(right.name));
    final hasLocalDiscovery =
        normalized.contains(ConnectivityResult.wifi) || normalized.contains(ConnectivityResult.ethernet);
    final fingerprint = normalized.map((result) => result.name).join('|');
    return NetworkSnapshot(localDiscoveryAvailable: hasLocalDiscovery, fingerprint: fingerprint);
  }
}
