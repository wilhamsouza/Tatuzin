enum TipoEntrega { delivery, retirada, mesa }

extension TipoEntregaX on TipoEntrega {
  String get label {
    switch (this) {
      case TipoEntrega.delivery:
        return 'Delivery';
      case TipoEntrega.retirada:
        return 'Retirada';
      case TipoEntrega.mesa:
        return 'Mesa';
    }
  }

  String get emoji {
    switch (this) {
      case TipoEntrega.delivery:
        return '🛵';
      case TipoEntrega.retirada:
        return '🏪';
      case TipoEntrega.mesa:
        return '🪑';
    }
  }
}
