import 'dart:io';

class NetworkUtils {
  static Future<String?> getDeviceIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          // Skip loopback addresses
          if (!address.isLoopback) {
            return address.address;
          }
        }
      }
    } catch (e) {
      print('Error getting IP address: $e');
    }
    return null;
  }

  static Future<List<String>> getAllIpAddresses() async {
    final List<String> ipAddresses = [];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            ipAddresses.add(address.address);
          }
        }
      }
    } catch (e) {
      print('Error getting IP addresses: $e');
    }

    return ipAddresses;
  }

  static bool isValidIpAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;

    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) {
        return false;
      }
    }

    return true;
  }
}