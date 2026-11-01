import 'package:devcat/core/mascot_appearance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v5 evolution boundaries are exact, with architect starting at 101', () {
    const cases = <int, MascotEvolution>{
      1: MascotEvolution.beginner,
      10: MascotEvolution.beginner,
      11: MascotEvolution.student,
      25: MascotEvolution.student,
      26: MascotEvolution.developer,
      50: MascotEvolution.developer,
      51: MascotEvolution.middle,
      75: MascotEvolution.middle,
      76: MascotEvolution.senior,
      100: MascotEvolution.senior,
      101: MascotEvolution.architect,
      999: MascotEvolution.architect,
    };
    for (final entry in cases.entries) {
      expect(MascotEvolution.forLevel(entry.key), entry.value);
    }
    expect(() => MascotEvolution.forLevel(0), throwsRangeError);
    expect(() => MascotEvolution.forLevel(-1), throwsRangeError);
  });

  test('equipping a costume does not change earned evolution or level', () {
    const original = MascotAppearanceSelection(level: 100);
    final pirate = original.equip(MascotCostume.pirate);
    expect(original.appearanceId, 'senior');
    expect(pirate.appearanceId, 'pirate');
    expect(pirate.level, 100);
    expect(pirate.earnedEvolution, MascotEvolution.senior);

    final promoted = pirate.withLevel(101);
    expect(promoted.earnedEvolution, MascotEvolution.architect);
    expect(promoted.appearanceId, 'pirate');
    expect(promoted.equip(null).appearanceId, 'architect');
  });

  test('all 15 display IDs are distinct', () {
    final names = <String>{
      ...MascotEvolution.values.map((stage) => stage.name),
      ...MascotCostume.values.map((costume) => costume.name),
    };
    expect(names.length, 15);
  });
}
