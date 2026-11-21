# Produtos e Estoque — execução

Plano aprovado: Produtos e Estoque separados no app e no owner_web, com Contagens dentro de Estoque. Aplicação de ajustes e contagens exige conexão; vendas seguem offline. admin_web fora do escopo.

## Quadro de trabalho

| Frente | Responsável | Estado | Critério de revisão |
| --- | --- | --- | --- |
| Catálogo seguro e integração | root | Validado | Edição parcial, revisão concorrente, identidade dos SKUs e estoque preservados |
| Backend de estoque | inventory_backend | Publicado no piloto | Migração aditiva, 108 testes de contratos e 37 de relatórios; imagem HTTP validada |
| Painel proprietário | owner_inventory | Publicado | 67 testes e 25 capturas no navegador sem erros; caminho/filtros preservados após autenticação |
| App mobile | mobile_inventory / root | Publicado como APK piloto | 662 testes Flutter no CI, assinatura e download HTTPS conferidos |

Alterações anteriores no workspace são preservadas. A integração usa áreas de arquivo distintas e revisão sequencial pelo responsável principal. Publicação depende da validação dos contratos e testes; backend antecede os clientes.

## Organização entregue

Produtos contém catálogo, filtros, detalhe e cadastro. Estoque contém Saldos, Movimentações e Contagens. No Android, as cinco abas principais permanecem; Estoque é acessado pelo menu e por atalho em Produtos. No painel, os módulos aparecem separados e a consulta gerencial anterior fica em `/products/analysis`.

Contagens locais anteriores ficam no histórico do aparelho, sem aplicação ou publicação automática dos ajustes antigos. Sessões centrais têm um responsável, revisão, itens não contados explicitamente nulos e aplicação online após conferência. Uma alteração de saldo durante a contagem exige nova conferência.

## Design e Astryx

Foi aplicada a skill local `astryx` e consultada a CLI/Core 0.7.16 com `astryx build`, o template `table-filter` e os componentes `Table` e `BottomSheet`. A orientação para páginas existentes é manter a estrutura e aproveitar os blocos necessários. As referências foram adaptadas a widgets nativos Flutter Material 3; não foi criada outra aplicação React nem adicionada uma biblioteca JavaScript ao cliente Flutter.

A revisão usa listas/tabelas com filtros visíveis, detalhe contextual, estados vazios e erros recuperáveis. Seleção em lote sem operação correspondente foi removida da tabela de produtos. No Android, `ProductStockSurface` reutiliza a paleta roxa existente, inclusive os estilos de chips, campos e botões que antes herdavam verde. O tema global do ERP permanece preservado. Capturas com fontes reais verificam largura e escala de texto; fixtures de demonstração pertencem exclusivamente aos testes.

## Contratos e consistência

- `/api/products`: cadastro existente com `metadataOnly`, `expectedCatalogRevision` e IDs persistentes das variações. PUT parcial preserva campos não expostos; formulários legados com saldo desatualizado recebem 409. Reenvio de criação não recria variações nem repõe estoque.
- `/api/inventory`: capacidades reais, consulta e resumo paginados, detalhe por produto/variação, movimentações, ajustes idempotentes e limites de reposição. Autorizações usam a empresa do contexto, permissões e recursos do plano.
- `/api/inventory/counts`: criar, selecionar itens, contar, revisar, transferir, cancelar e aplicar. Histórico e alterações são auditados. Limite atual: 500 itens por sessão; detalhe apresenta os últimos 100 eventos, mantendo os demais no banco.
- `/api/inventory/initial-balances`: primeira entrada positiva e confirmada, com revisão e idempotência próprias. Preserva o saldo inicial no FREE sem liberar ajustes ou contagens avançados.
- Revisões e lançamentos observam as alterações de estoque existentes por triggers PostgreSQL. A observação não repete a baixa. Auditoria registra a origem e o autor disponíveis; não inventa responsáveis para registros antigos.
- No piloto, os alertas do painel usam os mínimos por SKU da mesma fonte operacional. Mínimo zero significa não configurado; igualdade ao mínimo não gera alerta. Os relatórios continuam indicando produtos ativos, enquanto a lista operacional pode incluir inativos por filtro.

## Validação e artefatos

Backend: `build/products-stock/backend-tests.log` e `backend-owner-tests.log` registram 145 testes aprovados em conjuntos distintos. `candidate-image-check.json` registra sete verificações HTTP da imagem compilada em banco descartável: cadastro sem estoque, entrada inicial, contagem, reenvio sem duplicação e edição cadastral preservando saldo. Não foram feitas vendas ou ajustes sintéticos na empresa publicada.

Painel: `owner_web/build/products-stock/` contém fixtures identificadas, capturas e logs. Os testes usam a navegação real, as cinco larguras de 360 a 1440 px e texto até 200%. A abertura por link direto e o retorno após login preservam caminho, busca, filtros e página; destinos externos não são aceitos no retorno.

A publicação web `owner-products-stock-20261120-r1` está em https://painel.tatuzin.com.br. Rotas HTTPS, política de cache e SHA-256 do bundle servido foram conferidos; o resultado está em `public-release-checks.json`. A navegação autenticada automatizada usa fixtures interceptadas, sem enviar a credencial falsa à API real.

Mobile: os testes novos estão em `central_inventory_api_test.dart`, `product_stock_consistency_test.dart` e `stock_workspace_test.dart`, além das regressões existentes. Incluem isolamento por empresa/operador, proteção de saldos com eventos pendentes, revisões e contagens incompletas. A migração SQLite 39 é aditiva e mantém o histórico existente.

A versão final também inclui `confirmed_inventory_mirror_test.dart` e a regressão de carrinho já aberto. Antes de uma alteração de quantidade, o app preserva sua identidade e protege o saldo local. Se a resposta se perder, a recuperação usa a mesma chave, sem criar outra operação. Depois de confirmar, consulta quantidades atuais antes de espelhar valores absolutos no SQLite; nunca reaplica o delta do ajuste. Pendências operacionais impedem sobrescrita. Enquanto a conferência estiver pendente, o PDV fica protegido inclusive para carrinhos já existentes. Os rascunhos continuam privados por empresa/operador; o bloqueio de consistência acompanha o banco da empresa.

Validação final: análise estática limpa, 662 testes Flutter aprovados no [CI da revisão entregue](https://github.com/wilhamsouza/Tatuzin/actions/runs/44697697245) e compilação do APK aprovada no [workflow piloto](https://github.com/wilhamsouza/Tatuzin/actions/runs/44697697278). As três abas de Estoque permanecem visíveis com quebra de linha em telas pequenas.

## APK entregue — 1.0.4-pilot

[Baixar APK](https://api.tatuzin.com.br/downloads/tatuzin-1.0.4-piloto-2.apk) · [Checksum SHA-256](https://api.tatuzin.com.br/downloads/tatuzin-1.0.4-piloto-2.sha256).

Instalar sobre **Tatuzin Piloto 2**, sem desinstalar. Pacote `br.com.tatuzin.gestao.pilot2`, versionCode 9, superior ao 6 do APK 1.0.3. O certificado é o mesmo da versão instalada, mantendo banco e sessão.

- APK SHA-256: `75b8499ee750b526f499765cebdb9d167d633aace70e5949d70fa54b21b62693`.
- Certificado SHA-256: `ac32b18025da277535d163f0ead1b0dda515aa8c993134ffc48d5d410bb0fb47`.
- Tamanho: 99.087.609 bytes; ARM, ARM64 e x86_64. Assinatura verificada e alinhamento de 16 KiB conferido nas bibliotecas nativas não comprimidas.
- Código revisado: `fff37d6d3e885029c829615186dbb7b084ff496e`; merge compilado: `80fb4fb2c46c956e9b982219492646f251c325dc`. A árvore compilada corresponde à revisão entregue.
- [PR de revisão e compilação](https://github.com/wilhamsouza/Tatuzin/pull/2), mantido como draft; nenhuma integração na main foi feita automaticamente.
- `build/pilot/1.0.4/verification.json` e `public-download-check.json` registram conferência do pacote, certificado, bibliotecas e hash do download HTTPS. Versões anteriores foram preservadas.

## Publicação e retorno

Backend compatível: `tatuzin-backend:products-stock-20261120-r2`. O piloto é controlado por `INVENTORY_WORKSPACE_PILOT_COMPANY_IDS`, com uma empresa habilitada. Os demais ambientes conservam as restrições e a definição anterior dos relatórios.

O painel é publicado em diretório imutável, com `/release.json` e checksum do JavaScript, alternando o symlink existente. Backups privados de banco, ambiente e referência anterior estão em `.release-backups/products-stock-20261120/`; não publicar esses arquivos.

Rollback recomendado: restaurar os clientes anteriores e desligar o piloto, mantendo o backend que protege identidades e saldos. Não remover tabelas aditivas. Reverter para o backend antigo com escritas abertas recolocaria o comportamento de recriar variações e sobrescrever quantidades; nesse caso, congelar as escritas afetadas ou preferir correção para frente.

## Repetição no Android e painel

1. Abrir Produtos, buscar por nome/código, filtrar e conferir o detalhe. Editar nome ou preço e verificar que o saldo não muda.
2. Abrir Estoque pelo atalho/menu; conferir Saldos, Movimentações e Contagens.
3. Em uma empresa de testes habilitada, confirmar uma movimentação com motivo. Verificar histórico, responsável e saldo usado pelo PDV.
4. Criar uma contagem, deixar um item pendente e confirmar que a revisão é bloqueada. Informar zero explicitamente quando essa for a quantidade real.
5. Alterar o saldo após contar e conferir o bloqueio por revisão. Recontar, revisar e aplicar uma única vez.
6. Preparar um rascunho offline, reiniciar e conferir persistência. Trocar de operador e verificar que o rascunho não é exposto à outra conta.
7. Sincronizar antes da confirmação e verificar que vendas locais não sofrem baixa duplicada. No painel, voltar após login mantendo filtros e página.

O aceite com conta real/aparelho físico continua sendo uma repetição do usuário. Não equivale às fixtures automatizadas. Múltiplos depósitos, lotes/validade, contagem simultânea colaborativa e comunicação externa continuam fora desta entrega.
