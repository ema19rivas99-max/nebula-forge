# Sprite pack recipe (resume from here)

Goal: ship all 10 remaining paid sprite packs for NebulaForge. Each pack is 52
sprites. The shop auto-reveals a pack once `<prefix>_fire_t0` is in the bundle,
so **no Swift change is needed** — generate 52, cut, write imagesets, commit.

## Status

- [x] `anime`   Anime Ink   (shipped earlier)
- [x] `cyber`   Cyberpunk   (commit 1828e60)
- [x] `medieval` Medieval   (commit ab9e21a)
- [ ] `fantasy` High Fantasy
- [ ] `dragon`  Dragonscale
- [ ] `frost`   Frostbound
- [ ] `eldritch` Eldritch
- [ ] `celestial` Celestial
- [ ] `clockwork` Clockwork
- [ ] `biolume` Bioluminescent
- [ ] `vapor`   Vaporwave

## Pipeline

`python pack_pipeline.py <prefix>` reads `<prefix>_urls.json` (index -> URL),
downloads to `<prefix>_raw/`, cuts the background, writes imagesets straight
into the repo's Assets.xcassets. It aborts if any of the 52 indices is missing
and flags any sprite whose opaque coverage is outside 4%-92% (a failed cut).

Result URLs look like:
`https://d8j0ntlcm91z4.cloudfront.net/user_3GmwsF4lkE2IFG1d2Rr6UkcuS4j/hf_20260807_<stamp>_<jobid>.png`

## Generation lessons (learned the expensive way)

- **Batch size 6.** 12 triggers HTTP 429 `rate_limit_reached` on submit; 8 still
  fails ~20-35% of jobs; 6 came back 6/6 repeatedly. Submit 6, poll (the 15s
  long-poll also paces the next submit), repeat.
- **Failures are silent job failures, not errors.** Track indices, retry the
  gaps. Failed jobs do not consume credits — Cyberpunk's 52 sprites plus 6
  style probes cost 87.5 credits total, about 1.5 per delivered image.
- **Lock the palette per element.** Generic style colour destroys the board's
  at-a-glance element read — the first Cyberpunk pass produced a Fire item
  indistinguishable from a Void one.
- **Keep the body bright.** Dark-bodied sprites sink into the dark board.
- **Generate on plain white**; the cut floods inward from the edges, so white
  *enclosed* inside the artwork is preserved deliberately.

## Prompt template

```
{STYLE} game item icon: {NAME} — {DESC}. {SCALE}. {MATERIAL}; the glowing
parts are {PALETTE} only. Bold black ink outline, flat cel shading, high
contrast. Single centered object, pure flat white background. No text, no
frame, no shadow.
```

SCALE by tier: t0 "Tiny and simple" · t1 "Small and simple" · t2 "Modest size,
a little more structure" · t3 "Medium sized, clearly crafted" · t4 "Large and
detailed" · t5 "Big, intricate and layered" · t6 "Very large, ornate and
imposing" · t7 "Colossal and maximally elaborate, the ultimate form".

## Index -> item (fixed across every pack)

Base chains, 8 tiers each:

- 0-7 fire: Stardust, Ember, Cinder, Flare, Solar Wisp, Corona, Sunforge, Helios Core
- 8-15 ice: Frost Dust, Rime, Glacier Shard, Comet, Ice Moon, Cryosphere, Frozen Titan, Absolute Zero
- 16-23 void: Dark Matter, Shadow Wisp, Null Fragment, Void Rift, Singularity, Event Horizon, Dark Star, Oblivion
- 24-31 radiant: Sunmote, Gleam, Prism, Radiant Core, Starlight, Quasar, Pulsar, Lumen Eternal

Hybrids, tiers 3-7 only:

- 32-36 tempest (ice): Tempest, Cyclone, Maelstrom, Stormcrown, Eye of Winter
- 37-41 infernal (fire): Infernal Rift, Hellforge, Nova Heart, Cinder Throne, Ashen God
- 42-46 aurora (radiant): Aurora, Polar Crown, Spectrum, Lightfall, Firmament
- 47-51 eclipse (void): Eclipse, Black Sun, Devourer, Endless Night, Final Dark

Descriptions: a faint scatter of glowing dust motes / a single smouldering
ember / a cluster of burning cinders / a sharp burst of flame / a curling wisp
of solar flame / a blazing ring of solar fire / a forge burning at the heart of
a star / the burning heart of a sun · a sprinkle of frost crystals / a crust of
rime ice / a jagged shard of glacier ice / an icy comet with a trailing tail /
a frozen moon / a frozen orb of layered ice shells / a colossal figure encased
in ice / a sphere of absolute cold · a clot of dark matter / a curling wisp of
shadow / a jagged fragment of nothingness / a tear ripped in space / an
infinitely dense point / the rim of a black hole bending light / a collapsed
star burning black / total annihilation · a single mote of sunlight / a small
gleam of light / a refracting prism splitting a beam / a glowing core of pure
light / concentrated starlight in a lattice / a brilliant jet from a spinning
core / a spinning beacon firing twin beams / an everlasting lantern · a violent
swirling storm / a towering spiral cyclone / a devouring whirlpool of storm / a
crown wreathed in lightning / the calm eye of an endless blizzard · a rift onto
an inferno / an infernal forge with anvil and molten metal / the exploding
heart of a nova / a throne of burning cinders / a towering figure of ash and
fire · ribbons of aurora light / a crown of polar light / a full spectrum of
split light / a cascading waterfall of light / the vault of heaven · a sun
blotted out by a dark disc / a sun burning in negative / a vast maw devouring
light / night without end / the last darkness after everything.

## Per-pack style and palettes

Element palettes stay in their family; hybrids take their parent element's
colour plus one accent (tempest +white lightning, infernal +ember red,
aurora +emerald-teal shimmer, eclipse +thin gold rim).

- **cyber** (done) — "Cyberpunk"; bright polished silver chrome with fine
  circuit etching. fire neon orange/red/amber · ice neon cyan/ice blue/white ·
  void neon violet/purple/magenta · radiant neon gold/warm yellow/white-hot.
- **medieval** — "Medieval illuminated-manuscript"; hammered iron, riveted
  steel and gold leaf with enamel inlay. fire ember orange and deep red enamel ·
  ice pale blue enamel and frosted silver · void deep purple enamel and
  blackened iron · radiant gold leaf and warm ivory.
- **fantasy** — "Storybook high-fantasy"; glossy painted enamel over carved
  pale wood and silver filigree, soft storybook shapes.
- **dragon** — "Dragonscale"; overlapping iridescent dragon scales, horn and
  molten veins.
- **frost** — "Frostbound"; carved clear glacier ice with internal fracture
  lines and pale frost.
- **eldritch** — "Eldritch"; wrong angles, too many eyes, wet chitin and
  writhing tendrils.
- **celestial** — "Celestial stained glass"; leaded stained-glass panels with
  gold came and haloed light.
- **clockwork** — "Clockwork"; brass gears, escapements, springs and
  engraved plate.
- **biolume** — "Deep-sea bioluminescent"; translucent gel flesh, glowing
  organs and drifting filaments.
- **vapor** — "Vaporwave"; glossy pink-and-teal chrome, marble bust surfaces
  and grid lines. (This one deliberately reads pink/teal; keep the *element*
  hue dominant and vaporwave as the surface treatment.)
