/// A kind of release a publisher puts out: "Standard Edition", "Omnibus
/// Edition", a deluxe or box-set line, and so on.
///
/// Editions are a shared vocabulary rather than something owned by one
/// publisher - collections point at one by name - so this is a plain
/// reference list.
class Edition {
  final String id;
  final String name;
  final String description;

  const Edition({required this.id, required this.name, this.description = ''});

  factory Edition.fromJson(Map<String, dynamic> json) => Edition(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
  );
}
