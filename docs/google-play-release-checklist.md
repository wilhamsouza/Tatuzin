# Checklist de lancamento Google Play - Tatuzin

> Antes de enviar, conferir no Play Console as exigencias atuais de targetSdk, Data Safety, permissoes, anuncios, politica de dados e assinaturas.

## 1. Pre-requisitos

- Conta Google Play Console ativa.
- Perfil de pagamentos, se exigido.
- Politica de privacidade publicada.
- Termos de uso publicados.
- E-mail de suporte.
- Site ou landing page do Tatuzin.
- Prints do app.
- Descricao curta.
- Descricao completa.
- Categoria do app.
- Classificacao indicativa.
- Formulario de seguranca de dados.
- Informacao se coleta dados.
- Informacao sobre login e conta.
- Dados de teste para revisao se o app exigir login.

## 2. Checklist tecnico

- `flutter clean`
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build appbundle --release`
- Testar instalacao local.
- Testar login OWNER.
- Testar login Caixa.
- Testar PDV.
- Testar venda.
- Testar caixa.
- Testar sync.
- Testar assinatura.
- Testar Mercado Pago.
- Testar tema claro/escuro.
- Testar offline/online.
- Testar conta FREE.
- Testar conta PRO.
- Testar `pendingPlan=PRO`.
- Confirmar `applicationId` definitivo.
- Confirmar nome do app: Tatuzin.
- Confirmar icone 512x512 e icones Android.
- Confirmar splash screen, se existir.
- Confirmar `versionName` e `versionCode`.
- Confirmar `minSdk`, `targetSdk` e `compileSdk` com Flutter/Play Console.
- Confirmar permissoes minimas.
- Confirmar `INTERNET` presente.
- Confirmar `CAMERA` justificada pelo leitor/uso operacional.
- Confirmar cleartext traffic desativado em release.
- Confirmar URLs de producao e ausencia de localhost/dev em release.
- Confirmar logs sensiveis removidos/protegidos.

## 3. Checklist comercial

- Nome do app.
- Descricao curta.
- Descricao completa.
- Screenshots.
- Icone 512x512.
- Feature graphic, se necessario.
- Politica de privacidade.
- Termos de uso.
- Suporte.
- Site do produto.
- Texto sobre assinatura PRO.
- Texto sobre trial de 15 dias.
- Explicacao de renovacao automatica.
- Explicacao de cancelamento.

## 4. Checklist Mercado Pago antes de enviar

- Criar assinatura real com conta controlada.
- Confirmar abertura do checkout.
- Confirmar cadastro de cartao.
- Confirmar webhook recebido.
- Confirmar `pendingPlan`.
- Confirmar que `pendingPlan` nao libera PRO.
- Confirmar promocao para PRO so apos confirmacao segura.
- Confirmar invoice.
- Confirmar cancelamento durante trial.
- Confirmar retomada.
- Confirmar troca de plano.
- Confirmar que falha de pagamento nao libera plano.
- Confirmar que usuario nao OWNER nao gerencia assinatura.
- Confirmar que `owner_web` so libera com `license.plan=PRO`.

## 5. Observacao

- Conferir no Play Console as exigencias atuais de targetSdk, Data Safety, permissoes, anuncios, politica de dados e assinaturas antes de enviar.
- Em maio de 2026, a documentacao publica do Android Developers informa exigencia de target Android 15/API 35 ou superior para novos apps e updates comuns; valide novamente no Play Console antes do envio.
