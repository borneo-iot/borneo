import 'package:borneo_app/core/services/devices/ota/coap_ota_service.dart';
import 'package:borneo_app/core/services/devices/ota/ota_service.dart';
import 'package:borneo_kernel_abstractions/kernel.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:logger/logger.dart';

final class OtaProvider {
  static const String kCoapType = 'coap';
  final IKernel kernel;

  const OtaProvider({required this.kernel});

  IOtaService create({String type = kCoapType, required GettextLocalizations gt, Logger? logger}) => switch (type) {
    kCoapType => CoapOtaService(kernel: kernel, logger: logger, gt: gt),
    _ => throw Error(),
  };
}
