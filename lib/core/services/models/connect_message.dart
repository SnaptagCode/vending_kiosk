/// Message to request connection to card dispenser
class ConnectMessage {
  final String port;
  final String protocol;

  ConnectMessage({required this.port, required this.protocol});
}
