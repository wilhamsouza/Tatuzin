# APK piloto mobile — 1.0.3-pilot

## Conteúdo

- Novo Início roxo: atalhos circulares, resumo do dia, vendas dos últimos sete dias, pendências e últimas movimentações.
- Dados reais da base local. Lucro reutiliza as regras existentes dos relatórios, incluindo fiado proporcional ao recebido; custo desconhecido mantém o indicador indisponível.
- Permissões, tema escuro, texto ampliado e estados de carregamento, vazio, erro e offline.
- Correções anteriores preservadas: comprovantes fora das abas, Atividade com as vendas do dia, cliente no checkout e associação posterior em vendas simples, drawer rolável e sincronização auditada.

O painel do proprietário da Fase 2 continua acessível pelo navegador; não foi embutido no APK.

## Compatibilidade

O aplicativo continua sendo **Tatuzin Piloto 2**, pacote `br.com.tatuzin.gestao.pilot2`. A assinatura usa a chave persistente do servidor, que permanece privada e nunca é enviada ao GitHub Actions. A atualização sobre 1.0.2-pilot preserva o banco e a sessão existentes; não desinstalar o aplicativo para atualizar.

Quem ainda tiver somente o primeiro piloto (`br.com.tatuzin.gestao.pilot`) receberá o Piloto 2 em paralelo, conforme a escolha anterior. Dados locais não sincronizados do primeiro pacote continuam nele.

## Compilação e verificações

- Fonte mobile: commit `b6e75a4c3acd4853954c26242e2458ff9e9d341b`, branch `codex/experience-pilot`.
- Candidato compilado pelo GitHub Actions, workflow `43594287252`; o host recebe um APK sem assinatura e assina com a chave persistente.
- Flutter 3.41.9; análise estática e testes críticos executados no CI. A implementação mobile também passou pela suíte completa local de 625 testes.
- Conferir pacote, versão, incremento do versionCode, certificado igual ao APK 1.0.2-pilot, assinatura válida e checksum do download HTTPS antes da distribuição.
- Metadados finais e checksum ficam em `build/pilot/1.0.3/verification.json` e no endereço público de checksum do APK.

## Testar no Android

1. Instalar a atualização sobre **Tatuzin Piloto 2**, sem desinstalar. Conferir que os dados já presentes continuam disponíveis.
2. Abrir Início e conferir resumo, gráfico, estoque e pendências com as telas de origem. Não esperar lucro disponível para produtos sem custo cadastrado.
3. Fazer duas vendas, fechar cada comprovante e abrir Atividade. A aba deve mostrar as vendas de hoje, sem manter o último comprovante aberto.
4. Selecionar cliente no checkout e, em uma venda simples permitida, usar Vincular/Alterar cliente pelo detalhe. Conferir o comprovante e a sincronização.
5. Abrir o menu por toque e gesto nas cinco abas, alternar tema e ampliar a fonte. Conferir que a busca de Produtos permanece preservada ao trocar de aba.
6. Repetir uma operação offline e sincronizar ao reconectar. Conferir os avisos de pendência/conflito quando aplicáveis.

A repetição em aparelho físico e a avaliação com operadores continuam sendo etapas de aceitação do usuário; não são simuladas pelos testes automatizados.

## APK publicado

[Baixar Tatuzin Piloto 2 — 1.0.3-pilot](https://api.tatuzin.com.br/downloads/tatuzin-1.0.3-piloto-2.apk)
e [checksum SHA-256](https://api.tatuzin.com.br/downloads/tatuzin-1.0.3-piloto-2.sha256).

- VersionCode 6, superior ao 5 da versão 1.0.2-pilot.
- Assinaturas APK v2 e v3 válidas; certificado igual ao APK anterior.
- Certificado SHA-256: `ac32b18025da277535d163f0ead1b0dda515aa8c993134ffc48d5d410bb0fb47`.
- APK SHA-256: `f8c56743dd0b227de3023575ac8594aa7b5ba85015182a63e0076285053270bb`.
- Tamanho: 98.940.153 bytes.
- Android ARM, ARM64 e x86_64; 18 bibliotecas nativas conferidas, com alinhamento ZIP de 16 KiB nas bibliotecas não comprimidas.
- Fonte do merge de teste: `bdad4580277f952f02b774b26364b87f45dde6a6`.
- Workflow do APK e CI geral concluídos com sucesso. Download HTTPS completo, hash e assinatura conferidos novamente no arquivo recebido pela URL pública.
- APK 1.0.2-pilot preservado. O coletor do piloto passa a incluir eventos reais das versões 1.0.2-pilot e 1.0.3-pilot, sem gerar sessões ou vendas sintéticas.
