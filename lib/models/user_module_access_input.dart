class UserModuleAccessInput {
  const UserModuleAccessInput({
    required this.moduleId,
    required this.hasFilteredData,
    required this.filterValues,
  });

  final String moduleId;
  final bool hasFilteredData;
  final Map<String, String> filterValues;
}
