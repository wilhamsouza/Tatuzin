enum CostType { fixed, variable }

extension CostTypeX on CostType {
  String get dbValue => this == CostType.fixed ? 'fixed' : 'variable';

  String get label => this == CostType.fixed ? 'Fixo' : 'Variavel';

  String get pluralLabel => this == CostType.fixed ? 'Fixos' : 'Variaveis';

  static CostType fromDb(String value) {
    return value == 'fixed' ? CostType.fixed : CostType.variable;
  }
}
