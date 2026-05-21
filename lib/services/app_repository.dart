import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/blocked_orders_overview.dart';
import '../models/delinquency_overview.dart';
import '../models/kpi_metric_source.dart';
import '../models/performance_overview.dart';
import '../models/remembered_login.dart';
import '../models/return_analysis.dart';
import '../models/seller_home_kpis.dart';
import '../models/supplier_analysis.dart';
import '../models/usage_report.dart';
import 'remembered_login_store.dart';

class AppRepository {
  AppRepository._({
    RememberedLoginStore rememberedLoginStore =
        const SecureRememberedLoginStore(),
  }) : _rememberedLoginStore = rememberedLoginStore;

  static AppRepository instance = AppRepository._();

  final RememberedLoginStore _rememberedLoginStore;

  static const String technicalDomain = 'app.omegadistribuidora.com.br';

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> initialize() async {
    if (!SupabaseConfig.isConfigured) {
      throw const RepositoryException(
        'Configuração do Supabase ausente. Defina SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY.',
      );
    }
  }

  Future<RememberedLogin?> loadRememberedLogin() {
    return _rememberedLoginStore.load();
  }

  Future<void> saveRememberedLogin({
    required String identifier,
    required bool rememberLogin,
  }) async {
    if (!rememberLogin) {
      await clearRememberedLogin();
      return;
    }

    await _rememberedLoginStore.save(
      RememberedLogin(identifier: identifier.trim(), rememberLogin: true),
    );
  }

  Future<void> clearRememberedLogin() {
    return _rememberedLoginStore.clear();
  }

  Future<AppUser?> restoreSession() async {
    if (_supabase.auth.currentSession == null) {
      return null;
    }

    try {
      return await _loadCurrentUser(enforceActive: true);
    } on RepositoryException {
      await _supabase.auth.signOut();
      return null;
    }
  }

  Future<AppUser> authenticate({
    required String login,
    required String password,
  }) async {
    final identifier = login.trim();
    final loginContext = await _resolveLoginContext(identifier);
    final technicalEmail = loginContext?.technicalEmail;

    if (loginContext?.requiresAdminPasswordDefinition == true) {
      throw const RepositoryException(
        'Sua senha ainda precisa ser definida pelo administrador. Entre em contato com a equipe comercial.',
      );
    }

    if (technicalEmail == null || technicalEmail.isEmpty) {
      throw const RepositoryException('Identificador ou senha inválidos.');
    }

    try {
      await _signInWithPassword(email: technicalEmail, password: password);
    } on AuthException {
      final sellerFallbackPassword = _buildSellerFallbackPassword(
        identifier,
        password,
      );
      if (sellerFallbackPassword == null) {
        throw const RepositoryException('Identificador ou senha inválidos.');
      }

      try {
        await _signInWithPassword(
          email: technicalEmail,
          password: sellerFallbackPassword,
        );
      } on AuthException {
        throw const RepositoryException('Identificador ou senha inválidos.');
      }
    } catch (error) {
      if (_isTransientNetworkError(error)) {
        throw const RepositoryException(
          'Falha temporÃ¡ria de conexÃ£o ao autenticar. Tente novamente.',
        );
      }
      rethrow;
    }

    late final AppUser user;
    try {
      user = await _loadCurrentUser(enforceActive: true);
    } catch (error) {
      await _supabase.auth.signOut();
      rethrow;
    }

    await _recordLoginEventSafely(user);
    return user;
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<AppUser> changeMyPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final authUser = _supabase.auth.currentUser;
    final email = authUser?.email;
    if (authUser == null || email == null || email.isEmpty) {
      throw const RepositoryException('Nenhuma sessão ativa encontrada.');
    }

    final currentUser = await _loadCurrentUser(enforceActive: true);

    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException {
      final sellerFallbackPassword =
          currentUser.profileSlug == AppProfile.sellerSlug
          ? _buildSellerFallbackPassword(currentUser.code, currentPassword)
          : null;

      if (sellerFallbackPassword == null) {
        throw const RepositoryException('A senha atual está incorreta.');
      }

      try {
        await _supabase.auth.signInWithPassword(
          email: email,
          password: sellerFallbackPassword,
        );
      } on AuthException {
        throw const RepositoryException('A senha atual está incorreta.');
      }
    }

    await _supabase.auth.updateUser(
      UserAttributes(password: newPassword.trim()),
    );
    await _supabase
        .from('app_users')
        .update(<String, dynamic>{
          'requires_admin_password_definition': false,
          'credentials_updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('auth_user_id', authUser.id);

    await _supabase.auth.signOut();
    await _supabase.auth.signInWithPassword(
      email: email,
      password: newPassword.trim(),
    );

    return _loadCurrentUser(enforceActive: true);
  }

  Future<List<AppProfile>> getProfiles() async {
    final data = await _supabase
        .from('app_profiles')
        .select()
        .order('is_system', ascending: false)
        .order('name');

    return data
        .whereType<Map>()
        .map((row) => AppProfile.fromJson(_stringKeyedMap(row)))
        .toList();
  }

  Future<AppProfile> createProfile({
    required String name,
    required String slug,
  }) async {
    final row = await _supabase
        .from('app_profiles')
        .insert(<String, dynamic>{
          'name': name.trim(),
          'slug': _normalizeSlug(slug),
        })
        .select()
        .single();

    return AppProfile.fromJson(_stringKeyedMap(row));
  }

  Future<AppProfile> updateProfile({
    required String profileId,
    required String name,
    required String slug,
  }) async {
    final row = await _supabase
        .from('app_profiles')
        .update(<String, dynamic>{
          'name': name.trim(),
          'slug': _normalizeSlug(slug),
        })
        .eq('id', profileId)
        .select()
        .single();

    return AppProfile.fromJson(_stringKeyedMap(row));
  }

  Future<void> deleteProfile(String profileId) async {
    await _supabase.rpc(
      'delete_app_profile',
      params: <String, dynamic>{'target_profile_id': profileId},
    );
  }

  Future<List<AppUser>> getUsers() async {
    final profilesById = await _loadProfilesById();
    final data = await _supabase.from('app_users').select().order('code');

    return data.whereType<Map>().map((row) {
      final mapped = _stringKeyedMap(row);
      return _mapUser(mapped, profilesById);
    }).toList();
  }

  Future<AppUser> createUser({
    required String code,
    required String password,
    required String displayName,
    String? loginAlias,
    required String profileId,
    required bool isActive,
  }) async {
    final result = await _invokeAdminUsersFunction(<String, dynamic>{
      'action': 'create',
      'code': code.trim(),
      'password': password.trim(),
      'displayName': displayName.trim(),
      'loginAlias': loginAlias?.trim(),
      'profileId': profileId,
      'isActive': isActive,
    });

    final userData = result['user'];
    if (userData is! Map) {
      throw const RepositoryException(
        'A função administrativa não retornou o usuário criado.',
      );
    }

    final profilesById = await _loadProfilesById();
    return _mapUser(_stringKeyedMap(userData), profilesById);
  }

  Future<AppUser> updateUser({
    required String userId,
    required String code,
    required String displayName,
    String? loginAlias,
    required String profileId,
    required bool isActive,
    String? newPassword,
  }) async {
    final result = await _invokeAdminUsersFunction(<String, dynamic>{
      'action': 'update',
      'userId': userId,
      'code': code.trim(),
      'displayName': displayName.trim(),
      'loginAlias': loginAlias?.trim(),
      'profileId': profileId,
      'isActive': isActive,
      'newPassword': newPassword?.trim().isEmpty ?? true
          ? null
          : newPassword?.trim(),
    });

    final userData = result['user'];
    if (userData is! Map) {
      throw const RepositoryException(
        'A função administrativa não retornou o usuário atualizado.',
      );
    }

    final profilesById = await _loadProfilesById();
    return _mapUser(_stringKeyedMap(userData), profilesById);
  }

  Future<void> deleteUser(String userId) async {
    await _invokeAdminUsersFunction(<String, dynamic>{
      'action': 'delete',
      'userId': userId,
    });
  }

  Future<void> deactivateOracleSellersMissingCodes({
    required Set<String> activeCodes,
  }) async {
    final sellerProfile = await _supabase
        .from('app_profiles')
        .select('id')
        .eq('slug', AppProfile.sellerSlug)
        .single();

    final sellerProfileId = sellerProfile['id'] as String;
    final rows = await _supabase
        .from('app_users')
        .select('auth_user_id, code')
        .eq('profile_id', sellerProfileId)
        .eq('origin', 'oracle_sellers');

    for (final row in rows.whereType<Map>()) {
      final mapped = _stringKeyedMap(row);
      final code = '${mapped['code'] ?? ''}'.trim();
      if (code.isEmpty || activeCodes.contains(code)) {
        continue;
      }
      await _supabase
          .from('app_users')
          .update(<String, dynamic>{'is_active': false})
          .eq('auth_user_id', mapped['auth_user_id']);
    }
  }

  Future<void> upsertOracleSellerSnapshot(AppUser user) async {
    final currentRow = await _supabase
        .from('app_users')
        .select('auth_user_id')
        .eq('auth_user_id', user.id)
        .maybeSingle();

    if (currentRow == null) {
      throw const RepositoryException('Usuário vendedor não encontrado.');
    }
  }

  Future<UsageReport> getUsageReport({
    required DateTime start,
    required DateTime end,
    String? userId,
  }) async {
    final response = await _supabase.rpc(
      'get_usage_report',
      params: <String, dynamic>{
        'window_start': start.toUtc().toIso8601String(),
        'window_end': end.toUtc().toIso8601String(),
        'target_user_id': userId,
      },
    );

    if (response is! Map) {
      return UsageReport.empty();
    }

    return UsageReport.fromJson(_stringKeyedMap(response));
  }

  Future<SellerHomeKpis> getHomeKpis({
    required DateTime start,
    required DateTime end,
    required KpiMetricSource metricSource,
  }) async {
    final response = await _supabase.rpc(
      'get_home_kpis',
      params: <String, dynamic>{
        'window_start': start.toUtc().toIso8601String(),
        'window_end': end.toUtc().toIso8601String(),
        'metric_source': metricSource.value,
      },
    );

    if (response is! Map) {
      return SellerHomeKpis.empty();
    }

    return SellerHomeKpis.fromJson(_stringKeyedMap(response));
  }

  Future<SupplierAnalysis> getSupplierAnalysis({
    required DateTime start,
    required DateTime end,
    required KpiMetricSource metricSource,
  }) async {
    final response = await _supabase.rpc(
      'get_supplier_analysis',
      params: <String, dynamic>{
        'window_start': start.toUtc().toIso8601String(),
        'window_end': end.toUtc().toIso8601String(),
        'metric_source': metricSource.value,
      },
    );

    if (response is! Map) {
      return SupplierAnalysis.empty();
    }

    return SupplierAnalysis.fromJson(_stringKeyedMap(response));
  }

  Future<PerformanceOverview> getPerformanceOverview({
    DateTime? monthStart,
    KpiMetricSource metricSource = KpiMetricSource.venda,
    String? targetScopeProfileSlug,
    String? targetScopeOwnerCode,
  }) async {
    final response = await _supabase.rpc(
      'get_performance_overview',
      params: <String, dynamic>{
        'target_month_start': monthStart?.toIso8601String().split('T').first,
        'metric_source': metricSource.value,
        'target_scope_profile_slug': targetScopeProfileSlug,
        'target_scope_owner_code': targetScopeOwnerCode,
      },
    );

    if (response is! Map) {
      return PerformanceOverview.empty();
    }

    return PerformanceOverview.fromJson(_stringKeyedMap(response));
  }

  Future<ReturnAnalysis> getReturnAnalysis({
    required DateTime start,
    required DateTime end,
  }) async {
    final response = await _supabase.rpc(
      'get_return_analysis',
      params: <String, dynamic>{
        'window_start': start.toUtc().toIso8601String(),
        'window_end': end.toUtc().toIso8601String(),
      },
    );

    if (response is! Map) {
      return ReturnAnalysis.empty();
    }

    return ReturnAnalysis.fromJson(_stringKeyedMap(response));
  }

  Future<DelinquencyOverview> getDelinquencyOverview({
    String? targetScopeProfileSlug,
    String? targetScopeOwnerCode,
  }) async {
    final response = await _supabase.rpc(
      'get_delinquency_overview',
      params: <String, dynamic>{
        'target_scope_profile_slug': targetScopeProfileSlug,
        'target_scope_owner_code': targetScopeOwnerCode,
      },
    );

    if (response is! Map) {
      return DelinquencyOverview.empty();
    }

    return DelinquencyOverview.fromJson(_stringKeyedMap(response));
  }

  Future<BlockedOrdersOverview> getBlockedOrdersOverview() async {
    final response = await _supabase.rpc('get_blocked_orders_overview');

    if (response is! Map) {
      return BlockedOrdersOverview.empty();
    }

    return BlockedOrdersOverview.fromJson(_stringKeyedMap(response));
  }

  Future<List<ReturnOrderDetail>> getReturnOrderDetails({
    required DateTime returnDate,
    required String orderNumber,
  }) async {
    final response = await _supabase.rpc(
      'get_return_order_details',
      params: <String, dynamic>{
        'target_return_date': returnDate.toIso8601String().split('T').first,
        'target_order_number': orderNumber,
      },
    );

    if (response is! Map) {
      return const <ReturnOrderDetail>[];
    }

    final items = response['items'];
    if (items is! List) {
      return const <ReturnOrderDetail>[];
    }

    return items
        .whereType<Map>()
        .map(
          (row) => ReturnOrderDetail.fromJson(
            row.map((key, value) => MapEntry('$key', value)),
          ),
        )
        .toList();
  }

  String buildTechnicalEmail(String code) {
    final normalizedCode = code.trim().toLowerCase();
    return '$normalizedCode@$technicalDomain';
  }

  String? _buildSellerFallbackPassword(String identifier, String password) {
    final trimmedIdentifier = identifier.trim();
    final trimmedPassword = password.trim();
    final isNumericCode = RegExp(r'^\d+$').hasMatch(trimmedIdentifier);
    if (!isNumericCode || trimmedPassword.length != 3) {
      return null;
    }
    return '$trimmedPassword$trimmedPassword';
  }

  Future<AppUser> _loadCurrentUser({required bool enforceActive}) async {
    final authUser = _supabase.auth.currentUser;
    if (authUser == null) {
      throw const RepositoryException('Nenhuma sessão ativa encontrada.');
    }

    final row = await _supabase
        .from('app_users')
        .select()
        .eq('auth_user_id', authUser.id)
        .maybeSingle();

    if (row == null) {
      throw const RepositoryException(
        'O usuário autenticado ainda não possui perfil no app.',
      );
    }

    final credentialsUpdatedAt = _parseDateTimeValue(
      row['credentials_updated_at'],
    );
    final sessionIssuedAt = _currentSessionIssuedAt();
    final sessionInvalidated =
        enforceActive &&
        credentialsUpdatedAt != null &&
        sessionIssuedAt != null &&
        credentialsUpdatedAt.toUtc().isAfter(
          sessionIssuedAt.toUtc().add(const Duration(seconds: 1)),
        );

    if (sessionInvalidated) {
      await _supabase.auth.signOut();
      throw const RepositoryException(
        'Sua sessão foi invalidada. Faça login novamente.',
      );
    }

    final profilesById = await _loadProfilesById();
    final user = _mapUser(_stringKeyedMap(row), profilesById);

    if (enforceActive && !user.isActive) {
      await _supabase.auth.signOut();
      throw const RepositoryException(
        'Usuário inativo. Procure o administrador.',
      );
    }

    if (enforceActive && user.requiresAdminPasswordDefinition) {
      await _supabase.auth.signOut();
      throw const RepositoryException(
        'Sua senha ainda precisa ser definida pelo administrador. Entre em contato com a equipe comercial.',
      );
    }

    return user;
  }

  Future<void> _recordLoginEvent(AppUser user) async {
    await _supabase.from('app_login_events').insert(<String, dynamic>{
      'user_id': user.id,
      'profile_slug': user.profileSlug,
      'logged_in_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _recordLoginEventSafely(AppUser user) async {
    try {
      await _runWithTransientRetry<void>(() => _recordLoginEvent(user));
    } catch (_) {
      // O login do usuario nao deve falhar por indisponibilidade da telemetria.
    }
  }

  Future<_ResolvedLoginContext?> _resolveLoginContext(String identifier) async {
    try {
      final response = await _runWithTransientRetry<dynamic>(
        () => _supabase.rpc(
          'resolve_login_context',
          params: <String, dynamic>{'login_identifier': identifier},
        ),
      );

      if (response is Map) {
        final mapped = _stringKeyedMap(response);
        final technicalEmail = '${mapped['technical_email'] ?? ''}'.trim();
        if (technicalEmail.isEmpty) {
          return null;
        }
        return _ResolvedLoginContext(
          technicalEmail: technicalEmail,
          requiresAdminPasswordDefinition:
              mapped['requires_admin_password_definition'] as bool? ?? false,
        );
      }
      return null;
    } on PostgrestException catch (error) {
      if (error.message.toLowerCase().contains('duplicado')) {
        throw const RepositoryException(
          'O identificador informado está duplicado. Ajuste esse usuário na administração.',
        );
      }
      throw RepositoryException(error.message);
    } catch (error) {
      if (_isTransientNetworkError(error)) {
        throw const RepositoryException(
          'Falha temporÃ¡ria de conexÃ£o ao validar o login. Tente novamente.',
        );
      }
      rethrow;
    }
  }

  Future<void> _signInWithPassword({
    required String email,
    required String password,
  }) {
    return _runWithTransientRetry<void>(() async {
      await _supabase.auth.signInWithPassword(email: email, password: password);
    });
  }

  Future<Map<String, AppProfile>> _loadProfilesById() async {
    final profiles = await getProfiles();
    return <String, AppProfile>{
      for (final profile in profiles) profile.id: profile,
    };
  }

  AppUser _mapUser(
    Map<String, dynamic> row,
    Map<String, AppProfile> profilesById,
  ) {
    final profileId = row['profile_id'] as String?;
    return AppUser.fromJson(<String, dynamic>{
      ...row,
      'profile': profileId == null ? null : profilesById[profileId]?.toJson(),
    });
  }

  Future<Map<String, dynamic>> _invokeAdminUsersFunction(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _supabase.functions.invoke(
        'admin-users',
        body: payload,
      );

      final data = response.data;
      if (data is Map) {
        return _stringKeyedMap(data);
      }

      return const <String, dynamic>{};
    } on FunctionException catch (error) {
      throw RepositoryException(
        error.details?.toString() ??
            'Falha ao executar a função administrativa do Supabase.',
      );
    } catch (error) {
      throw RepositoryException(
        'Falha ao executar a função administrativa do Supabase.\n$error',
      );
    }
  }

  String _normalizeSlug(String rawValue) {
    final lower = rawValue.trim().toLowerCase();
    return lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> source) {
    return source.map((key, value) => MapEntry('$key', value));
  }

  DateTime? _parseDateTimeValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  DateTime? _currentSessionIssuedAt() {
    final accessToken = _supabase.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    final parts = accessToken.split('.');
    if (parts.length < 2) {
      return null;
    }

    try {
      final normalizedPayload = base64Url.normalize(parts[1]);
      final payloadJson = utf8.decode(base64Url.decode(normalizedPayload));
      final payload = jsonDecode(payloadJson);
      if (payload is Map<String, dynamic>) {
        final issuedAtSeconds = payload['iat'];
        if (issuedAtSeconds is num) {
          return DateTime.fromMillisecondsSinceEpoch(
            issuedAtSeconds.toInt() * 1000,
            isUtc: true,
          );
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<T> _runWithTransientRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 2,
    Duration retryDelay = const Duration(milliseconds: 350),
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (error, stackTrace) {
        final shouldRetry =
            _isTransientNetworkError(error) && attempt < maxAttempts;
        if (!shouldRetry) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        await Future<void>.delayed(retryDelay);
      }
    }

    throw StateError('Retry loop finalizado sem retorno.');
  }

  bool _isTransientNetworkError(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('connection reset by peer') ||
        message.contains('connection closed before full header was received') ||
        message.contains('software caused connection abort') ||
        message.contains('temporarily unavailable') ||
        message.contains('timed out');
  }
}

class RepositoryException implements Exception {
  const RepositoryException(this.message);

  final String message;
}

class _ResolvedLoginContext {
  const _ResolvedLoginContext({
    required this.technicalEmail,
    required this.requiresAdminPasswordDefinition,
  });

  final String technicalEmail;
  final bool requiresAdminPasswordDefinition;
}
