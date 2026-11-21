# Vendas atribuídas ao funcionário — 14/11/2026

## Causa e correção

O app já grava o usuário vendedor na venda local (`seller_remote_user_id`), e a sincronização operacional grava `Sale.sellerUserId` com o usuário autenticado no servidor. Entretanto, o ranking de vendas do owner agrupava por `cashSessionId` e atribuía tudo ao usuário que abriu o caixa. Vendas sem caixa vinculado ficavam fora. O agrupamento ainda limitava os caixas antes de reunir os resultados por funcionário.

O relatório agora resolve o vendedor de cada venda antes de somar valores/quantidades e aplicar o limite de funcionários. Atividade e comissões passam a selecionar também `sellerUserId`, usando a mesma regra de identificação. A política preserva o vendedor da comanda convertida, quando existir; em seguida usa o vendedor registrado na venda; para registros legados mantém o autor do evento sincronizado e, por último, o responsável pelo caixa. Sem nenhuma dessas fontes, não inventa uma identificação. A consulta do owner verifica a associação do usuário à empresa consultada.

A alteração afeta a identificação para os relatórios. Não modifica os valores da venda, estoque, caixa, cálculo/base/taxa de comissão ou regras do fiado. Não regrava vendas antigas. Registros já sincronizados com autoria rastreável passam a aparecer no relatório corrigido. Não houve mudança de schema, API, Flutter ou APK nesta correção.

## Validação

- Regressão HTTP reproduzida antes da correção: dois vendedores no mesmo caixa eram contabilizados no responsável pelo caixa; venda sem caixa era omitida.
- Nova regressão valida ranking, atividade e comissão com dois vendedores, caixa compartilhado, venda sem caixa, evento legado, cancelamento e identidades/empresas diferentes. O vendedor registrado prevalece sobre um remetente diferente do evento.
- Regressão de sincronização com perfil SELLER: venda com data anterior ao upload preserva a autoria autenticada e a data de venda; reenvio é duplicata e não gera outra venda; IDs de vendedor/funcionário fornecidos no payload não substituem o usuário autenticado.
- Cinco testes da regra de identificação cobrem precedência e compatibilidade dos registros antigos.
- TypeScript sem erros (`npx --no-install tsc -p tsconfig.json --noEmit`).
- 148 testes de backend aprovados, sem falhas ou testes ignorados: regras de identificação e suítes HTTP de owner, funcionários e sincronização. Executados contra PostgreSQL descartável separado do ambiente utilizado pelo aplicativo.
- Build Docker aprovado. Imagem publicada: `tatuzin-backend:sale-attribution-20261114`, ID `sha256:3a7ecb215965d49cfab39546ece5e22e651cd93f172ff626cdb2fc4565aed042`.
- Saúde HTTPS aprovada após publicação; `/api/owner/reports/employees` sem autenticação retorna 401.
- Conferência interna somente leitura comparou o relatório compilado publicado com uma consulta SQL independente: quatro escopos de empresa examinados e três linhas de ranking conferidas para os últimos 30 dias, sem diferenças. Não foram expostos nomes, IDs ou valores das empresas na evidência.

## Arquivos

- `backend/src/modules/owner/owner-reporting.service.ts`: ranking por vendedor e compatibilidade com autoria legada.
- `backend/src/modules/employees/employee-sale-attribution.ts`: vendedor registrado na regra compartilhada.
- `backend/src/modules/employees/employee-activity.service.ts` e `employee-commission.service.ts`: seleção da autoria persistida.
- `backend/src/modules/employees/employee-sale-attribution.test.ts`, `backend/src/modules/owner/owner.routes.test.ts` e `backend/src/modules/sync/sync.routes.test.ts`: regressões.

Evidências locais em `backend/build/qa/sale-attribution-20261114/`. Backup privado do ambiente e referência da imagem anterior em `.release-backups/sale-attribution-20261114/`, fora dos artefatos públicos. O painel permanece na release r4 com a correção anterior de senha temporária.

## Repetição no Android e owner

1. Entrar no APK atual com o e-mail do funcionário e finalizar uma venda.
2. Aguardar a sincronização; se estiver offline, reconectar e sincronizar antes de conferir o painel.
3. Atualizar a página Funcionários no owner e verificar Vendas por funcionario no período da venda.
4. Repetir com outro funcionário usando o mesmo caixa: cada venda deve ser somada ao vendedor correspondente.
5. Consultar atividade e comissão para o mesmo período; os valores devem respeitar o vendedor e as regras de comissão já configuradas.

A repetição física no aparelho cabe à validação do usuário; os testes automatizados e a conferência interna publicada foram concluídos.
