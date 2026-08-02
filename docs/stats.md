# Steel Tide — Stat Reference

The canonical list of player stats. **Main** stats are the core power dials every
tank has (start at a class value). **Sub** stats mostly start at zero/baseline and
define specialized builds, gained through upgrades and class perks.

Status legend: ✅ implemented · 🔨 to build.

## Main stats (6)

| Stat | Type | What it does | Baseline | Status |
|------|------|--------------|----------|--------|
| Max HP | flat | Health pool | 70 / 100 / 150 by class | ✅ |
| Damage | ×mult | Multiplier on all weapon damage | ×1.0–1.1 | ✅ |
| Fire Rate | ×mult | Attack-speed multiplier | ×0.95–1.15 | ✅ |
| Range | ×mult | Weapon range multiplier | ×1.0 | ✅ |
| Move Speed | flat | Drive speed | 185 / 240 / 300 | ✅ |
| Armor | flat | Damage subtracted from each hit | 0 / 0 / 2 | ✅ |

## Sub stats (13)

| Stat | Type | What it does | Baseline | Status |
|------|------|--------------|----------|--------|
| Crit Chance | % | Chance a hit crits (multiplier is per-weapon, see below) | 0% (cap 60%) | ✅ |
| Dodge | % | Chance to ignore a hit entirely | 0% (cap 50%) | ✅ |
| HP Regen | /sec | Passive health regeneration | 0 | ✅ |
| Lifesteal | flat | HP restored per kill (a.k.a. Salvage) | 0 | ✅ |
| Greed | % | Bonus gold from pickups | +0% | ✅ |
| Engineering | tiers | Buffs turrets you build (+dmg / +HP per point) | 0 | ✅ |
| Pickup Radius | flat | Magnet range for gold/XP | 80–140 | ✅ |
| Turn Rate | rad/s | How fast the hull rotates | fixed 2.8 today → class-based | 🔨 |
| Projectile Speed | ×mult | Shot travel speed (hitscan/flame ignore this) | ×1.0 | 🔨 |
| AoE Radius | ×mult | Splash radius on explosive weapons & towers | ×1.0 | 🔨 |
| Shield | flat + % | Max capacity of the regenerating overhealth layer (0 → X) | 0 | 🔨 |
| Shield Recharge Rate | %/sec | % of max shield restored per second while recharging | 25%/s (default) | 🔨 |
| Shield Recharge Delay | sec | Time after taking a hit before recharge begins | 3s (default) | 🔨 |

## Crit multiplier (weapon property, not a player stat)

Crit *chance* is a universal player sub-stat, but the crit *multiplier* lives on
each weapon — e.g. a machine gun crits for ×2, a cannon for ×3. Big, slow weapons
can crit harder. Defined per weapon in `WeaponData`.

## Shield mechanic (detail)

A second HP layer that absorbs damage **before** real HP:
- Damage depletes Shield first, then HP.
- After **Shield Recharge Delay** seconds without taking damage, the shield refills
  at **Shield Recharge Rate** %/sec up to **Shield** (max capacity).
- It only refills the shield — never heals HP.
- With Shield capacity 0, the recharge stats are inert (nothing to refill).

Shield capacity is a universal stat (any class can build it). Shop items come in
two flavors: **+N Shield** (flat, adds base capacity) and **+% Shield** (scales
current capacity). A +% item does nothing until you own some flat base, so there's
a deliberate build order — buy the base, then amplify. Heavy's *Bulwark* perk means
it simply starts with base Shield already.

## Conventions

- **×mult** stats are multiplicative and stack multiplicatively from upgrades
  (e.g. two +8% Damage cards → ×1.166).
- **% chance** stats (Crit, Dodge) are additive and capped.
- Which stats each class starts strong/weak in, and their unique perks, are defined
  in the class bonuses (see the classes doc — TBD).
