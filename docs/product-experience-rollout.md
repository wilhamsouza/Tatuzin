# Evolução da experiência do Tatuzin

## Decisões aprovadas

- Moda como foco; preservar empresas que usam alimentação.
- Todos entram no Início, inclusive vendedores.
- Navegação principal: Início, Produtos, Vender (+), Atividade, Perfil.
- Ativação concluída na primeira venda real, sem transações fictícias.
- Manter FREE/BASIC/PRO e os preços e limites atuais nesta rodada.
- Owner Web continua sendo um painel de acompanhamento.

## Entregas

1. **Fundação — implementada.** Perfil, cache offline, eventos de jornada,
   ingestão deduplicada, relatório administrativo e retenção de 90 dias.
2. **Onboarding — implementado.** Slug automático com colisões tratadas;
   checklist retomável no Início; marcos por empresa reconciliados com dados reais;
   progresso local offline e trial somente em acesso posterior à primeira venda.
3. **Início — implementado.** Contagem diária independente das cinco movimentações
   recentes, remoção de métricas vazias, caixa e ações conforme permissões e alcance local explícito.
4. **Navegação — implementada.** Cinco abas com Vender destacado, rotas antigas
   preservadas, estado mantido por aba, Perfil com acessos filtrados e todos entrando no Início.
5. **Checkout — implementado.** Opções adicionais recolhidas no modo novo,
   pagamento e confirmação em destaque, bloqueio de duplo envio durante validações
   e proteção contra troca de empresa enquanto o fechamento aguarda o caixa.
6. **Planos — implementados os ajustes de comunicação.** Mantidos preços,
   limites e chaves FREE/BASIC/PRO; limites explícitos e aviso prévio sobre gestão de fiado no Básico.

Implementação validada por testes automatizados e backend publicado no ambiente
de testes. A avaliação com operadores e o lançamento comercial ainda não ocorreram.

## Preparação do piloto em 13/11/2026

O responsável confirmou que o produto ainda não foi lançado e que o servidor
atual, apesar de usar `APP_ENV=production`, é um ambiente de testes. Escolheu APK
para instalação direta e permitiu usar qualquer empresa desse ambiente.

- Workflow `Experience pilot APK` preparado para compilação em runner Android
  x64; este host de implantação é ARM e não possui SDK/assinatura Android.
- O pacote de testes é `br.com.tatuzin.gestao.pilot`, com rótulo Tatuzin Piloto,
  certificado Android de teste e telemetria `1.0.1-pilot`. O pacote definitivo
  continua exigindo a assinatura release configurada.
- Imagem candidata local: `tatuzin-backend:experience-pilot-20261113`.
- A imagem final foi compilada e iniciou em Docker com PostgreSQL descartável;
  migrations, readiness, cadastro sem slug, flags no bootstrap, reconciliação,
  ingestão/reenvio de eventos e proteções de empresa/admin passaram no smoke HTTP.
  Dados sintéticos ficaram exclusivamente no ambiente `isolated-test`.
- O relatório executado dentro da imagem retornou `insufficient_data` para zero
  checkouts, conforme esperado; dois testes adicionais da classificação passaram.
- Overlay de testes liga as duas flags para todas as empresas; o compose normal
  mantém os defaults desligados e aceita listas de empresas.
- Relatório diário: `npm run experience:report -- --days 1 --app-version 1.0.1-pilot`
  no container atualizado. Não aprova uma amostra vazia e não substitui observação humana.
- Roteiro e registro das cinco sessões: [Avaliação do piloto](experience-pilot-acceptance.md).

O responsável autorizou explicitamente enviar o código à branch pública
`codex/experience-pilot` para compilar o APK e atualizar o backend/banco de testes
de `api.tatuzin.com.br`, com backup privado e experiência habilitada para todas as
empresas. A execução e seus resultados devem ser registrados abaixo.

### Publicação do backend de testes

- Publicado em 13/11/2026, às 12h47 (America/Sao_Paulo), usando a imagem
  `tatuzin-backend:experience-pilot-20261113`, digest
  `sha256:992fac8adaf088bf7708000e0c40ec0bb8b121a2f5d3bbd59ac3c76b61430c2d`.
- Backup privado anterior às migrações em `.release-backups/experience-20261113/`,
  fora do Git, com permissões restritas e arquivo legível pelo `pg_restore --list`.
  Não anexar nem enviar esses arquivos ao repositório público.
- As três migrations desta entrega foram aplicadas ao banco do ambiente autorizado.
  Recriado somente o backend; PostgreSQL e os demais serviços foram preservados.
- Readiness pública retornou HTTP 200 com banco saudável; os endpoints novos
  recusaram requisições anônimas com HTTP 401. Flags verificadas para as cinco
  empresas existentes. Não foram criadas vendas fictícias nesse ambiente.
- Imagem anterior preservada como `tatuzin-backend:rollback-experience-20261113`.
  Sem o overlay, as duas flags retornam falso; migrações aditivas permitem manter
  os dados ao reverter a experiência.
- CI remoto de Flutter e backend aprovado no [PR #1](https://github.com/wilhamsouza/Tatuzin/pull/1).

### Monitoramento ativo

- Timer do sistema `tatuzin-experience-collector.timer` executa coleta somente
  leitura a cada minuto e persiste após reiniciar a máquina.
- Prometheus recebe readiness HTTPS, contagens da versão `1.0.1-pilot` em janela
  móvel de 24h e mediana de duração declarada pelo app. Sem conclusões, a mediana
  é `NaN`, sem inventar tempo zero ou aprovação.
- Painel Grafana `tatuzin-experience-pilot` provisionado; alertas locais verificados
  para indisponibilidade, atraso da coleta e checkout lento com amostra mínima.
  Nenhum destinatário externo foi configurado; consultar o Alertmanager/Grafana local.
- Acesso pelo túnel SSH já usado pelo monitoramento, com Grafana em
  `http://127.0.0.1:3000/d/tatuzin-experience-pilot`. Não expor essas portas à internet.

### APK entregue

- [Artefato do APK piloto](https://github.com/wilhamsouza/Tatuzin/actions/runs/43455821449/artifacts/14054251967),
  gerado por workflow aprovado em 13/11/2026; inclui APK, checksum e proveniência.
- Cópia local em `build/pilot/tatuzin-1.0.1-pilot.apk`, 98.619.854 bytes.
  SHA-256: `72f222dbcaaef438ee17c87ae3c95a18333ae3dd8cf354094c50ad177365869a`.
- Compilado a partir do merge de teste do PR,
  `78168f39cf8fea93ad8d1d721ab6b6a0b11de2c1`; branch de código
  `33d726fa7acc283df61a5a930c62b7ccfb0616a6`.
- Pacote e depuração conferidos pelo `apkanalyzer`; arquivo e APK baixados com
  checksums conferidos. Certificado Android de testes, separado do pacote oficial.
- Instalar Tatuzin Piloto, entrar na empresa de testes e verificar cinco abas.
  O APK não foi instalado nem avaliado por cinco operadores nesta execução.
- Único critério de aceite de produto ainda pendente: sessões humanas e comparação
  observada de tempo/erros. Os resultados não podem ser substituídos por testes de CI.

## Contrato de perfil da loja

`company.experienceProfile`: `moda`, `alimentacao` ou `misto`.
Retornado por `/api/app/bootstrap` e `/api/app/company/settings`.
O dono pode alterar pelo PATCH de configurações ou pela tela Configurações.
Administradores continuam podendo editar comprovantes, mas não o perfil.
O campo não altera permissões, entitlements, produtos nem a arquitetura de sync.
Moda oculta Insumos no drawer e opções de alimentação no cadastro novo.
Produtos antigos continuam editáveis; produto simples de moda não exige grade.

Novas empresas têm default `moda`. A migration classifica empresas existentes
uma única vez usando o catálogo persistido, incluindo produtos inativos/excluídos:
somente moda → moda; somente alimentação → alimentação; misto, desconhecido ou
vazio → misto. Alterações futuras no catálogo não sobrescrevem a escolha do dono.
Clientes antigos podem omitir o campo nos PATCHes. Apps novos preservam a
experiência mista quando o backend/cache antigo não contém esse campo.

## Contratos de jornada e onboarding

- `POST /api/product-journey/events`: até 50 eventos por lote; exige sessão e
  dispositivo válidos. Empresa e dispositivo de persistência vêm do contexto
  autenticado; um companyId divergente é recusado. Reenvios retornam os mesmos ACKs.
- `GET /api/admin/product-journey/report`: exclusivo de platform admin; filtros
  opcionais por empresa, versão, plano e perfil, janela de 1 a 90 dias.
  Mostra eventos, empresas, tentativas e mediana de duração de checkout.
  São etapas alcançadas no período, não uma coorte sequencial. Saída não é prova de
  abandono definitivo; assinatura iniciada não significa pagamento confirmado.
- `POST /api/app/onboarding/reconcile`: exclusivo do dono, sem marcos enviados pelo
  cliente. Lê produtos, caixas e vendas da empresa e persiste marcos monotônicos.
  Retorna `enabled`, `productReady`, `cashReady`, `completedAt`.
- O app combina esses marcos com os registros do SQLite e um cache por empresa.
  Venda cancelada depois da ativação não reinicia a configuração. Empresas com
  vendas existentes não precisam realizar uma venda demonstrativa ou repetir o processo.
- O cadastro público aceita omitir `companySlug`; clientes antigos continuam
  enviando o campo. O bootstrap administrativo inicial mantém seu contrato anterior.

## Liberação por etapas

Os dois controles vêm no objeto `company` do bootstrap e são guardados no cache de sessão:

| Controle backend | Campo no app | Comportamento |
| --- | --- | --- |
| `PRODUCT_ONBOARDING_COMPANY_IDS` | `onboardingEnabled` | Habilita o checklist para empresas internas/piloto |
| `PRODUCT_EXPERIENCE_COMPANY_IDS` | `experienceRefreshEnabled` | Habilita cinco abas e checkout compacto para empresas internas/piloto |
| `PRODUCT_ONBOARDING_ENABLED=true` | `onboardingEnabled` | Amplia onboarding para todas as empresas |
| `PRODUCT_EXPERIENCE_ENABLED=true` | `experienceRefreshEnabled` | Amplia abas e checkout compacto para todas as empresas |

As listas são separadas por vírgulas. Os booleanos gerais começam desligados.
Sem os campos no bootstrap/cache antigo, o app mantém navegação sem barra e
checkout com opções abertas. Corrigir contagem e retirar métricas vazias não depende do piloto.
Após mudar os controles no servidor, renovar a sessão/bootstrap para atualizar o dispositivo;
offline ele conserva a última configuração recebida. Reversão segue o mesmo caminho,
sem apagar produtos, operações, assinaturas ou progresso.

## Validação e publicação

- Verificação final em 13/11/2026: 608 testes Flutter aprovados e análise estática
  sem problemas; TypeScript sem erros; 14 testes focados de contratos/acesso,
  19 testes da plataforma e sete integrações de onboarding/jornada aprovados no backend.
- O teste de onboarding offline usa SQLite real e confirma que a liberação recebida
  no bootstrap mantém o checklist ativo antes da primeira reconciliação com o servidor.
- Gerar cliente Prisma e validar schema; executar TypeScript com `--noEmit`.
- Testar valores aceitos e recusa de alteração por não proprietários.
- Testar mapeamento legado, merge e PATCH parcial no Flutter.
- Migrations e classificação de catálogos moda, alimentação, misto e vazio
  verificadas em PostgreSQL descartável; testes Flutter executados com SDK temporário
  compatível com o lockfile, sem atualizar dependências do projeto.
- Aplicar migration antes de iniciar o backend novo; em seguida publicar o app.
  Na validação inicial, migrations rodaram em banco descartável; depois da autorização,
  foram aplicadas ao servidor existente, confirmado como ambiente de testes apesar
  de seu rótulo técnico `production`.
- Antes da publicação geral, validar com cinco operadores a primeira venda e as
  trocas de aba, comparar tempo de checkout e falhas com a versão anterior e
  confirmar que a mediana da venda simples fica abaixo de 15 segundos.

## Critérios gerais das próximas entregas

Medir ativação, duração de checkout, saídas sem concluir, erros e conversão de planos.
A telemetria implementada tem fila própria, deduplicação, isolamento por empresa/dispositivo e
retenção de 90 dias, sem bloquear vendas. Não incluir dados pessoais ou conteúdo
de carrinho. Liberar mudanças de experiência por flags: interno, piloto e geral.
Validar navegação/checkout com cinco operadores antes da liberação geral.
