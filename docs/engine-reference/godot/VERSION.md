# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.7.2 |
| **Installed at pin time** | Godot 4.7.2.stable.official.ed1daf0bf (`~/.local/bin/godot4`, Linux x86_64, probed 2026-10-06) |
| **Release Date** | 2026 (4.7 stable line; 4.7.2 patch) |
| **Project Pinned** | 2026-10-06 |
| **Last Docs Verified** | 2026-10-06 (4.7 delta only; `modules/` snapshots still describe 4.6) |
| **LLM Knowledge Cutoff** | May 2025 |

## Godot 4.7 delta (pinned 2026-10-06)

The `modules/` snapshots in this folder were written for 4.6. Known 4.7
compatibility breaks (source: https://godotengine.org/releases/4.7/ and the
4.7 milestone "breaks compat" label):

- GDScript: evaluation of constant expressions with arrays/dictionaries
  changed (GH-113228). Re-check `const` arrays/dicts if a value looks wrong.
- Shaders: stricter condition parsing in the shader preprocessor (GH-117173).
- Particles: angular velocity fixed to match the docs (GH-117861).
- Android: deprecated Google Play OBB support removed (GH-118283).

Verified on this project with 4.7.2: SceneTree `-s` scripts must
`await process_frame` after `root.add_child()` before `_ready` state exists.

## Knowledge Gap Warning

The LLM's training data likely covers Godot up to ~4.3. Versions 4.4, 4.5,
and 4.6 introduced significant changes that the model does NOT know about.
Always cross-reference this directory before suggesting Godot API calls.

## Installed-Version Gap Warning

The warning above is one-directional — it covers the **model** knowing less than
this pin. The reverse gap is real and `/setup-engine` §3 creates it deliberately
("pin the newer one and upgrade later"): this reference can sit **ahead of the
installed editor**, and an agent citing it correctly then emits APIs that do not
compile locally. **Check `Installed at pin time` above before trusting a
version-qualified claim** — `NOT DETERMINED` means the gap is unknown, not absent.

## Post-Cutoff Version Timeline

| Version | Release | Risk Level | Key Theme |
|---------|---------|------------|-----------|
| 4.4 | ~Mid 2025 | MEDIUM | Jolt physics option, FileAccess return types, shader texture type changes |
| 4.5 | ~Late 2025 | HIGH | Accessibility (AccessKit), variadic args, @abstract, shader baker, SMAA |
| 4.6 | Jan 2026 | HIGH | Jolt default, glow rework, D3D12 default on Windows, IK restored |

## Verified Sources

- Official docs: https://docs.godotengine.org/en/stable/
- 4.5→4.6 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.6.html
- 4.4→4.5 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.5.html
- Changelog: https://github.com/godotengine/godot/blob/master/CHANGELOG.md
- Release notes: https://godotengine.org/releases/4.6/
