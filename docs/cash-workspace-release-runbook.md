# Caixa — implantação e recuperação (ainda não executadas em produção)

## Autorização e estado

A implementação é local. Publicar backend, painel ou APK em produção exige autorização específica posterior do proprietário. Nenhum comando deste roteiro foi executado contra serviços publicados. Não alterar credenciais nem transportar bancos reais para testes.

## Regras operacionais

- Decisão final: caixa geral da empresa consolidado na nuvem e caixa individual por funcionário, independente do aparelho. A identidade do funcionário é o usuário autenticado da empresa; não um ID escolhido pelo cliente. Aparelhos autorizados do mesmo funcionário participam da mesma sessão central e não somam novamente o fundo inicial. Funcionários diferentes não compartilham a sessão individual.
- O aparelho novo precisa obter a sessão central e registrar participação online antes de usá-la offline. Aparelhos já participantes usam o cache offline. Aberturas concorrentes não criam dois fundos nem fundem valores silenciosamente; conflitos e indisponibilidade da nuvem são informados.
- Conferência offline é pendente, não um fechamento definitivo. Todos os aparelhos participantes precisam enviar as operações e reconhecer a mesma revisão. Movimentos novos invalidam os reconhecimentos antigos. Se o saldo central divergir da prévia conferida, o funcionário deve revisar e confirmar novamente; a contagem registrada não é silenciosamente substituída.
- Um aparelho sem comunicação recente não é considerado sincronizado. Dispositivo perdido/bloqueado com operações pendentes exige diagnóstico e recuperação; não há conclusão forçada automática com saldo presumido. Sessões V1/V2 antigas continuam identificadas e não são retroativamente fundidas por funcionário.
- A configuração cega é desligada por padrão e possui revisão. Cada abertura captura a política recebida pelo aparelho. Alterações posteriores valem na próxima abertura. Aparelhos desconectados continuam com a última política recebida; clientes antigos não passam a oferecer fechamento cego por atualização do servidor.
- A conferência vincula UUID, requisição e estado revisado. Gravar o pedido durável e o estado local pendente é atômico. A conclusão central ocorre somente depois da barreira de sincronização, com revisão, idempotência e fotografia final imutável. Pedidos ainda não concluídos são reenviados pela rotina de sincronização; o fluxo V1/V2 mantém seu evento e fechamento local na mesma transação. Reenviar não gera novo fechamento nem atinge a próxima sessão.
- O total contado começa vazio. Zero exige preenchimento explícito. Diferença exige motivo. Em fechamento cego, motivo é sempre exigido e o esperado só aparece depois de confirmar.
- Revisão gerencial é um histórico independente com autor, motivo e revisão concorrente. Reabrir a revisão não reabre o caixa nem muda a contagem original.
- Eventos tardios V3 enquanto pendente invalidam aceites e podem exigir nova conferência. Depois de fechado centralmente, novos movimentos não são aceitos como se ainda estivesse aberto; duplicados reconhecidos não reaplicam saldo. O contrato V2 legado preserva seu tratamento compatível de eventos tardios, sem reescrever a fotografia original.
- Pagamentos e diferenças usam centavos inteiros. Recebimentos em Pix/cartão não compõem numerário. Venda fiado só entra como recebimento na parcela efetivamente recebida. Cancelamento estorna cada meio registrado. Recebimento legado sem meio identificável exige conferência, sem presumir dinheiro.
- O checkout atual oferece um meio imediato por venda. A cobertura multimeio desta entrega testa o ledger de recebimentos da sessão e pagamentos parciais de uma nota fiado em meios diferentes; não acrescenta divisão de uma venda à vista em vários meios no checkout.

## Preparação da publicação, após autorização

1. Congelar uma revisão dos artefatos e registrar versões/hashes de backend, painel e APK; preservar a imagem e o diretório atualmente publicados. Manter o app anterior instalado para a validação piloto.
2. Atualizar todos os aparelhos que participarão do caixa compartilhado. Encerrar e sincronizar os caixas do aplicativo anterior antes da migração operacional; versões antigas continuam no modelo legado, não entram automaticamente na mesma sessão central. Confirmar compatibilidade em homologação com uma cópia anonimizada: clientes antigos, eventos antigos enfileirados, sessões já abertas e v2. A mudança do PostgreSQL é aditiva: `20261120090000_cash_workspace` acrescenta duas colunas com padrão e a tabela de revisões; não renomeia ou remove dados. Os metadados locais adicionais usam a tabela SQLite `configuracoes`, sem downgrade do schema existente. A evolução por funcionário acrescenta a migração `20261120100000_employee_cash_workspace` (participantes, revisão e pedidos de fechamento); aplicar também `20261120101000_employee_cash_blind_count` (esperado opcional na conferência cega) e `20261120102000_cash_workspace_deferred_device_keys` (integridade das referências na exclusão transacional do tenant). São quatro migrações aditivas novas; aplicar antes de clientes V3.
3. Fazer backup privado consistente PostgreSQL (`pg_dump` formato custom), configurações e versões publicadas. Calcular checksum; guardar fora da pasta pública e com acesso restrito. Verificar espaço livre. Restaurar esse backup em banco isolado e comparar migrações, contagens de registros e amostras de fechamentos/auditoria antes de autorizar a troca.
4. Aplicar a migração com o backend anterior ainda compatível. Publicar o backend novo primeiro. Verificar saúde, login, settings antigos/novos, relatórios e sync. Interromper a liberação se aparecer conflito/duplicação ou perda de precisão.
5. Publicar o painel e só então distribuir o APK para empresa piloto. Deixar fechamento cego desligado até validar o fluxo normal. Testar a política cega em nova sessão recebida online e depois repetir offline.
6. Observar recusas e conflitos de sync, falhas de auditoria, latência, divergências e duplicações. Ampliar acesso somente após aceite dos cenários abaixo.

## Rollback

- Em falha de cliente, restaurar os artefatos anteriores do painel/app conforme compatibilidade validada. Não apagar SQLite nem limpar a fila para resolver falha; exportar diagnóstico e preservar operações pendentes.
- Se a política cega causar problema, desligá-la por empresa via fluxo autorizado. Isso vale para aberturas futuras; sessões já abertas preservam sua política original.
- A reversão preferencial é dos artefatos, mantendo as colunas/tabela aditivas e os metadados. Não executar `DROP`, não remover migração aplicada e não apagar revisões gerenciais.
- Reverter backend só após confirmar que a versão anterior aceita os payloads já em fila. Se não aceitar V2, manter o backend compatível e reverter apenas as telas, ou aplicar correção prospectiva. Não reprocessar movimentos manualmente como novos lançamentos.
- Restaurar banco inteiro é último recurso, com indisponibilidade controlada e plano de recuperação das operações posteriores ao backup. Exige nova autorização explícita, pois pode descartar operações legítimas. Nunca restaurar um dump antigo sobre o banco ativo por conveniência.

## Ensaio local executado

Somente PostgreSQL descartável `127.0.0.1:55442`, banco `tatuzin_cash_test`. Backup custom criado em `/tmp/tatuzin-cash-workspace-test-backup.dump` (acesso 0600) e restaurado em `tatuzin_cash_restore_test`, no mesmo container isolado. Restauração concluiu sem erro; as 52 migrações foram preservadas, a coluna de fechamento cego mantém padrão `false` e a tabela independente de revisão existe. Esse ensaio comprova o mecanismo local; não substitui validar um backup privado real antes da implantação autorizada.

## Repetição no Android piloto

1. Abra Caixa, informe a contagem na calculadora e use o total. Confira abertura e moedas/centavos.
2. Faça recebimentos em dinheiro, Pix e cartão; receba parte de um fiado. Confira que somente dinheiro altera saldo físico.
3. Abra fechamento: o campo inicia vazio, aceita zero explícito e o botão permanece utilizável com teclado aberto e fonte 200%. Revise; diferença exige motivo.
4. Antes de registrar a conferência, force parada do app; reabra e confira rascunho. Depois de registrar offline, force parada e reabra: deve haver um único pedido pendente, sem apresentar conclusão definitiva. Após sincronizar todos os participantes, reinicie e confira uma única conclusão. Não prometer recuperação de teclas ainda não persistidas no instante da interrupção.
5. Faça uma movimentação entre revisão e confirmação; a prévia deve ser recusada até nova conferência.
6. Registre a conferência offline, reinicie, conecte e reenvie sync. Antes de todos os participantes reconhecerem a revisão, a situação permanece pendente. O saldo não pode ser aplicado duas vezes. Após a conclusão, abra outro caixa e repita a confirmação antiga: não pode fechar o novo.
7. No painel, revise a divergência, registre motivo, recarregue e confirme valores originais e histórico de autoria. Teste usuário sem permissão e outra empresa.
8. Ative fechamento cego, abra uma nova sessão após atualizar a configuração, e confirme ocultação de esperado/diferença até finalizar. Use o mesmo funcionário em dois aparelhos: confirme o mesmo UUID e um único fundo inicial; deixe um aparelho offline com venda pendente, registre conferência no outro e comprove que a conclusão aguarda sincronização e nova revisão quando o saldo muda. Use outro funcionário e confirme isolamento entre caixas individuais e a consolidação da empresa.

A repetição física no Android, o ensaio com backup real e o aceite da empresa piloto permanecem pré-requisitos da publicação; testes automatizados não substituem esse aceite.
