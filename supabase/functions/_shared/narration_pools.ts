// Static narration pools. Used by cheap-resolve and combat-action when we want to avoid an
// LLM call (the spec calls these "static narration pools" — 5-8 phrasings per beat).
//
// Shape: a flat object keyed by canonical event slug → array of phrasings. Pick uniformly.

function pick(arr: readonly string[]): string {
  return arr[Math.floor(Math.random() * arr.length)];
}

const POOLS = {
  // ----------------- cheap-resolve: template_common, exploration -----------------
  exploration_look_around: [
    "You take a slow look around. The space is unremarkable, but you mark its corners.",
    "You sweep your eyes across the room. Nothing leaps out, but you have its shape now.",
    "You linger a moment, taking in the scene. Memorising. Calculating.",
    "You scan the area methodically. A few details register, none yet useful.",
    "Your gaze travels the walls, the floor, the ceiling — habit, not panic.",
    "You pause and let the place show itself to you. It does, slowly.",
    "You watch the way the light falls. Things hide where shadows pool.",
    "You stand still and let the world settle around you. The map clarifies.",
    "You take stock — exits, hazards, anything that does not belong. Noted.",
    "You read the room the way a hunter reads tracks. Patient.",
  ],
  exploration_search_clues: [
    "You comb the area carefully. A faint scuff in the dust, perhaps something more.",
    "You search the immediate vicinity, fingers brushing surfaces. Nothing obvious yet.",
    "You crouch and peer at the floor. A trace of something — too faint to call.",
    "You probe corners and lift the obvious things. The find, if any, is small.",
    "You spend a few minutes searching. The world reveals itself only a little.",
    "You check the seams of the place — where a thing might be hidden, if a thing was hidden.",
    "You run a finger along a ledge and come away with grit and questions.",
    "You move with care, looking for what does not match the rest.",
    "You search slowly. Slowness is its own kind of skill.",
    "You note what is missing as much as what is present. It is informative.",
  ],
  exploration_move_on: [
    "You press onward.",
    "You leave the spot behind and move on.",
    "You shoulder your pack and keep walking.",
    "You take a breath and continue.",
    "You set out for the next stretch.",
    "You commit your weight forward and the path takes you in.",
    "You trade this place for the next. Distance is a kind of safety.",
    "You walk on, the ground crunching softly beneath your boots.",
    "You leave one silence and step into another.",
    "You go. There is no good reason to stay.",
  ],
  exploration_rest_briefly: [
    "You sit a moment and let your breathing slow. It is not enough to truly rest, but the edge dulls.",
    "You take a brief pause, leaning against the cool stone. The world keeps moving.",
    "You rest a moment. Time passes; not enough.",
    "You drink a sip of water and steady your hands. Onward soon.",
    "You let yourself rest a half-minute. It is something. Barely.",
    "You close your eyes briefly. The exhaustion stays, but quiets.",
    "You stretch a knot from your shoulders and feel the day settle.",
    "You eat half a strip of dried meat and let it work.",
    "You catch your breath. The next step will come easier for it.",
    "You take stock of yourself, body before mind. Both are tired.",
  ],

  // ----------------- cheap-resolve: dialog -----------------
  dialog_ask_question: [
    "You phrase the question with care, watching for a tell.",
    "You ask, voice level.",
    "You ask plainly, leaving no room for evasion.",
    "You frame the question gently, an opening rather than a demand.",
    "You ask, and let the silence after do half the work.",
    "You speak the question slowly, giving them room to answer or refuse.",
    "You put it as a question of fact, not of feeling. Cleaner that way.",
  ],
  dialog_agree: [
    "You nod, agreement enough.",
    "You voice your assent, plain and unadorned.",
    "You agree. The other party seems to relax, slightly.",
    "You say yes. The word lands and settles.",
    "You agree without hedging. Sometimes that is the rarer kindness.",
  ],
  dialog_refuse: [
    "You shake your head once, firm. The refusal lands.",
    "You decline. The air grows a touch cooler.",
    "You refuse, careful but unambiguous.",
    "You say no. You do not soften it.",
    "You decline, and offer no reason. The reason is yours to keep.",
  ],

  // ----------------- combat: defend (cheap-resolve) -----------------
  combat_defend: [
    "You set your stance, weapon raised, weight low. The next blow will not pass cleanly.",
    "You brace. Whatever comes, you will meet it.",
    "You shift your guard up. You will weather what comes.",
    "You plant your feet and ready a deflection.",
    "You raise your guard and breathe out.",
    "You square your shoulders and watch the line of the threat.",
    "You centre your weight and let your guard speak before you do.",
    "You wait, ready, the way a stone waits for water.",
  ],

  // ----------------- combat: routine enemy attack (combat-action) -----------------
  enemy_attack_hit_aggressive: [
    "{name} surges forward and strikes you across the {limb} for {dmg} damage.",
    "{name} closes in and lands a heavy blow — {dmg} damage.",
    "{name} barrels into you, knocking you back as it deals {dmg} damage.",
    "{name} swings hard. You take {dmg} damage.",
    "{name} catches you off-guard. You feel {dmg} damage land.",
  ],
  enemy_attack_hit_tactical: [
    "{name} feints, then strikes a clean opening for {dmg} damage.",
    "{name} measures the distance and slips a precise blow past your guard — {dmg} damage.",
    "{name} watches your stance, then exploits a weakness. You take {dmg} damage.",
    "{name} times its strike. You take {dmg} damage where you least expected.",
  ],
  enemy_attack_miss: [
    "{name} swings — you slip just outside the arc.",
    "{name} attacks; you catch the blow on your guard, no damage.",
    "{name} misses. The wind of the strike passes by your face.",
    "{name} commits to a blow that finds nothing.",
    "{name} attacks, and you turn the strike aside.",
  ],
  enemy_attack_critical: [
    "{name} finds a fatal angle — {dmg} damage explodes through your guard.",
    "{name}'s blow lands precisely where it shouldn't. {dmg} damage.",
    "{name}'s strike opens a deep wound. You take {dmg} damage and stumble.",
  ],

  // ----------------- combat: routine player basic attack -----------------
  player_attack_hit: [
    "Your weapon connects, and {target} reels for {dmg} damage.",
    "You strike clean. {target} takes {dmg} damage.",
    "Your blow finds its mark — {dmg} damage to {target}.",
    "You commit and follow through. {target} takes {dmg} damage.",
  ],
  player_attack_miss: [
    "Your blow goes wide. {target} sidesteps.",
    "Your weapon meets only air.",
    "{target} parries; the blow glances away.",
    "You miss. The opening was a feint.",
  ],
  player_attack_critical: [
    "You see the opening and take it — {dmg} damage to {target}, a near-fatal strike.",
    "You bring your full weight into the blow. {dmg} damage. {target} staggers badly.",
    "A perfect strike. {target} takes {dmg} damage and barely keeps its feet.",
  ],
} as const;

export type NarrationKey = keyof typeof POOLS;

export function narrate(key: NarrationKey, vars: Record<string, string | number> = {}): string {
  const tpl = pick(POOLS[key]);
  return tpl.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ""));
}
