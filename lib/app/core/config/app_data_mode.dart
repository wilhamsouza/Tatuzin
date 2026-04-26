enum AppDataMode { localOnly, futureRemoteReady, futureHybridReady }

extension AppDataModeX on AppDataMode {
  String get label {
    switch (this) {
      case AppDataMode.localOnly:
        return 'Somente local';
      case AppDataMode.futureRemoteReady:
        return 'Remoto pronto';
      case AppDataMode.futureHybridReady:
        return 'Hibrido pronto';
    }
  }

  String get description {
    switch (this) {
      case AppDataMode.localOnly:
        return 'SQLite local permanece como fonte unica de dados.';
      case AppDataMode.futureRemoteReady:
        return 'ERP e CRM priorizam a API; PDV preserva a base local offline.';
      case AppDataMode.futureHybridReady:
        return 'PDV local-first com sync em background; ERP e CRM server-first.';
    }
  }

  bool get keepsLocalAsSourceOfTruth => this == AppDataMode.localOnly;

  bool get allowsRemoteRead => this != AppDataMode.localOnly;

  bool get allowsRemoteWrite => this == AppDataMode.futureHybridReady;
}
