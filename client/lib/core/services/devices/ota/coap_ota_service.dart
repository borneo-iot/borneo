import 'dart:convert';
import 'package:borneo_app/core/services/devices/ota/ota_service.dart';
import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:http/http.dart' as http;
import 'package:libcompress/libcompress.dart';
import 'package:logger/logger.dart';
import 'package:pub_semver/pub_semver.dart';

const String _kManifestUrl = 'https://flasher.borneoiot.com/firmware/manifests.json';
const String _kFirmwareBaseUrl = 'https://flasher.borneoiot.com/firmware/';

final class CoapOtaService implements IOtaService {
  final Logger? _logger;
  final GettextLocalizations gt;

  CoapOtaService({required this.gt, Logger? logger}) : _logger = logger;

  /// Fetches the manifest JSON and returns the entry whose `product_id` and
  /// `compatible` both match the given values. Returns `null` if not found.
  Future<Map<String, dynamic>?> _fetchMatchingManifestEntry(String productId, String compatible) async {
    final response = await http.get(Uri.parse(_kManifestUrl));
    if (response.statusCode != 200) {
      final msg = gt.translate(
        'Failed to fetch firmware manifest: HTTP code `{code}`',
        nArgs: {'code': response.statusCode},
      );
      _logger?.e(msg);
      throw StateError(msg);
    }
    final List<dynamic> manifest = jsonDecode(response.body) as List<dynamic>;
    for (final item in manifest) {
      final entry = item as Map<String, dynamic>;
      if (entry['product_id'] == productId && entry['compatible'] == compatible) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<OtaUpgradeInfo> checkNewVersion(BoundDevice bound, {CancellationToken? cancelToken}) async {
    final api = bound.api<IBorneoDeviceApi>();
    final localDeviceInfo = await api.getGeneralDeviceInfo(bound.device, cancelToken: cancelToken);
    final localVer = localDeviceInfo.fwVer;
    final localProductId = localDeviceInfo.pid;
    final localCompatible = localDeviceInfo.compatible;

    _logger?.d('Checking new version: pid=$localProductId compatible=$localCompatible local=$localVer');

    final entry = await _fetchMatchingManifestEntry(localProductId, localCompatible);
    if (entry == null) {
      final msg = gt.translate('No firmware entry found for product ID `{pid}`', nArgs: {'pid': localProductId});
      _logger?.w(msg);
      throw StateError(msg);
    }

    final remoteVer = Version.parse(entry['version'] as String);
    final remoteTime = DateTime.fromMillisecondsSinceEpoch(entry['timestamp'] as int);
    final otaFilename = entry['ota_filename'] as String;
    final otaSha256 = entry['ota_sha256'] as String;

    _logger?.i('Remote version: $remoteVer (local: $localVer), canUpgrade=${remoteVer > localVer}');

    return OtaUpgradeInfo(
      remoteVersion: remoteVer,
      localVersion: localVer,
      canUpgrade: remoteVer > localVer,
      remoteTime: remoteTime,
      otaFilename: otaFilename,
      otaSha256: otaSha256,
    );
  }

  @override
  Future<void> upgrade(BoundDevice bound, {CancellationToken? cancelToken, bool force = false}) async {
    final api = bound.api<IBorneoDeviceApi>();

    // Step 1: Check version and obtain manifest entry info
    final upgradeInfo = await checkNewVersion(bound, cancelToken: cancelToken);
    if (!force && !upgradeInfo.canUpgrade) {
      _logger?.i('No upgrade available, skipping.');
      return;
    }
    if (force && !upgradeInfo.canUpgrade) {
      _logger?.w('Force-upgrading even though firmware is already up to date.');
    }

    // Step 2: Download the OTA firmware (.bin.gz)
    final otaUrl = '$_kFirmwareBaseUrl${upgradeInfo.otaFilename}';
    _logger?.i('Downloading firmware: $otaUrl');
    final httpResponse = await http.get(Uri.parse(otaUrl));
    if (httpResponse.statusCode != 200) {
      final msg = 'Failed to download firmware: HTTP ${httpResponse.statusCode}';
      _logger?.e(msg);
      throw StateError(msg);
    }
    final compressedData = httpResponse.bodyBytes;

    // Step 3: Verify SHA256 of compressed file
    final digest = sha256.convert(compressedData);
    if (digest.toString() != upgradeInfo.otaSha256) {
      final msg = gt.translate('Firmware hash mismatch');
      _logger?.e(msg);
      throw StateError(msg);
    }

    // Step 4: Decompress gzip in memory
    final codec = CodecFactory.codec(CodecType.gzip);
    final firmwareBuffer = Uint8List.fromList(codec.decompress(compressedData));
    _logger?.i('Firmware decompressed: ${firmwareBuffer.length} bytes, starting OTA upload');

    // Step 5: Upload firmware via CoAP OTA engage
    await api.otaCoapEngage(bound.device, firmwareBuffer, cancelToken: cancelToken);
    _logger?.i('OTA firmware upload completed successfully');
  }
}
