import 'package:borneo_app/shared/models/base_entity.dart';
import 'package:borneo_kernel_abstractions/device.dart';
import 'package:borneo_kernel_abstractions/models/driver_data.dart';

class DeviceEntity extends Device with BaseEntity {
  static const String kNameFieldName = "name";
  static const String kSceneIDFieldName = "sceneID";
  static const String kGroupIDFieldName = "groupID";
  static const String kFngerprintFieldName = "fingerprint";
  static const String kAddressFieldName = "address";
  static const String kIsDemoFieldName = "isDemo";

  DriverData? _driverData;

  final String sceneID;
  final String? groupID;
  final String driverID;
  final String compatible;
  final String name;
  final String model;
  final bool isDemo;

  // Non-persistent field for error messages
  String? lastErrorMessage;

  DeviceEntity({
    required super.id,
    required super.address,
    required super.fingerprint,
    required this.sceneID,
    required this.driverID,
    required this.compatible,
    required this.name,
    required this.model,
    this.groupID,
    this.isDemo = false,
  });

  factory DeviceEntity.fromMap(String id, Map<String, dynamic> map) {
    return DeviceEntity(
      id: id,
      sceneID: map[kSceneIDFieldName],
      groupID: map[kGroupIDFieldName],
      address: Uri.parse(map[kAddressFieldName]),
      compatible: map['compatible'],
      driverID: map['driverID'],
      fingerprint: map[kFngerprintFieldName],
      name: map[kNameFieldName],
      model: map['model'],
      isDemo: map[kIsDemoFieldName] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': super.id,
      kSceneIDFieldName: sceneID,
      kGroupIDFieldName: groupID,
      kAddressFieldName: address.toString(),
      'driverID': driverID,
      'compatible': compatible,
      kFngerprintFieldName: fingerprint,
      kNameFieldName: name,
      'model': model,
      kIsDemoFieldName: isDemo,
    };
  }

  @override
  DriverData get driverData {
    if (_driverData == null) {
      throw StateError('Driver data is not set for device: $id');
    }
    return _driverData!;
  }

  @override
  void setDriverData(DriverData driverData) {
    if (identical(_driverData, driverData)) {
      return;
    }
    _driverData?.dispose();
    _driverData = driverData;
  }

  @override
  String toString() => 'Device(id: `$id`, name: `$name`, model: `$model`, uri: `$address`)';
}
