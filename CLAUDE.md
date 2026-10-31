# Finding Red — agent guide

Roblox co-op FPS built with Rojo. **`docs/CONTRACT.md` is the single source of truth** — read it fully before any work.

- Contract types live in `src/shared/Types.luau`. Services/controllers must match them exactly (the type checker enforces this through `Main.server.luau` / `Main.client.luau`).
- File ownership is in CONTRACT §2.3. Only edit files you own. Propose contract changes in your report instead of editing shared files.
- Pure modules (`Rules`, `WeaponMath`, `EnemyLogic`, `Profile`, `Config/*`, `Maps/*`) use no Roblox globals and no requires, so Lune can test them.
- Verify with `tools/check.sh` (needs tool binaries in `$FR_BIN`, default `/home/claude/bin`). Done = last line `CHECK PASS`.
- There is no Roblox Studio here. Studio playtesting is done by the human reviewer from the checklist in your report (`docs/reports/<A|B|C|D>.md`).
- Original-game reference notes: `docs/reference/ORIGINAL_NOTES.md` (grammar only — never copy layouts or art).
