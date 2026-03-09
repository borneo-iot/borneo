import 'package:pub_semver/pub_semver.dart';

extension VersionTryParsing on Version {
  static Version? tryParse(String versionString) {
    try {
      return Version.parse(versionString);
    } on FormatException {
      return null;
    }
  }
}
