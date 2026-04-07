# ERP PDV App

Um aplicativo ERP/PDV profissional para pequenos negócios, desenvolvido em Flutter com arquitetura limpa e modular.

## 🏗️ Arquitetura

O projeto segue uma arquitetura limpa e modular com separação clara de responsabilidades:

```
lib/
├── app/
│   ├── core/                 # Funcionalidades compartilhadas
│   │   ├── constants/        # Constantes da aplicação
│   │   ├── database/         # Helper do banco de dados
│   │   ├── errors/           # Exceções customizadas
│   │   ├── formatters/       # Formatação de dados
│   │   ├── models/           # Models base
│   │   ├── services/         # Serviços compartilhados
│   │   ├── theme/            # Tema da aplicação
│   │   └── widgets/          # Widgets reutilizáveis
│   ├── routes/               # Configuração de rotas
│   └── app.dart              # Widget principal
└── modules/                  # Módulos de negócio
    ├── produtos/             # Gestão de produtos
    ├── categorias/           # Gestão de categorias
    ├── clientes/             # Gestão de clientes
    ├── vendas/               # Processamento de vendas
    ├── carrinho/             # Carrinho de compras
    ├── caixa/                # Controle de caixa
    ├── fiado/                # Contas a receber
    ├── relatorios/           # Relatórios
    └── configuracoes/        # Configurações
```

## 🚀 Funcionalidades

### ✅ Implementadas
- **Arquitetura limpa e modular**
- **Banco de dados SQLite** com schema completo
- **Módulo de Produtos**: CRUD completo, busca, código de barras, controle de estoque
- **Módulo de Categorias**: Organização de produtos
- **Módulo de Clientes**: CRUD completo, controle de dívidas
- **Dashboard**: Visão geral com estatísticas
- **UI/UX profissional**: Material 3, tema consistente
- **Formatação pt-BR**: Moeda, datas, telefones
- **Validações**: Input formatters, validação de dados

### 🚧 Em desenvolvimento
- **Módulo de Vendas**: Processamento completo de vendas
- **Carrinho de Compras**: Gestão de itens, cálculos
- **Checkout**: Formas de pagamento, finalização
- **Fiado**: Contas a receber, parcelamento
- **Caixa**: Abertura/fechamento, movimentos
- **Relatórios**: Análises e estatísticas
- **Comprovantes**: PDF, compartilhamento
- **Backup/Restore**: Exportação/importação

## 📱 Telas

### 🏠 Dashboard
- Visão geral do negócio
- Ações rápidas
- Estatísticas do dia
- Alertas de estoque baixo
- Vendas recentes

### 📦 Produtos
- Listagem com busca e filtros
- Cadastro/edição completa
- Controle de estoque
- Código de barras
- Categorias
- Fotos dos produtos

### 👥 Clientes
- Cadastro completo
- Busca dinâmica
- Controle de dívidas
- Histórico de compras

### 🗂️ Categorias
- Organização de produtos
- Gestão simples

## 🛠️ Tecnologias

- **Flutter**: Framework cross-platform
- **Riverpod**: State management
- **Go Router**: Navegação
- **SQLite**: Banco de dados local
- **Material 3**: UI Design
- **Decimal**: Cálculos monetários precisos
- **Mobile Scanner**: Leitura de código de barras
- **Image Picker**: Fotos de produtos
- **PDF**: Geração de comprovantes

## 📋 Requisitos

- Flutter SDK >= 3.13.0
- Dart SDK >= 3.1.0
- Android SDK (para desenvolvimento Android)

## 🔧 Instalação

1. Clone o repositório:
```bash
git clone <repository-url>
cd erp_pdv_app
```

2. Instale as dependências:
```bash
flutter pub get
```

3. Execute o aplicativo:
```bash
flutter run
```

## 🏢 Estrutura de Módulos

Cada módulo segue a estrutura:

```
modules/nome_modulo/
├── data/
│   └── repositories/         # Implementação dos repositórios
├── domain/
│   ├── models/              # Models de domínio
│   ├── repositories/        # Interfaces dos repositórios
│   └── use_cases/          # Casos de uso
└── presentation/
    ├── providers/           # State management (Riverpod)
    └── pages/              # Telas
```

## 💾 Banco de Dados

Schema completo com:
- **Usuários**: Sistema multiusuário preparado
- **Clientes**: Cadastro completo com controle de dívidas
- **Categorias**: Organização de produtos
- **Produtos**: Cadastro completo com estoque
- **Vendas**: Processamento completo
- **Itens de Venda**: Detalhes das vendas
- **Fiado**: Contas a receber
- **Pagamentos**: Histórico de pagamentos
- **Caixa**: Sessões e movimentos
- **Configurações**: Sistema de configurações
- **Logs**: Auditoria e backups

## 🎨 UI/UX

- **Material 3**: Design moderno e consistente
- **Tema claro**: Otimizado para uso em PDV
- **Layout responsivo**: Adaptado para diferentes tamanhos
- **Navegação intuitiva**: Fluxos otimizados
- **Feedback visual**: Loading, estados, validações

## 🔮 Próximos Passos

1. Finalizar módulo de vendas
2. Implementar carrinho e checkout
3. Desenvolver módulo de caixa
4. Criar sistema de fiado
5. Gerar relatórios e analytics
6. Implementar backup/sync
7. Adicionar notificações
8. Otimizar performance

## 📝 Licença

Este projeto está licenciado sob a Licença MIT.

## 🤝 Contribuição

Contribuições são bem-vindas! Por favor:
1. Fork o projeto
2. Crie uma branch para sua feature
3. Commit suas mudanças
4. Push para a branch
5. Abra um Pull Request

---

**Desenvolvido com ❤️ para pequenos negócios**
