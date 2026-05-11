class BiModuleFilterInput {
  const BiModuleFilterInput({
    this.id,
    required this.filterTable,
    required this.filterColumn,
    this.label,
  });

  final String? id;
  final String filterTable;
  final String filterColumn;
  final String? label;
}
