# Painel do proprietário — Fase 2

## Entrega e escopo

Implementação incremental no `owner_web`, preservando autenticação, rotas, proteção PRO, APIs e operações existentes. O `admin_web`, o aplicativo mobile da Fase 1, cálculos financeiros e sincronização operacional não foram alterados nesta fase.

A referência `01_painel_proprietario.png` orientou a hierarquia: navegação lateral, empresa e identidade da conta no topo, métricas, gráfico e equipe em colunas, atalhos, contas a receber e atividades. Não foram copiados nomes, fotos, valores, notificações, percentuais ou séries da imagem.

Não foi encontrado `AGENTS.md` no repositório consultado. O Graphify confirmou dependências de `owner_dashboard_page.dart`, incluindo providers, modelos, componentes, rotas e testes; o índice aponta para o commit base `726ebb20`, por isso cada dependência foi conferida no código local atual.

## Interface implementada

- Identidade roxa e tipografia Noto Sans reutilizada dos assets do aplicativo, com cores e contraste para temas claro/escuro.
- Navegação lateral no desktop; abaixo de 1100 px ou com texto ampliado, drawer rolável que mantém todos os destinos. A navegação fecha o drawer antes de trocar de rota. Acesso a Caixa usa o relatório existente `/reports/cash`.
- Empresa, nome e inicial do usuário autenticado e plano no cabeçalho; saída continua ligada ao controlador real de autenticação. Nenhuma foto de perfil foi inventada.
- Métricas com tamanho natural e grade adaptável. Gráfico, equipe e demais painéis ficam em colunas quando há espaço e empilhados no mobile. Cabeçalhos e ações também empilham com largura reduzida ou texto ampliado.
- Gráfico com pontos e segmentos da série real de vendas; datas e valores detalhados são acessíveis pela expansão “Ver valores por dia”. Seleção de 7/30 dias independente dos filtros das telas de relatórios.
- Resumo da equipe com nomes, cargos, situação cadastral e situação real de acesso. Cadastro ativo não é apresentado como acesso liberado quando há senha temporária pendente.
- Lista de funcionários com busca por nome/e-mail e menu por pessoa. Cadastro, edição, cargos/permissões, ativação/desativação, senha temporária e comissão continuam nos formulários e serviços existentes. Mutações exibem andamento e bloqueiam submissões concorrentes. Desativação/reativação e troca de senha exigem as confirmações existentes.
- Estados de carregamento, atualização, vazio, consulta parcial indisponível, erro com nova tentativa e restrição de acesso. Comissão indisponível não é apresentada como zero.

## Dados e ações conectados

| Bloco/ação | Fonte/destino real | Limite de interpretação |
| --- | --- | --- |
| Vendas hoje, faturamento mensal e ticket | `GET /owner/dashboard/business` | Período e timezone retornados pela API, atualmente UTC. Vendas não significam recebimentos nem lucro. |
| Estoque baixo/zerado e alertas | Mesmo dashboard | Dados sincronizados da empresa, sem comparação percentual inventada. |
| Gráfico e últimas atividades | `GET /owner/reports/sales-summary` | A série é de vendas. Atividades exibem vendas reais do período, sem simular eventos de estoque, equipe ou permissões. |
| Contas a receber | `GET /owner/financial/receivables`, `status=open`, até cinco contas | Valor em aberto, vencimento quando disponível e atraso. “Ver todas” leva a `/finance`. |
| Equipe | `GET /owner/employees` | Até quatro pessoas no resumo; lista completa e ações em `/employees`. |
| Criar/editar funcionário | `POST /owner/employees`, `PATCH /owner/employees/:id` | Validações reais de nome/e-mail, cargo, permissões, empresa e licença. Não representa envio de convite por e-mail. |
| Ativar/desativar | `POST /owner/employees/:id/enable` e `/disable` | Confirmação no cliente e autorização no servidor. |
| Redefinir acesso | `POST /owner/employees/:id/access/temporary-password` | Confirmação; senha exibida apenas após a operação, com o fluxo existente de cópia. |
| Comissões | API existente `/owner/commissions` e atualização de configuração | Estimativa e regras existentes, sem alteração do cálculo. |
| Atalhos | `/sales`, `/reports/cash`, `/products`, `/employees` | Consulta/gestão existente. Não foram adicionados botões de Nova venda ou Abrir caixa que o owner_web não oferece. |

O contrato atual não fornece lucro consolidado nem um saldo único de caixa da empresa. Esses valores não foram calculados por aproximação nem apresentados como zero. Não há uma busca global de registros, inbox ou central de notificações simulada.

## Preservação das permissões e compatibilidade

Foi corrigido um problema concreto do contrato antigo: `listEmployees` enviava apenas as oito primeiras permissões e a lista efetiva vazia de funcionários desativados. O formulário poderia gravar essa lista parcial e remover acessos configurados.

A API agora retorna a lista **completa de permissões configuradas**, inclusive de funcionários desativados, e o indicador aditivo `permissionsAreComplete: true`. A autenticação continua calculando as permissões efetivas conforme o status real; um funcionário desativado não recebe acesso por causa desse campo de edição.

O cliente aceita listas antigas completas de funcionários ativos e impede salvar listas truncadas ou listas de desativados sem confirmação de completude. Isso permite publicar o frontend sem gravar acessos destrutivos contra um backend antigo. Para liberar toda a edição, publicar primeiro o backend compatível deste código. Não há migração de banco ou mudança de schema.

Os endpoints continuam protegidos por contexto autenticado, licença `ownerWebPanel`, papel OWNER/ADMIN e permissões específicas (`employees.manage` para mutações). O flag `canManage` real determina os controles da interface, enquanto o backend valida a operação novamente. As consultas passam a depender também da identidade empresa/usuário/papel para invalidar resultados ao trocar de sessão, evitando reutilizar dados de outro tenant.

## Arquivos desta fase

- `owner_web/lib/src/theme/owner_theme.dart`, `owner_web/pubspec.yaml`, `owner_web/assets/fonts/`: identidade e fonte local compartilhada com o app.
- `owner_web/lib/src/core/widgets/owner_shell_scaffold.dart`: cabeçalho, perfil, caixa e navegação rolável/adaptável.
- `owner_web/lib/src/core/widgets/owner_management_widgets.dart`, `owner_responsive_layout.dart`, `owner_async_view.dart`: cabeçalhos, métricas, grade, colunas, linhas e estados comuns.
- `owner_web/lib/src/core/widgets/owner_sales_chart.dart`: série real com detalhamento acessível por dia.
- `owner_web/lib/src/core/auth/owner_providers.dart`: consultas independentes do dashboard, escopo de sessão e estados de busca/mutação.
- `owner_web/lib/src/core/models/owner_models.dart`: indicação de completude da lista de permissões.
- `owner_web/lib/src/features/dashboard/presentation/owner_dashboard_page.dart`: painel com dados reais.
- `owner_web/lib/src/features/employees/presentation/owner_employees_page.dart`: lista responsiva, busca e operações preservadas/protegidas.
- `owner_web/test/owner_web_test.dart`: regressões, estados, tenant, compatibilidade de permissões e capturas.
- `backend/src/modules/owner/owner.service.ts` e `owner.routes.test.ts`: contrato completo das permissões e teste HTTP de preservação ao editar um funcionário desativado.

## Verificação

- `flutter analyze --no-pub` no `owner_web`.
- Suíte Flutter do painel: 38 testes, incluindo renderização em 1440×1000, 1280×800, 360×800 e 390×844; claro/escuro e texto até 200%, drawer, dashboard, funcionários, recuperação de erro e preservação dos filtros de relatórios.
- 61 testes HTTP de owner e funcionários com PostgreSQL descartável separado, migrado com as migrations existentes: plano, papel, tenant, permissões, cadastro, edição, bloqueio, ativação e senha temporária. Inclui teste novo com mais de oito permissões, desativação, edição e reativação sem perda.
- TypeScript verificado com `npx tsc -p tsconfig.json --noEmit` e compilação emitida em `/tmp/tatuzin-owner-phase2-dist`.
- Build Flutter web release com recursos locais: `flutter build web --release --no-web-resources-cdn`.
- Pacote do site compilado: `owner_web/build/phase2-owner/tatuzin-owner-web-phase2.zip`, acompanhado de checksum `.sha256`. Contém somente o build público; não inclui ambientes, tokens, banco ou código privado de configuração.
- Capturas de widgets reais em `owner_web/build/phase2-owner/`, com fixtures exclusivamente de teste. Seus nomes/valores não representam empresas ou pessoas reais do ambiente. O registro `evidence.json` acompanha as capturas.

Limitação concreta do host: `npm run build` não consegue sobrescrever arquivos antigos de `backend/dist` por `EACCES`; a compilação foi validada em diretório temporário gravável sem mudar permissões nem substituir o backend em execução. O MCP Chrome não encontra `/opt/google/chrome/chrome`. Na publicação foi instalado Chromium e a tela pública de acesso foi verificada por CDP em HTTPS, em desktop e mobile, sem erros de JavaScript ou rede. Os fluxos autenticados continuam pendentes de aceitação com a conta real; foram testados por integrações HTTP isoladas. As prévias com dados de teste são renderizações Flutter; as imagens `live-login-*.png` são capturas do navegador real. O build padrão JavaScript é o alvo validado; não foi usada uma compilação WASM experimental.

## Visualizar e repetir os fluxos

Na raiz do repositório, após compilar o painel:

```sh
cd owner_web
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8787 \
  --dart-define=TATUZIN_OWNER_API_URL=http://127.0.0.1:4000/api
```

Ou servir o artefato release, a partir da raiz:

```sh
python3 -m http.server 8787 --bind 127.0.0.1 --directory owner_web/build/web
```

O artefato release gerado usa o endpoint oficial padrão `https://api.tatuzin.com.br/api`. Para usar outro backend, definir `TATUZIN_OWNER_API_URL` no build. Para um backend local, configurar as origens CORS do ambiente de desenvolvimento e usar os endpoints reais; não desabilitar autenticação. Em host remoto, encaminhar a porta 8787 para o computador. Para abrir no celular, usar o encaminhamento/host de testes acessível com HTTPS; `127.0.0.1` do celular não aponta para o servidor.

1. Entrar com uma empresa PRO e usuário autorizado. FREE/BASIC e usuários não autorizados devem continuar bloqueados.
2. Abrir `/dashboard` em desktop; conferir os números com Vendas, Financeiro e Produtos. Alterar somente o período do gráfico e conferir que os filtros das outras páginas continuam preservados.
3. Abrir “Ver valores por dia”, “Ver todas”, “Ver todos” e os atalhos. Confirmar que Caixa leva a `/reports/cash`, sem iniciar uma operação de PDV inexistente no web.
4. Em `/employees`, buscar uma pessoa e abrir seu menu. Cadastrar/editar, testar validações, confirmar/cancelar desativação e reativação e redefinir acesso. Verificar que permissões não exibidas no resumo continuam selecionadas e preservadas no formulário.
5. Repetir com ADMIN sem `employees.manage`: consulta conforme permissões, sem ações de alteração. Requisições diretas sem autorização devem continuar retornando 403.
6. Reduzir para 360–390 px, ampliar texto a 200% e alternar tema. Abrir o drawer e alcançar os destinos finais por rolagem.
7. Simular falha/rede lenta no navegador: carregamento e retry devem aparecer, sem zeros fictícios ou abandono de sessão. Sair e entrar com outra empresa; não devem reaparecer dados anteriores.

## Pendências

Backend compatível e painel publicados. Continua pendente somente a aceitação dos fluxos autenticados com a conta real em desktop/mobile. O APK da Fase 1 não foi alterado por esta publicação.


## Publicação concluída — 14/11/2026

- Endereço: https://painel.tatuzin.com.br
- Release ativa: `owner-phase2-20261114-r2`.
- Backend: `tatuzin-backend:owner-phase2-20261114`, imagem `sha256:7ceb3e6ddd98aed02236bf1d45fd3a3349a5cc6637874b27b6ec0740055c1d15`.
- Saúde e readiness da API confirmadas, incluindo banco e tarefas internas. Contrato `permissionsAreComplete` presente na imagem ativa. Endpoints de owner continuam retornando 401 sem autenticação; CORS aceita a origem correta do painel.
- Nenhuma migration nova nesta fase; mantidas as 47 migrations existentes e os dados do ambiente.
- 14 verificações HTTP de rotas, recursos e CORS; hashes dos recursos versionados conferidos contra o build local.
- Chromium real carregou `/login` por HTTPS em 1440×1000 e 390×844, sem exceções JavaScript, falhas de rede ou respostas HTTP de erro. Nenhuma credencial foi solicitada ou gerada para essa checagem.
- `owner_web/web/index.html` agora permite zoom e inclui descrição atualizada e favicon da marca; `owner_web/web/favicon.png` reutiliza o ícone existente do projeto.

O site usa `/var/www/tatuzin-owner-current` como link para a release ativa em `/var/www/tatuzin-owner-releases/`. HTML e entradas sem versão usam `no-store`; bootstrap, JavaScript, fonts e CanvasKit publicados usam URLs sob `/_releases/<release>/`. O carregador recebe `entrypointBaseUrl`, `assetBase` e `canvasKitBaseUrl` versionados, mantendo o base href `/` e as rotas e sessões no mesmo domínio. Isso evita misturar recursos novos com arquivos que o Nginx anterior armazenava por 30 dias.

A configuração publicada está registrada em `backend/observability/owner-web.nginx.conf`. A imagem desejada também foi fixada na configuração privada `.env.production` para futuras execuções do Compose; segredos não foram alterados nem publicados.

Backups privados do banco, container, site e Nginx estão em `.release-backups/owner-phase2-20261114/`, fora do diretório público e ignorados pelo Git. A versão anterior do site continua em `/var/www/painel.tatuzin.com.br`; a imagem anterior foi preservada como `tatuzin-backend:rollback-owner-phase2-20261114`. Uma reversão de código não requer restaurar o banco nem descartar operações posteriores.

Evidências adicionais: `owner_web/build/phase2-owner/deployed-http-checks.json`, `live-browser-checks.json`, `live-login-1440x1000.png` e `live-login-390x844.png`.


## Correção do dashboard — release r3

Corrigido o erro “Dados inválidos enviados para a API” em Resumo de vendas e Últimas atividades. Ambos usam `ownerDashboardSalesProvider`, que ligava incorretamente `limit` ao número de dias. O período de 30 dias enviava `limit=30`, acima do máximo 25 do schema; a API rejeitava a consulta com HTTP 422.

A consulta agora usa as datas para escolher o período, `pageSize=5` para as últimas vendas e o limite padrão válido. Isso não limita a série a dez dias: o backend monta a série a partir do intervalo de datas. A API, suas validações e as regras financeiras permaneceram inalteradas.

- Análise Flutter sem problemas; 39 testes do owner_web passaram.
- Teste novo captura as requisições HTTP efetivamente serializadas pelo provider nos períodos de 7 e 30 dias.
- Os mesmos parâmetros capturados foram aceitos pelo schema compilado do backend publicado; a requisição antiga foi reproduzida e rejeitada pelo campo `limit`.
- 62 integrações HTTP de owner/funcionários passaram em PostgreSQL descartável. O teste novo consulta ambos os períodos com autenticação e confirma que um limite inválido continua rejeitado com HTTP 422.
- Painel publicado em `owner-phase2-20261114-r3`, com JavaScript novo verificado por hash no endereço HTTPS. Release r2 preservada para reversão.
- Não houve atualização do backend, migration, alteração de dados compartilhados ou necessidade de gerar outro APK para esta correção web.

Após a publicação, recarregar o painel para que a aba aberta passe a usar o novo JavaScript. A conferência com os dados da conta real permanece uma aceitação do usuário; as verificações automatizadas autenticadas foram feitas em banco isolado.

## Correção de acesso dos funcionários — 14/11/2026, r4

O teste com `ownerRouterProvider` e `OwnerWebApp` reais reproduziu a tela branca: o botão de confirmação usava o contexto da página dentro do `ShellRoute`, enquanto o diálogo estava no navegador raiz. O GoRouter acusava `You have popped the last page off of the stack`. As confirmações de senha e ativação/desativação agora fecham pelo contexto do próprio diálogo. O diálogo de credenciais também usa esse contexto e tem conteúdo limitado e rolável.

No cadastro de um funcionário **ativo**, a opção **Gerar acesso ao app ao salvar**, inicialmente marcada, cria o cadastro e chama a API existente de senha temporária para o ID retornado. O painel exibe e-mail/login, senha gerada, validade e orientação de troca obrigatória no primeiro login. A cópia informa o resultado e mantém a janela aberta para conferência. A senha não é salva pelo painel nem registrada em logs. Não é um envio de e-mail ou convite automático.

Também há a opção **Usar permissões padrão do cargo**, inicialmente marcada no cadastro: o cliente omite `permissions`, deixando o backend aplicar os padrões existentes. É possível desmarcar para personalizar. A edição mantém as permissões configuradas e a validação de completude já existente. Cadastros convidados/desativados não geram acesso automaticamente. As autorizações, tenant, limites, bloqueios e políticas de senha do servidor permanecem como estavam.

Se o cadastro for concluído mas a geração de acesso falhar, a lista é atualizada e uma mensagem distingue as duas operações: o funcionário já foi cadastrado e deve-se tentar **Gerar senha temporaria** pelo menu, evitando cadastrar outra pessoa por engano. O envio para gerar acesso e a apresentação das credenciais conferem o escopo da sessão após a resposta.

Validação desta correção:

- 48 testes Flutter aprovados: nove regressões novas com a navegação real (gerar/fechar, cancelar, copiar, erro da API, cadastro com acesso, sem acesso, falha parcial, permissões personalizadas e status desativado). O cadastro foi exercitado em 390×844 com texto a 150%; as verificações responsivas existentes cobrem texto até 200%.
- `flutter analyze --no-pub`: sem problemas.
- 62 testes HTTP de owner/funcionários aprovados contra PostgreSQL descartável, incluindo troca inicial obrigatória, expiração, redefinição, isolamento de empresa e bloqueios de acesso. O banco de testes foi removido depois da execução.
- Build Flutter web release aprovado; sem mudança de backend ou banco nesta correção.
- Publicado em `https://painel.tatuzin.com.br`, release `owner-phase2-20261114-r4`, por troca atômica do link do site, preservando r3. Entradas e rotas públicas verificados por HTTPS; checksum público do JavaScript igual ao artefato local: `1263298af747c7a80688ddfb630865c350dfd2149ed70379269905ecdde009b1`.
- Bootstrap, JavaScript, assets e CanvasKit usam URLs da nova release para evitar reutilização do cache da versão anterior. Não é necessário atualizar o APK para esta correção do owner_web.

Roteiro: atualizar o painel no navegador, abrir **Funcionários → Novo funcionario**, preencher nome/e-mail e cargo, manter status Ativo e **Gerar acesso ao app ao salvar**, salvar e copiar as credenciais. No Android, entrar com esse e-mail e senha temporária e concluir a troca inicial. Para um funcionário existente, usar **três pontos → Gerar senha temporaria → Gerar senha → Copiar dados → Fechar**; a lista deve continuar visível. A repetição autenticada pelo usuário no navegador/aparelho continua necessária; a checagem pública em Chromium usa a tela de login, enquanto as operações autenticadas foram testadas com fixtures e banco descartável.

Arquivos da correção: `owner_web/lib/src/features/employees/presentation/owner_employees_page.dart`, `owner_web/test/owner_web_test.dart` e este documento. Evidências locais em `owner_web/build/phase2-owner/employee-access-*.log` e `employee-access-release.json`.

Checagem da release r4 em Chromium via HTTPS: login carregado em desktop 1440×1000 e mobile 390×844, campos E-mail/Senha presentes, nenhuma requisição falha, resposta HTTP de erro ou exceção JavaScript. Evidência em `owner_web/build/phase2-owner/employee-access-browser.log`; capturas públicas de login `live-login-*.png`.
