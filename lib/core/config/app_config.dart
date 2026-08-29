class AppConfig {
  static const aiApiBaseUrl = String.fromEnvironment(
    'AI_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const tariffAdminKey = String.fromEnvironment(
    'TARIFF_ADMIN_KEY',
    defaultValue: '',
  );
}
