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
        return 'Base local preservada, com leitura remota preparada para API futura.';
      case AppDataMode.futureHybridReady:
        return 'Arquitetura pronta para local-first com sincronizacao futura.';
    }
  }

  bool get keepsLocalAsSourceOfTruth => true;

  bool get allowsRemoteRead => this != AppDataMode.localOnly;

  bool get allowsRemoteWrite => this == AppDataMode.futureHybridReady;
}
