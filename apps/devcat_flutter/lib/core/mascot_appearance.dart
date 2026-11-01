/// Canonical appearance IDs and level thresholds for the DevCat v5 mascot.
///
/// Progress determines [MascotEvolution]. A selected cosmetic costume is a
/// separate preference and never modifies the user's earned level.
enum MascotEvolution {
  beginner(1, 10),
  student(11, 25),
  developer(26, 50),
  middle(51, 75),
  senior(76, 100),
  architect(101, null);

  const MascotEvolution(this.minLevel, this.maxLevel);

  final int minLevel;
  final int? maxLevel;

  static MascotEvolution forLevel(int level) {
    if (level < 1) {
      throw RangeError.range(level, 1, null, 'level');
    }
    for (final stage in MascotEvolution.values) {
      if (level >= stage.minLevel &&
          (stage.maxLevel == null || level <= stage.maxLevel!)) {
        return stage;
      }
    }
    throw StateError('Evolution bounds do not cover level $level');
  }
}

enum MascotCostume {
  space,
  hacker,
  samurai,
  winter,
  mage,
  engineer,
  pirate,
  cyberpunk,
  scientist,
}

/// Display-only choice; [level] is never changed by equipping a costume.
class MascotAppearanceSelection {
  const MascotAppearanceSelection({required this.level, this.costume})
    : assert(level >= 1);

  final int level;
  final MascotCostume? costume;

  MascotEvolution get earnedEvolution => MascotEvolution.forLevel(level);

  /// Maps to v5 model names. No assumption of an animated costume pack.
  String get appearanceId => costume?.name ?? earnedEvolution.name;

  MascotAppearanceSelection equip(MascotCostume? selected) =>
      MascotAppearanceSelection(level: level, costume: selected);

  MascotAppearanceSelection withLevel(int updatedLevel) =>
      MascotAppearanceSelection(level: updatedLevel, costume: costume);
}
