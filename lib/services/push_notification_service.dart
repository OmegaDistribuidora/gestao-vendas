import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNavigationIntent {
  const PushNavigationIntent({required this.module, required this.data});

  final String module;
  final Map<String, dynamic> data;

  factory PushNavigationIntent.fromMessage(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    return PushNavigationIntent(module: '${data['module'] ?? ''}', data: data);
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushNotificationService.ensureFirebaseInitialized();

  if (kDebugMode) {
    debugPrint(
      'FCM background message received: ${message.messageId ?? '(sem id)'}',
    );
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _deviceIdStorageKey = 'push_device_id';

  static bool _backgroundHandlerRegistered = false;

  bool _initialized = false;
  bool _registrationEnabled = false;
  bool _profileAllowsPush = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  final StreamController<PushNavigationIntent> _navigationController =
      StreamController<PushNavigationIntent>.broadcast();
  PushNavigationIntent? _pendingNavigationIntent;

  Stream<PushNavigationIntent> get navigationIntents =>
      _navigationController.stream;

  PushNavigationIntent? takePendingNavigationIntent() {
    final intent = _pendingNavigationIntent;
    _pendingNavigationIntent = null;
    return intent;
  }

  static void registerBackgroundHandler() {
    if (_backgroundHandlerRegistered) {
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _backgroundHandlerRegistered = true;
  }

  static Future<bool> ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) {
      return true;
    }

    try {
      await Firebase.initializeApp();
      return true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Firebase ainda nao foi configurado para este build. '
          'Adicione android/app/google-services.json para ativar o FCM. '
          'Detalhe: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      return false;
    }
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    registerBackgroundHandler();

    final firebaseReady = await ensureFirebaseInitialized();
    if (!firebaseReady) {
      return;
    }

    final messaging = FirebaseMessaging.instance;

    await messaging.setAutoInitEnabled(true);

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
      _handleTokenRefresh,
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('Erro ao acompanhar refresh do token FCM: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      },
    );

    await _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );

    await _openedMessageSubscription?.cancel();
    _openedMessageSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }

    _initialized = true;
  }

  Future<void> registerForCurrentUser({
    required bool rememberLoginEnabled,
    required String profileSlug,
  }) async {
    _registrationEnabled = rememberLoginEnabled;
    _profileAllowsPush = _isPushProfile(profileSlug);

    registerBackgroundHandler();

    final firebaseReady = await ensureFirebaseInitialized();
    if (!firebaseReady) {
      return;
    }

    await initialize();

    final messaging = FirebaseMessaging.instance;
    final settings = await _requestPermission(messaging);
    final notificationsAllowed =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!rememberLoginEnabled || !_profileAllowsPush || !notificationsAllowed) {
      await revokeForCurrentUser();
      return;
    }

    final token = await messaging.getToken();
    await _registerToken(
      token: token,
      rememberLoginEnabled: rememberLoginEnabled,
      notificationsEnabled: notificationsAllowed,
    );
  }

  Future<void> revokeForCurrentUser() async {
    if (Supabase.instance.client.auth.currentSession == null) {
      return;
    }

    final firebaseReady = await ensureFirebaseInitialized();
    if (!firebaseReady) {
      return;
    }

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      token = null;
    }

    final deviceId = await _loadOrCreateDeviceId();

    try {
      await Supabase.instance.client.rpc(
        'revoke_push_token',
        params: <String, dynamic>{
          'target_fcm_token': token,
          'target_device_id': deviceId,
        },
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Nao foi possivel revogar token FCM: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      _registrationEnabled = false;
    }
  }

  Future<NotificationSettings> _requestPermission(
    FirebaseMessaging messaging,
  ) async {
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (kDebugMode) {
        debugPrint('Permissao FCM: ${settings.authorizationStatus.name}');
      }
      return settings;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Nao foi possivel solicitar permissao FCM: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return const NotificationSettings(
        authorizationStatus: AuthorizationStatus.denied,
        alert: AppleNotificationSetting.disabled,
        announcement: AppleNotificationSetting.disabled,
        badge: AppleNotificationSetting.disabled,
        carPlay: AppleNotificationSetting.disabled,
        criticalAlert: AppleNotificationSetting.disabled,
        lockScreen: AppleNotificationSetting.disabled,
        notificationCenter: AppleNotificationSetting.disabled,
        providesAppNotificationSettings: AppleNotificationSetting.disabled,
        showPreviews: AppleShowPreviewSetting.never,
        sound: AppleNotificationSetting.disabled,
        timeSensitive: AppleNotificationSetting.disabled,
      );
    }
  }

  Future<void> _registerToken({
    required String? token,
    required bool rememberLoginEnabled,
    required bool notificationsEnabled,
  }) async {
    if (token == null || token.trim().isEmpty) {
      return;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.buildNumber.trim().isEmpty
          ? packageInfo.version
          : '${packageInfo.version}+${packageInfo.buildNumber}';
      final response = await Supabase.instance.client.rpc(
        'register_push_token',
        params: <String, dynamic>{
          'target_fcm_token': token,
          'target_device_id': await _loadOrCreateDeviceId(),
          'target_platform': Platform.operatingSystem,
          'target_app_version': appVersion,
          'target_remember_login_enabled': rememberLoginEnabled,
          'target_notifications_enabled': notificationsEnabled,
        },
      );

      if (kDebugMode) {
        debugPrint('Token FCM atual: $token');
        debugPrint('Registro push: $response');
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Nao foi possivel registrar token FCM: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  void _handleTokenRefresh(String token) {
    if (kDebugMode) {
      debugPrint('Token FCM atualizado: $token');
    }

    if (!_registrationEnabled || !_profileAllowsPush) {
      return;
    }

    unawaited(
      _registerToken(
        token: token,
        rememberLoginEnabled: true,
        notificationsEnabled: true,
      ),
    );
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint(
        'FCM foreground message received: ${message.messageId ?? '(sem id)'}',
      );
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('Notificacao FCM aberta: ${message.messageId ?? '(sem id)'}');
    }

    final intent = PushNavigationIntent.fromMessage(message);
    if (intent.module.trim().isEmpty) {
      return;
    }

    _pendingNavigationIntent = intent;
    if (!_navigationController.isClosed) {
      _navigationController.add(intent);
    }
  }

  static bool _isPushProfile(String profileSlug) {
    return profileSlug == 'vendedor' ||
        profileSlug == 'supervisor' ||
        profileSlug == 'coordenador';
  }

  static Future<String> _loadOrCreateDeviceId() async {
    final existing = await _secureStorage.read(key: _deviceIdStorageKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final deviceId = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    await _secureStorage.write(key: _deviceIdStorageKey, value: deviceId);
    return deviceId;
  }
}
