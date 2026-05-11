class RememberedLogin {
  const RememberedLogin({
    required this.identifier,
    required this.rememberLogin,
  });

  final String identifier;
  final bool rememberLogin;

  factory RememberedLogin.fromJson(Map<String, dynamic> json) {
    return RememberedLogin(
      identifier:
          json['identifier'] as String? ??
          json['code'] as String? ??
          json['login'] as String? ??
          '',
      rememberLogin: json['rememberLogin'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'identifier': identifier,
      'rememberLogin': rememberLogin,
    };
  }
}
