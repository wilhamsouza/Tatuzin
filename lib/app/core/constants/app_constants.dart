abstract final class AppConstants {
  static const appName = 'Tatuzin';
  static const appSlogan = 'parceiro do pequeno negocio';
  static const brandLine =
      'ERP/PDV offline-first para o pequeno negocio brasileiro';
  static const appVersion = String.fromEnvironment(
    'TATUZIN_APP_VERSION',
    defaultValue: '1.0.0',
  );
  static const databaseName = 'simples_erp_pdv.db';
  static const databaseVersion = 38;
  static const defaultLocalOperatorName = 'Operador local';
  static const defaultLocalCompanyName = 'Empresa local';
}
