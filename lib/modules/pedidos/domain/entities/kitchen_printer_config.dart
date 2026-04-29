enum KitchenPrinterConnectionType { network, bluetooth }

extension KitchenPrinterConnectionTypeX on KitchenPrinterConnectionType {
  String get storageValue {
    switch (this) {
      case KitchenPrinterConnectionType.network:
        return 'network';
      case KitchenPrinterConnectionType.bluetooth:
        return 'bluetooth';
    }
  }

  static KitchenPrinterConnectionType fromStorage(String? value) {
    switch (value) {
      case 'bluetooth':
        return KitchenPrinterConnectionType.bluetooth;
      default:
        return KitchenPrinterConnectionType.network;
    }
  }
}

class KitchenPrinterConfig {
  const KitchenPrinterConfig({
    required this.displayName,
    required this.connectionType,
    this.host,
    this.port = 9100,
    this.bluetoothAddress,
    this.charactersPerLine = 32,
    this.autoCut = true,
  });

  final String displayName;
  final KitchenPrinterConnectionType connectionType;
  final String? host;
  final int port;
  final String? bluetoothAddress;
  final int charactersPerLine;
  final bool autoCut;

  String get targetLabel {
    switch (connectionType) {
      case KitchenPrinterConnectionType.network:
        final resolvedHost = host?.trim() ?? '';
        return resolvedHost.isEmpty
            ? 'IP nao configurado'
            : '$resolvedHost:$port';
      case KitchenPrinterConnectionType.bluetooth:
        return bluetoothAddress?.trim().isNotEmpty == true
            ? bluetoothAddress!.trim()
            : 'Bluetooth nao configurado';
    }
  }

  KitchenPrinterConfig copyWith({
    String? displayName,
    KitchenPrinterConnectionType? connectionType,
    String? host,
    int? port,
    String? bluetoothAddress,
    int? charactersPerLine,
    bool? autoCut,
  }) {
    return KitchenPrinterConfig(
      displayName: displayName ?? this.displayName,
      connectionType: connectionType ?? this.connectionType,
      host: host ?? this.host,
      port: port ?? this.port,
      bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
      charactersPerLine: charactersPerLine ?? this.charactersPerLine,
      autoCut: autoCut ?? this.autoCut,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'displayName': displayName,
      'connectionType': connectionType.storageValue,
      'host': host,
      'port': port,
      'bluetoothAddress': bluetoothAddress,
      'charactersPerLine': charactersPerLine,
      'autoCut': autoCut,
    };
  }

  factory KitchenPrinterConfig.fromJson(Map<String, Object?> json) {
    return KitchenPrinterConfig(
      displayName: (json['displayName'] as String?)?.trim().isNotEmpty == true
          ? (json['displayName'] as String).trim()
          : 'Impressora de pedidos',
      connectionType: KitchenPrinterConnectionTypeX.fromStorage(
        json['connectionType'] as String?,
      ),
      host: json['host'] as String?,
      port: json['port'] is int ? json['port'] as int : 9100,
      bluetoothAddress: json['bluetoothAddress'] as String?,
      charactersPerLine: json['charactersPerLine'] is int
          ? json['charactersPerLine'] as int
          : 32,
      autoCut: json['autoCut'] is bool ? json['autoCut'] as bool : true,
    );
  }
}
