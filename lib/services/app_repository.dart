import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/bi_module.dart';
import '../models/bi_module_filter_input.dart';
import '../models/remembered_login.dart';
import '../models/seller_home_kpis.dart';
import '../models/usage_report.dart';
import '../models/user_module_access.dart';
import '../models/user_module_access_input.dart';
import 'remembered_login_store.dart';

class AppRepository {
  AppRepository._({
    RememberedLoginStore rememberedLoginStore =
        const SecureRememberedLoginStore(),
  }) : _rememberedLoginStore = rememberedLoginStore;

  static AppRepository instance = AppRepository._();

  final RememberedLoginStore _rememberedLoginStore;

  static const String technicalDomain = 'app.omegadistribuidora.com.br';
  static const String _moduleFiltersSelect =
      'filters:app_module_filters!app_module_filters_module_id_fkey(*)';

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
      await _supabase.auth.signInWithPassword(
        email: technicalEmail,
        password: password,
      );
    } on AuthException {
      throw const RepositoryException('Identificador ou senha inválidos.');
    }

    try {
      final user = await _loadCurrentUser(enforceActive: true);
      await _recordLoginEvent(user);
      return user;
    } catch (error) {
      await _supabase.auth.signOut();
      rethrow;
    }
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

    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException {
      throw const RepositoryException('A senha atual está incorreta.');
    }

    await _supabase.auth.updateUser(
      UserAttributes(password: newPassword.trim()),
    );
    await _supabase
        .from('app_users')
        .update(<String, dynamic>{'requires_admin_password_definition': false})
        .eq('auth_user_id', authUser.id);

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
    List<UserModuleAccessInput> initialAccesses =
        const <UserModuleAccessInput>[],
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
    final createdUser = _mapUser(_stringKeyedMap(userData), profilesById);

    if (initialAccesses.isNotEmpty) {
      await replaceUserModuleAccesses(
        userId: createdUser.id,
        accesses: initialAccesses,
      );
    }

    return createdUser;
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

  Future<List<BiModule>> getBiModules({bool onlyActive = false}) async {
    var query = _supabase
        .from('app_modules')
        .select('*, $_moduleFiltersSelect');
    if (onlyActive) {
      query = query.eq('is_active', true);
    }

    final data = await query.order('name');
    return data
        .whereType<Map>()
        .map((row) => _mapModule(_stringKeyedMap(row)))
        .toList();
  }

  Future<BiModule> createBiModule({
    required String name,
    required String panelUrl,
    required List<BiModuleFilterInput> filters,
    required bool isActive,
  }) async {
    final firstFilter = filters.isEmpty ? null : filters.first;
    final row = await _supabase
        .from('app_modules')
        .insert(<String, dynamic>{
          'name': name.trim(),
          'panel_url': panelUrl.trim(),
          'filter_table': firstFilter?.filterTable.trim() ?? '',
          'filter_column': firstFilter?.filterColumn.trim() ?? '',
          'is_active': isActive,
        })
        .select()
        .single();

    final moduleId = row['id'] as String;
    await _replaceModuleFilters(moduleId: moduleId, filters: filters);
    return getBiModuleById(moduleId);
  }

  Future<BiModule> updateBiModule({
    required String moduleId,
    required String name,
    required String panelUrl,
    required List<BiModuleFilterInput> filters,
    required bool isActive,
  }) async {
    final firstFilter = filters.isEmpty ? null : filters.first;
    await _supabase
        .from('app_modules')
        .update(<String, dynamic>{
          'name': name.trim(),
          'panel_url': panelUrl.trim(),
          'filter_table': firstFilter?.filterTable.trim() ?? '',
          'filter_column': firstFilter?.filterColumn.trim() ?? '',
          'is_active': isActive,
        })
        .eq('id', moduleId);

    await _replaceModuleFilters(moduleId: moduleId, filters: filters);
    return getBiModuleById(moduleId);
  }

  Future<void> setModuleSellerDefaultFilter({
    required String moduleId,
    String? sellerDefaultFilterId,
  }) async {
    await _supabase
        .from('app_modules')
        .update(<String, dynamic>{
          'seller_default_filter_id': sellerDefaultFilterId,
        })
        .eq('id', moduleId);
  }

  Future<void> deleteBiModule(String moduleId) async {
    await _supabase.from('app_modules').delete().eq('id', moduleId);
  }

  Future<BiModule> getBiModuleById(String moduleId) async {
    final row = await _supabase
        .from('app_modules')
        .select('*, $_moduleFiltersSelect')
        .eq('id', moduleId)
        .single();

    return _mapModule(_stringKeyedMap(row));
  }

  Future<List<UserModuleAccess>> getUserModuleAccesses() async {
    final data = await _supabase
        .from('app_user_module_accesses')
        .select(
          '*, filter_values:app_user_module_filter_values(*, module_filter:app_module_filters(*))',
        )
        .order('created_at');

    return data
        .whereType<Map>()
        .map((row) => UserModuleAccess.fromJson(_stringKeyedMap(row)))
        .toList();
  }

  Future<List<UserModuleAccess>> getUserModuleAccessesForModule(
    String moduleId,
  ) async {
    final data = await _supabase
        .from('app_user_module_accesses')
        .select(
          '*, filter_values:app_user_module_filter_values(*, module_filter:app_module_filters(*))',
        )
        .eq('module_id', moduleId)
        .order('created_at');

    return data
        .whereType<Map>()
        .map((row) => UserModuleAccess.fromJson(_stringKeyedMap(row)))
        .toList();
  }

  Future<UserModuleAccess> createUserModuleAccess({
    required String userId,
    required String moduleId,
    required bool hasFilteredData,
    required Map<String, String> filterValues,
  }) async {
    final row = await _supabase
        .from('app_user_module_accesses')
        .insert(<String, dynamic>{
          'user_id': userId,
          'module_id': moduleId,
          'has_filtered_data': hasFilteredData,
          'filter_value': _firstLegacyFilterValue(filterValues),
        })
        .select()
        .single();

    final accessId = row['id'] as String;
    await _replaceAccessFilterValues(
      accessId: accessId,
      filterValues: filterValues,
    );

    return getUserModuleAccessById(accessId);
  }

  Future<UserModuleAccess> updateUserModuleAccess({
    required String accessId,
    required String userId,
    required String moduleId,
    required bool hasFilteredData,
    required Map<String, String> filterValues,
  }) async {
    await _supabase
        .from('app_user_module_accesses')
        .update(<String, dynamic>{
          'user_id': userId,
          'module_id': moduleId,
          'has_filtered_data': hasFilteredData,
          'filter_value': _firstLegacyFilterValue(filterValues),
        })
        .eq('id', accessId);

    await _replaceAccessFilterValues(
      accessId: accessId,
      filterValues: filterValues,
    );

    return getUserModuleAccessById(accessId);
  }

  Future<void> deleteUserModuleAccess(String accessId) async {
    await _supabase
        .from('app_user_module_accesses')
        .delete()
        .eq('id', accessId);
  }

  Future<void> replaceUserModuleAccesses({
    required String userId,
    required List<UserModuleAccessInput> accesses,
  }) async {
    final existingRows = await _supabase
        .from('app_user_module_accesses')
        .select('id')
        .eq('user_id', userId);

    for (final row in existingRows.whereType<Map>()) {
      final accessId = row['id'] as String?;
      if (accessId != null && accessId.isNotEmpty) {
        await deleteUserModuleAccess(accessId);
      }
    }

    for (final access in accesses) {
      await createUserModuleAccess(
        userId: userId,
        moduleId: access.moduleId,
        hasFilteredData: access.hasFilteredData,
        filterValues: access.filterValues,
      );
    }
  }

  Future<void> syncModuleAllowedUsers({
    required String moduleId,
    required Iterable<AppUser> allowedUsers,
    String? sellerDefaultFilterId,
  }) async {
    final desiredUsers = allowedUsers.toList();
    final desiredUserIds = desiredUsers.map((item) => item.id).toSet();
    final existingAccesses = await getUserModuleAccessesForModule(moduleId);
    final existingByUserId = <String, UserModuleAccess>{
      for (final access in existingAccesses) access.userId: access,
    };

    for (final access in existingAccesses) {
      if (!desiredUserIds.contains(access.userId)) {
        await deleteUserModuleAccess(access.id);
      }
    }

    for (final user in desiredUsers) {
      final existingAccess = existingByUserId[user.id];
      final sellerFilterId = sellerDefaultFilterId?.trim();
      final shouldApplySellerDefault =
          user.profileSlug == AppProfile.sellerSlug &&
          sellerFilterId != null &&
          sellerFilterId.isNotEmpty;

      if (existingAccess == null) {
        final filterValues = shouldApplySellerDefault
            ? <String, String>{sellerFilterId: user.code}
            : const <String, String>{};
        await createUserModuleAccess(
          userId: user.id,
          moduleId: moduleId,
          hasFilteredData: shouldApplySellerDefault,
          filterValues: filterValues,
        );
        continue;
      }

      final hasExistingValues = existingAccess.filterValues.any(
        (item) => item.filterValue.trim().isNotEmpty,
      );
      if (shouldApplySellerDefault &&
          !existingAccess.hasFilteredData &&
          !hasExistingValues) {
        await updateUserModuleAccess(
          accessId: existingAccess.id,
          userId: existingAccess.userId,
          moduleId: existingAccess.moduleId,
          hasFilteredData: true,
          filterValues: <String, String>{sellerFilterId: user.code},
        );
      }
    }
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

  Future<void> deleteUserModuleAccessesForUsers(
    Iterable<String> userIds,
  ) async {
    for (final userId in userIds) {
      final rows = await _supabase
          .from('app_user_module_accesses')
          .select('id')
          .eq('user_id', userId);
      for (final row in rows.whereType<Map>()) {
        final mapped = _stringKeyedMap(row);
        final accessId = mapped['id'] as String?;
        if (accessId != null && accessId.isNotEmpty) {
          await deleteUserModuleAccess(accessId);
        }
      }
    }
  }

  Future<void> deleteAccessByUserAndModule({
    required String userId,
    required String moduleId,
  }) async {
    final access = await getAccessForUserModule(userId, moduleId);
    if (access != null) {
      await deleteUserModuleAccess(access.id);
    }
  }

  Future<void> syncModuleAllowedUserIds({
    required String moduleId,
    required Iterable<String> allowedUserIds,
  }) async {
    final users = await getUsers();
    final allowedUserIdSet = allowedUserIds.toSet();
    await syncModuleAllowedUsers(
      moduleId: moduleId,
      allowedUsers: users.where((user) => allowedUserIdSet.contains(user.id)),
    );
  }

  Future<void> syncModuleAllowedUsersBySellerDefaults({
    required String moduleId,
    required Iterable<AppUser> allowedUsers,
    String? sellerDefaultFilterId,
  }) {
    return syncModuleAllowedUsers(
      moduleId: moduleId,
      allowedUsers: allowedUsers,
      sellerDefaultFilterId: sellerDefaultFilterId,
    );
  }

  Future<void> removeModuleUsersNotInSet({
    required String moduleId,
    required Set<String> allowedUserIds,
  }) async {
    final accesses = await getUserModuleAccessesForModule(moduleId);
    for (final access in accesses) {
      if (!allowedUserIds.contains(access.userId)) {
        await deleteUserModuleAccess(access.id);
      }
    }
  }

  Future<List<BiModule>> getModulesForUser(AppUser user) async {
    if (user.isAdmin) {
      return getBiModules(onlyActive: true);
    }

    final accessRows = await _supabase
        .from('app_user_module_accesses')
        .select('module_id')
        .eq('user_id', user.id);

    final moduleIds = accessRows
        .whereType<Map>()
        .map((row) => row['module_id'])
        .whereType<String>()
        .toList();

    if (moduleIds.isEmpty) {
      return const <BiModule>[];
    }

    final data = await _supabase
        .from('app_modules')
        .select('*, $_moduleFiltersSelect')
        .inFilter('id', moduleIds)
        .eq('is_active', true)
        .order('name');

    return data
        .whereType<Map>()
        .map((row) => _mapModule(_stringKeyedMap(row)))
        .toList();
  }

  Future<UserModuleAccess?> getAccessForUserModule(
    String userId,
    String moduleId,
  ) async {
    final row = await _supabase
        .from('app_user_module_accesses')
        .select(
          '*, filter_values:app_user_module_filter_values(*, module_filter:app_module_filters(*))',
        )
        .eq('user_id', userId)
        .eq('module_id', moduleId)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return UserModuleAccess.fromJson(_stringKeyedMap(row));
  }

  Future<UserModuleAccess> getUserModuleAccessById(String accessId) async {
    final row = await _supabase
        .from('app_user_module_accesses')
        .select(
          '*, filter_values:app_user_module_filter_values(*, module_filter:app_module_filters(*))',
        )
        .eq('id', accessId)
        .single();

    return UserModuleAccess.fromJson(_stringKeyedMap(row));
  }

  Future<String?> startModuleUsage({
    required String userId,
    required String moduleId,
  }) async {
    final row = await _supabase
        .from('app_module_usage_events')
        .insert(<String, dynamic>{'user_id': userId, 'module_id': moduleId})
        .select('id')
        .single();

    return row['id'] as String?;
  }

  Future<void> finishModuleUsage({
    required String usageEventId,
    required Duration duration,
  }) async {
    await _supabase
        .from('app_module_usage_events')
        .update(<String, dynamic>{
          'closed_at': DateTime.now().toUtc().toIso8601String(),
          'duration_seconds': duration.inSeconds,
        })
        .eq('id', usageEventId);
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
  }) async {
    final response = await _supabase.rpc(
      'get_home_kpis',
      params: <String, dynamic>{
        'window_start': start.toUtc().toIso8601String(),
        'window_end': end.toUtc().toIso8601String(),
      },
    );

    if (response is! Map) {
      return SellerHomeKpis.empty();
    }

    return SellerHomeKpis.fromJson(_stringKeyedMap(response));
  }

  String buildTechnicalEmail(String code) {
    final normalizedCode = code.trim().toLowerCase();
    return '$normalizedCode@$technicalDomain';
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

  Future<_ResolvedLoginContext?> _resolveLoginContext(String identifier) async {
    try {
      final response = await _supabase.rpc(
        'resolve_login_context',
        params: <String, dynamic>{'login_identifier': identifier},
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
    }
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

  BiModule _mapModule(Map<String, dynamic> row) {
    final module = BiModule.fromJson(row);
    final sortedFilters = [...module.filters]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return module.copyWith(filters: sortedFilters);
  }

  Future<void> _replaceModuleFilters({
    required String moduleId,
    required List<BiModuleFilterInput> filters,
  }) async {
    final sanitizedFilters = filters
        .map(
          (item) => BiModuleFilterInput(
            id: item.id,
            filterTable: item.filterTable.trim(),
            filterColumn: item.filterColumn.trim(),
            label: item.label?.trim(),
          ),
        )
        .where(
          (item) => item.filterTable.isNotEmpty && item.filterColumn.isNotEmpty,
        )
        .toList();

    if (sanitizedFilters.isEmpty) {
      await _supabase
          .from('app_module_filters')
          .delete()
          .eq('module_id', moduleId);
      return;
    }

    final existingRows = await _supabase
        .from('app_module_filters')
        .select('id')
        .eq('module_id', moduleId);
    final existingIds = existingRows
        .whereType<Map>()
        .map((row) => row['id'])
        .whereType<String>()
        .toSet();
    final keptIds = <String>{};

    for (final entry in sanitizedFilters.asMap().entries) {
      final index = entry.key;
      final filter = entry.value;
      if (filter.id != null && filter.id!.trim().isNotEmpty) {
        keptIds.add(filter.id!.trim());
        await _supabase
            .from('app_module_filters')
            .update(<String, dynamic>{
              'filter_table': filter.filterTable,
              'filter_column': filter.filterColumn,
              'label': filter.label,
              'sort_order': index,
              'is_active': true,
            })
            .eq('id', filter.id!.trim())
            .eq('module_id', moduleId);
      } else {
        final row = await _supabase
            .from('app_module_filters')
            .insert(<String, dynamic>{
              'module_id': moduleId,
              'filter_table': filter.filterTable,
              'filter_column': filter.filterColumn,
              'label': filter.label,
              'sort_order': index,
              'is_active': true,
            })
            .select('id')
            .single();
        keptIds.add(row['id'] as String);
      }
    }

    final idsToDelete = existingIds.difference(keptIds);
    for (final filterId in idsToDelete) {
      await _supabase.from('app_module_filters').delete().eq('id', filterId);
    }
  }

  Future<void> _replaceAccessFilterValues({
    required String accessId,
    required Map<String, String> filterValues,
  }) async {
    await _supabase
        .from('app_user_module_filter_values')
        .delete()
        .eq('access_id', accessId);

    final payload = filterValues.entries
        .map((entry) => MapEntry(entry.key, entry.value.trim()))
        .where((entry) => entry.value.isNotEmpty)
        .map(
          (entry) => <String, dynamic>{
            'access_id': accessId,
            'module_filter_id': entry.key,
            'filter_value': entry.value,
          },
        )
        .toList();

    if (payload.isEmpty) {
      return;
    }

    await _supabase.from('app_user_module_filter_values').insert(payload);
  }

  String _firstLegacyFilterValue(Map<String, String> filterValues) {
    for (final value in filterValues.values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
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
