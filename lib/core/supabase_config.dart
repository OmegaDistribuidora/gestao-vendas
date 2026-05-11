class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ewkexlyywmvufbirmpot.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_vQyCQEU5hh_HHMRAy798Ig_Pwfiox9U',
  );

  static bool get isConfigured =>
      url.isNotEmpty && publishableKey.isNotEmpty;
}
