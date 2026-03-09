import 'package:borneo_kernel_abstractions/models/bound_device.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:pub_semver/pub_semver.dart';

final class OtaUpgradeInfo {
  final Version remoteVersion;
  final Version localVersion;
  final bool canUpgrade;
  final DateTime remoteTime;
  final String otaFilename;
  final String otaSha256;

  const OtaUpgradeInfo({
    required this.remoteVersion,
    required this.localVersion,
    required this.canUpgrade,
    required this.remoteTime,
    required this.otaFilename,
    required this.otaSha256,
  });
}

abstract class IOtaService {
  Future<OtaUpgradeInfo> checkNewVersion(BoundDevice bound, {CancellationToken? cancelToken});
  Future<void> upgrade(BoundDevice bound, {CancellationToken? cancelToken, bool force = false});
}
