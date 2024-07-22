class Setting {
  final int? id;
  final String title;
  final String value;
  final String projectId;

  const Setting({
    required this.title,
    required this.value,
    required this.projectId,
    this.id
  });

  factory Setting.fromJson(Map<String, dynamic> json) => Setting(
    id: json['id'],
    title: json['title'],
    value: json['value'],
    projectId: json['projectId'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'value': value,
    'projectId': projectId,
  };
}
