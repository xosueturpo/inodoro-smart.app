/// Endpoints HTTP del ESP32 inodoro_smart.
class ApiConstants {
  ApiConstants._();

  static const mdnsHostname = 'inodoro_smart';
  static const mdnsServiceType = '_http._tcp.local';
  static const httpPort = 80;
  static const pingPath = '/ping';
  static const cmdPath = '/cmd';
  static const evtPath = '/evt';

  static String baseUrl(String host) => 'http://$host:$httpPort';
  static String mdnsHost() => '$mdnsHostname.local';
}
