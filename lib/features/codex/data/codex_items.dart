/// Static catalogue for the Codex Items tab.
///
/// We don't currently store items in Supabase — they're seeded by the AI
/// during gameplay — so the codex needs its own curated descriptions for
/// the seven illustrated items in `assets/images/items/`.
class CodexItem {
  const CodexItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.rarity,
    required this.description,
    required this.lore,
    required this.imageAsset,
  });

  final String id;
  final String name;
  final String kind;
  final String rarity;
  final String description;
  final String lore;
  final String imageAsset;
}

const kCodexItems = <CodexItem>[
  CodexItem(
    id: 'apprentices_blessing',
    name: "Apprentice's Blessing",
    kind: 'Trinket',
    rarity: 'Uncommon',
    description:
        'A frayed cord wrapped around a chip of guild-stone. Wards off the '
        'first dose of bad luck each day.',
    lore:
        'Pressed into the palms of every Mages\u2019 Tower hopeful on their '
        'naming day. Many keep the cord long after they renounce the order.',
    imageAsset: 'assets/images/items/apprentices_blessing.png',
  ),
  CodexItem(
    id: 'brass_whistle',
    name: 'Brass Whistle',
    kind: 'Tool',
    rarity: 'Common',
    description:
        'A short, sharp note carries impossibly far. Useful for signaling '
        'allies or panicking small beasts.',
    lore:
        'Standard issue for Brassmere watchmen. The pitch is tuned to a '
        'frequency the city\u2019s clockworks recognise as friendly.',
    imageAsset: 'assets/images/items/brass_whistle.png',
  ),
  CodexItem(
    id: 'hand_stitched_cloak',
    name: 'Hand-stitched Cloak',
    kind: 'Apparel',
    rarity: 'Common',
    description:
        'Light, warm, and threaded with prayers. +1 to checks made against '
        'rough weather.',
    lore:
        'Sewn by a grandmother somewhere, for someone she loved. The seams '
        'still smell faintly of woodsmoke.',
    imageAsset: 'assets/images/items/hand_stitched_cloak.png',
  ),
  CodexItem(
    id: 'healing_potion',
    name: 'Healing Potion',
    kind: 'Consumable',
    rarity: 'Common',
    description:
        'Restores 2d4+2 HP when consumed. Tastes of crushed herbs and '
        'copper coins.',
    lore:
        'Brewed in every roadside chapel between Ashfall and the coast. '
        'Some priests bless theirs; the rest just charge more.',
    imageAsset: 'assets/images/items/healing_potion.png',
  ),
  CodexItem(
    id: 'letter_of_introduction',
    name: 'Letter of Introduction',
    kind: 'Document',
    rarity: 'Uncommon',
    description:
        'A sealed letter from a name that opens doors. Persuasion checks '
        'with civic officials gain advantage while it remains unopened.',
    lore:
        'Whose seal? That depends on who handed it to you. Read carefully '
        '\u2014 some seals close more doors than they open.',
    imageAsset: 'assets/images/items/letter_of_introduction.png',
  ),
  CodexItem(
    id: 'sages_pouch',
    name: "Sage's Pouch",
    kind: 'Container',
    rarity: 'Rare',
    description:
        'Holds two extra reagents without weight. Items remembered last '
        'are the first to come to hand.',
    lore:
        'Each pouch carries a faint hum, like a library at midnight. '
        'Empty ones still rustle when no breeze moves.',
    imageAsset: 'assets/images/items/sages_pouch.png',
  ),
  CodexItem(
    id: 'singers_lyre',
    name: "Singer's Lyre",
    kind: 'Instrument',
    rarity: 'Uncommon',
    description:
        'A traveling bard\u2019s lyre. Inspires nearby allies, granting +1 '
        'to a single check per scene while it plays.',
    lore:
        'Strung with horsehair and a single strand of human hair. The '
        'previous owner sang it through three sieges and a wake.',
    imageAsset: 'assets/images/items/singers_lyre.png',
  ),
];
