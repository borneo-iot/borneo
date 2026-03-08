import 'dart:io';

typedef InternetAddressLookup = Future<List<InternetAddress>> Function(String host, {InternetAddressType type});

Future<List<InternetAddress>> _defaultLookup(String host, {InternetAddressType type = InternetAddressType.any}) {
  return InternetAddress.lookup(host, type: type);
}

bool _isLinkLocalIpv6(InternetAddress address) {
  if (address.type != InternetAddressType.IPv6) {
    return false;
  }
  return address.address.toLowerCase().startsWith('fe80:');
}

int _addressPreferenceScore(InternetAddress address) {
  if (address.type == InternetAddressType.IPv4) {
    return 0;
  }
  if (!_isLinkLocalIpv6(address)) {
    return 1;
  }
  return 2;
}

InternetAddress? selectPreferredInternetAddress(Iterable<InternetAddress> addresses) {
  final candidates = addresses.toList(growable: false);
  if (candidates.isEmpty) {
    return null;
  }

  candidates.sort((left, right) {
    final scoreCompare = _addressPreferenceScore(left).compareTo(_addressPreferenceScore(right));
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    return 0;
  });
  return candidates.first;
}

Future<String> resolveHostToPreferredAddress(String host, {InternetAddressLookup lookup = _defaultLookup}) async {
  final parsedAddress = InternetAddress.tryParse(host);
  if (parsedAddress != null) {
    return parsedAddress.address;
  }

  try {
    final addresses = await lookup(host, type: InternetAddressType.any);
    final selected = selectPreferredInternetAddress(addresses);
    return selected?.address ?? host;
  } on SocketException {
    return host;
  }
}

Future<Uri> resolveUriHostToPreferredAddress(Uri uri, {InternetAddressLookup lookup = _defaultLookup}) async {
  if (uri.host.isEmpty) {
    return uri;
  }

  final resolvedHost = await resolveHostToPreferredAddress(uri.host, lookup: lookup);
  if (resolvedHost == uri.host) {
    return uri;
  }

  return uri.replace(host: resolvedHost);
}
