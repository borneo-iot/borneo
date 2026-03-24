import 'package:borneo_kernel/drivers/borneo/device_api.dart';
import 'package:pub_semver/pub_semver.dart';

import 'package:borneo_kernel_abstractions/models/driver_descriptor.dart';
import 'package:borneo_kernel_abstractions/models/heartbeat_method.dart';

import 'coap_driver.dart';

const kLyfiDriverID = "borneo.lyfi";
const kLyfiDriverName = "Borneo LyFi Aquarium LED";
final kLyfiFWVersionConstraint = VersionConstraint.parse('>=0.7.0');
const kLyfiMinInterfaceVersion = 1;

final DriverDescriptor borneoLyfiDriverDescriptor = DriverDescriptor(
  id: kLyfiDriverID,
  name: kLyfiDriverName,
  heartbeatMethod: HeartbeatMethod.push,
  discoveryMethod: MdnsDeviceDiscoveryMethod(kBorneoDeviceMdnsServiceType),
  matches: BorneoLyfiCoapDriver.matches,
  factory: BorneoLyfiCoapDriver.new,
);
