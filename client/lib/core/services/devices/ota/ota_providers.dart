import 'package:borneo_app/core/services/devices/ota/coap_ota_service.dart';
import 'package:borneo_app/core/services/devices/ota/ota_service.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:logger/logger.dart';

final class OtaProvider {
  static const String kCoapType = 'coap';
  const OtaProvider();

  IOtaService create({String type = kCoapType, required GettextLocalizations gt, Logger? logger}) => switch (type) {
    kCoapType => CoapOtaService(logger: logger, gt: gt),
    _ => throw Error(),
  };
}
