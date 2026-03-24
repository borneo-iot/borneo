import 'package:pub_semver/pub_semver.dart';

import 'package:borneo_kernel_abstractions/models/driver_descriptor.dart';

class SupportedDeviceDescriptor {
  final DriverDescriptor driverDescriptor;
  final String name;
  final Uri address;
  final String fingerprint;
  final String compatible;
  final String model;
  final String? vendor;
  final String? serno;
  final Version fwVer;
  final bool? isCE;
  final int interfaceVer;

  const SupportedDeviceDescriptor({
    required this.driverDescriptor,
    required this.name,
    required this.address,
    required this.fingerprint,
    required this.compatible,
    required this.model,
    required this.fwVer,
    required this.isCE,
    required this.interfaceVer,
    this.vendor,
    this.serno,
  });
}
