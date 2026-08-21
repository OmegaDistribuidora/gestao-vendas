# Build iOS com Codemagic

## Identificação do aplicativo

- Nome: `Gestão de Vendas`
- Bundle ID: `br.com.omegadistribuidora.gestaovendas`
- Versão Flutter atual: `0.9.14+30`
- Versão mínima do iOS: `15.0`

O Bundle ID precisa ser idêntico no Apple Developer, App Store Connect, Firebase,
projeto Xcode e Codemagic.

## Firebase no Codemagic

O arquivo real `ios/Runner/GoogleService-Info.plist` não é versionado. Ele é
ignorado pelo Git e deve ser criado durante o build a partir de uma variável
secreta.

1. Converta o arquivo para Base64 no PowerShell:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Users\POWERBI\Desktop\GoogleService-Info.plist')) | Set-Clipboard
   ```

2. No workflow do Codemagic, crie a variável:

   - Nome: `GOOGLE_SERVICE_INFO_PLIST_BASE64`
   - Valor: conteúdo copiado para a área de transferência
   - Marcar: `Secret`

3. Antes da etapa de build, adicione o script:

   ```sh
   sh tool/prepare_ios_firebase.sh
   ```

## Notificações APNs + Firebase

A chave da API do App Store Connect usada pelo Codemagic não substitui a chave
APNs usada pelo Firebase.

1. Acesse Apple Developer > Certificates, Identifiers & Profiles > Keys.
2. Crie uma chave com a permissão `Apple Push Notifications service (APNs)`.
3. Baixe o arquivo `.p8` e guarde o Key ID.
4. No Firebase, acesse Configurações do projeto > Cloud Messaging.
5. Na configuração do app iOS, envie a chave APNs e informe:
   - Key ID da chave APNs
   - Team ID: `BCM99G6F4D`

## Configuração do workflow visual

- Plataforma: `iOS`
- Project path: `.`
- Mode: `Release`
- Build arguments: somente `--release`
- iOS code signing: automático
- Distribution type: `App Store`
- Bundle ID: `br.com.omegadistribuidora.gestaovendas`
- App Store Connect integration: `codemagic`
- Enviar para TestFlight: habilitado
- Enviar automaticamente para revisão da App Store: desabilitado no primeiro teste

Antes do build iOS, o script `tool/prepare_ios_firebase.sh` precisa ser executado.

## TestFlight

- A build `0.9.11 (26)` foi a primeira entrega aceita pelo App Store Connect.
- A build `0.9.11 (27)` adiciona a descrição de localização exigida pela
  validação `ITMS-90683` e declara que o app utiliza somente criptografia isenta
  de documentação de exportação.
- A próxima entrega é `0.9.14 (30)`. O Codemagic deve usar a branch/tag
  `v0.9.14+30`, que contém `version: 0.9.14+30`; o Flutter propagará
  automaticamente `0.9.14` para `CFBundleShortVersionString` e `30` para
  `CFBundleVersion`.
- Esta entrega adiciona câmera, biblioteca de fotos e localização à Agenda.
  As chaves `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
  `NSLocationWhenInUseUsageDescription` e
  `NSLocationAlwaysAndWhenInUseUsageDescription` já estão declaradas no
  `ios/Runner/Info.plist`.
- Para testes internos, não é necessário marcar `Submit to TestFlight beta review`.
- Para grupos externos, a build precisa ser enviada à revisão beta da Apple.
