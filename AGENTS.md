# Finding Red — guide for coding agents (Codex, Claude, others)

Roblox co-op first-person shooter built with Rojo + Luau. **`docs/CONTRACT.md` (Korean) is the single source of truth.** Read it fully before any work.

## How work arrives
- Every job is a **task card** in `docs/tasks/` (e.g. `docs/tasks/W2-A1.md`). Do exactly what the card says: it lists the files you own, the goal, the acceptance criteria and the Studio checklist to write.
- One task card = one branch = one pull request. Branch name: `task/<card-id>` (e.g. `task/W2-A1`). PR title: `<card-id>: <short summary>`.
- If the card and the contract disagree, follow the contract and say so in the PR.

## Setup and verification
```sh
tools/setup.sh     # installs Rojo, luau-lsp (+ Roblox types) and Lune into .tools/bin
tools/check.sh     # Rojo build + strict type check + Lune tests + map checks
```
Done means the last line of `tools/check.sh` is `CHECK PASS`. Never weaken or skip a check to get there.

## Rules
- **File ownership**: edit only the files your card lists (plus new files in the folders it allows). Shared files (`src/shared/Types.luau`, `Net.luau`, `Rules.luau`, `Config/Game|Stages|Audio`, both `Main.*.luau`, `docs/CONTRACT.md`) belong to the orchestrator — propose changes in the PR description instead.
- **Contract types** live in `src/shared/Types.luau`. Services and controllers must match them exactly; `Main.server.luau` / `Main.client.luau` require each module with its contract type, so a mismatch fails the type check.
- **Service pattern**: `--!strict`; methods defined with `.` and a typed `self` (see CONTRACT §2.4).
- **Pure modules** (`Rules`, `WeaponMath`, `EnemyLogic`, `Profile`, `Flow/FlowLogic`, `Config/*`, `Maps/*`) use no Roblox globals and no `require`, so Lune can test them. Put branchy logic there and test it in `tests/<name>.spec.luau`.
- **Server-authoritative**: validate every client argument (`Net.isNumber/isVector/isString`, `Net.throttle`, `RoundId`).
- **No external assets** (Toolbox, InsertService, other people's models or sounds). Build visuals from Parts; request models via `Assets.get(key)` with a code-built fallback; play sounds only through `Config/Audio` keys.
- Player-facing text is Korean; identifiers are English.
- **No Roblox Studio is available to agents.** Reason carefully about runtime behaviour you cannot execute, and write the Studio checklist the human reviewer will follow.
- Original-game reference: `docs/reference/ORIGINAL_NOTES.md` — grammar and feel only; never copy layouts, art or character designs.

## PR description must include
1. What changed (files) and contract APIs touched.
2. `tools/check.sh` result (paste the last 15 lines).
3. **Studio checklist** for the reviewer (numbered, solo + 2-client where relevant).
4. Known limitations and any contract change proposals.
