# 보고서 B — 몬스터 (1차 웨이브: Red, White)

## 상태 요약

| 단계 | 상태 |
|---|---|
| **자동 검사** (`tools/check.sh`) | **통과** — `CHECK PASS` (rojo 빌드 ok, 타입 검사 오류 0 / 경고 0, Lune 테스트 3개 파일 통과) |
| **플레이 검증** (Studio, 솔로 + 2클라이언트) | **검수 대기** — 이 환경에는 Studio가 없어 Humanoid 이동·물리·애니메이션은 실행해 보지 못했다. 아래 체크리스트로 확인 필요 |

## 만든/고친 파일

| 파일 | 내용 |
|---|---|
| `src/shared/Config/Enemies.luau` | §3.6 스키마 그대로. Red·White 완성 수치 (§1.8 표), Bomb·Raptor·Missile은 데이터만 (MVP). `EnemyConfig` 타입 export |
| `src/shared/EnemyLogic.luau` | **순수** 상태머신 + 구역 계산 (Roblox 전역·require 없음, 벡터 `{x,y,z}`). `new / step / damaged / stun / kill`, `clampToZone / randomPointInZone / fleePoint / segmentDistance / detect / nearestPlayer / historyAt` |
| `src/shared/Models/EnemyModels.luau` | 코드로 조립한 R6 리그. `Assets.get("Enemy/<Kind>")`가 R6 리그면 그것을 우선 사용. 표준 R6 Motor6D 이름·C0/C1, Humanoid(R6) + Animator, 머리 위 `HPBar`·`Alert`("!") BillboardGui. `loadAnimations` (pcall, 실패 시 애니메이션 없이 동작) |
| `src/server/Services/EnemyService.luau` | 계약 API 전부. 스폰, 10Hz 두뇌(프레임 분산), MoveTo 이동 + 막히면 점프 → 길찾기(서버 전체 초당 8회), LOS 레이 예산, 위치 기록, 피해/처치/넉백/사망 연출 |
| `src/client/Controllers/EnemyFX.luau` | "!" 팝 + `Alert` 소리, 피격 흰 번쩍임(Highlight), 기절 별, 화이트 공격 시 `WhiteAttack` 소리 + 팔 휘두르기, `EnemyDeath` 시 `RedDeath` 소리 + 시체 페이드 |
| `tests/enemy_logic.spec.luau` | EnemyLogic 테스트 1054개 체크 |
| `tests/enemy_purity.spec.luau` | EnemyLogic·Config/Enemies에 Roblox 전역/require가 없는지 검사 |

새 하위 폴더(`Services/Enemy/`, `Controllers/Enemy/`)는 만들지 않았다.

## 모습

- **레드**: 빨간 몸(다리는 약간 어둡게), 머리 앞면 SurfaceGui로 **노란 화난 눈**(기울어진 눈 + 검은 눈동자 + "\ /" 눈썹)과 **검은 입 + 흰 이빨**. 뒤에서 봐도 구분되도록 머리 위 작은 뿔 2개(파트).
- **화이트**: 흰 몸, 머리 앞에 튀어나온 **검은 유리 바이저**(파트, 반사 0.25) + 작은 반짝임.
- 외부 에셋 없음 (애니메이션만 Roblox 소유 R6 걷기 `180426354` / 대기 `180435571`).
- 머리 위: 체력바(초록, 거리 120까지), "!"(노란 글자, AlwaysOnTop, 0.5초).

## 행동 (EnemyLogic이 결정, EnemyService가 실행)

모든 몬스터: 집 = 스폰 마커 위치, 구역 = 마커 `Zone` 반지름(없으면 12). 배회·도주 목표는 항상 구역 안.

- **Red**: `Idle`(배회 8, 구역 85% 안 무작위 지점, 도착 후 0.8~2.5초 쉼) → 시야 40 안 + LOS 있는 `Alive` 플레이어 → `Alert` 0.5초(멈추고 바라봄, "!") → `Flee` 13으로 4초 → `Tired` 6으로 2초(계속 멀어짐) → 여전히 위협이면 `Flee`(두 번째 "!" 없음), 아니면 `Idle`. 맞으면: Idle→Alert, Tired→즉시 Flee.
  - **도주 지점**: 가장 가까운 플레이어 기준. 16방향 × 16스터드 앞 지점(구역 안으로 clamp → 가장자리에서 **미끄러지듯 옆으로**) + 구역 테두리 16지점 중, 직선 경로가 위협에게 `min(d, max(6, 0.75d))`보다 가까워지지 않는 후보 가운데 **위협에서 가장 먼** 지점. 막힌 경로(바닥 없음·벽)는 제외. 안전한 후보가 전혀 없으면(구역 밖으로 밀려났고 플레이어가 사이에 있음 등) 위협에서 가장 멀리 비켜 가는 경로를 택해 **멈추지 않는다**. 0.5초마다 재계산.
- **White**: `Idle`(배회 8) → 25 안 + LOS 또는 피격 → `Alert` 0.5초 → `Chase` 18 → 사거리 4 안에서 첫 타 0.35초 준비 후 **1초마다 10** (`Flow:DamagePlayer(p, 10, "White", rootPos)`), 너무 붙으면(2.4 이내) 멈추고 바라봄. 집에서 `Leash` 50 넘으면 `Return`(8, 플레이어 무시) → 집 도착 시 `Idle`. 대상이 사라지면(쓰러짐·이탈) 시야 안 다른 플레이어로 바꾸거나 귀환. 귀환 중 맞으면 집에서 40 이내일 때만 다시 추격(목줄 경계에서 왔다갔다 방지). 맞으면 공격자를 쫓는다.
- **Stunned**(넉백): 지정 시간 동안 아무것도 안 함(공격 없음). 끝나면 White는 마지막 대상을 다시 쫓고, Red는 위협이 있으면 도주, 없으면 배회.
- **Dead**: 아무것도 안 함, 피해·기절 무시.
- 플레이어 대상: `Flow:IsPlaying()`이 true일 때만, `Flow:GetParty()` 중 `Flow:GetLife(p) == "Alive"`이고 캐릭터 루트가 있는 플레이어. (카운트다운 동안은 배회만 한다.)
- 상태는 모델 속성 `State` (`Idle/Alert/Flee/Tired/Chase/Return/Stunned/Dead`).

## 계약 API 구현 상태 (`Types.EnemyService`)

| API | 상태 | 비고 |
|---|---|---|
| `Init / Start` | ✅ | `workspace.Enemies` 폴더 생성(재사용), Heartbeat 루프 |
| `SpawnStage(handle, redCount)` | ✅ | `Markers.EnemySpawn`: Red는 `Weight`(기본 1)로 `Rules.distribute`, 그 외는 `Count`(기본 1). 구역 안 무작위 지점(집과 같은 높이 ±3.5, 집에서 직선으로 막힘 없음, 10회 시도 후 실패하면 마커 위치), `Stage:GeometryParams()` 레이로 접지. 남은 몬스터가 있으면 먼저 정리. Red 마커가 없으면 경고 후 다른 마커에 Red 생성. 미구현 종류(Bomb 등)는 경고 후 건너뜀 |
| `ClearAll` | ✅ | 모델·연결 전부 제거, 테이블 초기화 (Id 카운터는 유지) |
| `Damage` | ✅ | 죽은/없는 Id → `false`. 처치 타격에서만 정확히 한 번 `true`. `HP` 속성·체력바 갱신, 피격 반응. 사망: `State="Dead"`, `IsAlive` 즉시 false, 날려 보내기, `Effect("EnemyDeath",{Id,Pos,From})`, 2.5초 후 제거, **마지막에** `Flow:ReportKill(kind, byPlayer, cause)` 1회 (ReportKill 안에서 ClearAll이 불려도 안전) |
| `Knockback(id, dir, stun)` | ✅ | PlatformStand + 속도(수평 45 + 위 20) → 착지(또는 1.2초) 시 똑바로 세워 공격자 쪽을 보게 함 → 남은 시간 `Stunned`. `Effect("Knockback",{Id})`. **방향 길이 > 1.5면 그 길이를 속도로 사용** (최대 120) |
| `IsAlive` | ✅ | |
| `GetKind` | ✅ | 시체 제거 후에도 다음 `ClearAll`까지 종류 반환 |
| `GetRadius` | ✅ | Config `Radius` (Red/White 2), 모르는 Id면 2 |
| `PositionAt(id, t)` | ✅ | `workspace:GetServerTimeNow()` 기준 10Hz × 0.6초 기록, 사이 보간, 기록보다 오래되면 가장 오래된 값, 최신보다 새로우면 현재 위치 |
| `QueryRadius` | ✅ | 살아 있는 몬스터만, Id 정렬 |

모델 규격(§2.6): `workspace.Enemies/<Kind>_<Id>`, `PrimaryPart = HumanoidRootPart`, Humanoid(R6), 속성 `EnemyId`·`Kind`·`HasKey`·`State`·`HP`·`MaxHP`(+ `KeyColor` 있으면, `Attack` 카운터), 모든 파트 `CanQuery = true`, 루트 네트워크 소유자 = 서버.

호출하는 외부 API: `Flow:ReportKill/DamagePlayer/GetParty/GetLife/IsPlaying`, `Stage:GeometryParams` 만 (전부 pcall로 감쌈 — 스텁이어도 안전).

## 테스트 / 검사 결과

```
== rojo build                ok
== type check (src/)         ok (lint warnings: 0)
== lune tests
ok   tests/enemy_logic.spec.luau  — 1054 checks passed
ok   tests/enemy_purity.spec.luau — 20 checks passed
ok   tests/rules.spec.luau        — 33 checks passed
CHECK PASS
```

`enemy_logic.spec` 범위: Config 수치·색 형식 / 구역 clamp(높이 유지)·무작위 지점 200회 / 도주 방향 / **가장자리에 몰렸을 때 테두리를 따라 미끄러짐**(움직임 ≥ 2, 거리 증가, 위협 옆을 지나지 않음) / 걷기 불가 필터 / 구역 밖에서 돌아옴 / 무작위 300상황에서 항상 구역 안·멈추지 않음 / Red의 Alert 0.5 → Flee 4 → Tired 2 → 재도주 → 배회 타이밍 / 시야 밖·LOS 없음 미발견 / 피격 반응 / White 발견·추격 18·준비 후 1초 간격 타격·대상 소실 시 귀환·목줄·귀환 중 무시·재추격 조건·다른 대상 재선택 / 기절 중 무행동·기절 후 복귀 / 사망 무반응 / 위치 기록 보간.

## Studio 검수 체크리스트 (검수자)

준비: C·D 작업이 합쳐진 빌드에서 `rojo build -o FindingRed.rbxl` → Studio에서 열기. (C의 StageFlow가 아직 스텁이면 몬스터는 배회만 하고 플레이어를 무시한다 — `IsPlaying()`이 false.)

### 솔로 (Play)
1. 1-1 시작 → `Workspace.Enemies` 아래 `Red_<Id>` 모델 생성, 바닥에 서 있음(공중·땅속 아님). 출력 창에 `[EnemyService]` 경고 없음.
2. 레드 모습: 빨간 몸, 노란 화난 눈·이빨, 머리 뿔. 30~60스터드 거리에서도 빨간 실루엣이 분명.
3. 레드가 **걷기 애니메이션**으로 자기 구역 안을 돌아다니고 가끔 멈춤(대기 애니메이션). 구역 밖으로 나가지 않음.
4. 벽 너머(보이지 않는 곳)에서는 반응하지 않음. 시야 40 안에서 보이면 **"!"가 0.5초** 뜨고 `Alert` 소리 → 반대쪽으로 빠르게 도망(13) → 약 4초 후 느려짐(6) → 계속 보고 있으면 다시 도망, 멀어지면 배회.
5. 레드를 구역 가장자리로 몰기: 제자리에 멈춰 버리지 않고 **가장자리를 따라 옆으로** 빠져나감. 플레이어 쪽으로 달려들지 않음.
6. 권총으로 맞히기: 맞을 때마다 **흰색 번쩍**, 체력바 감소. 처치 시 **맞은 방향으로 회전하며 날아감**, `RedDeath` 소리, 약 1.6초 뒤 흐려지고 2.5초 안에 사라짐. 목표 카운터 +1 (C).
7. 1-3(화이트): 흰 몸 + 검은 바이저. 25 안으로 들어가거나 쏘면 "!" → 빠르게(18) 쫓아옴 → 붙으면 **약 1초마다 팔을 휘두르며** 피해 10 + `WhiteAttack` 소리 (화면 빨개짐은 C).
8. 화이트에게서 멀리 도망: 집에서 50 넘게 끌려오면 포기하고 걸어서 귀환, 귀환 중엔 무시. 집 근처에서 다시 보이면 다시 "!".
9. 방망이로 화이트 치기(A): 밀려나 날아갔다가 착지 후 **똑바로 서서** 별(★) 표시와 함께 약 2초 기절(공격·이동 없음) → 다시 추격. 화이트 처치 시 날아감 + 벌점(C).
10. 상자·낮은 벽 너머로 쫓아올 때 막히면 점프하거나 돌아서 옴(길찾기). 끼어서 계속 제자리걸음하지 않음.
11. 몬스터를 떨어뜨리기(맵 밖 낙하가 가능하다면): 조용히 사라지고, 레드면 카운터에 반영(`cause = "Other"`).
12. 판 종료/재시작: 몬스터 전부 사라지고 다음 판에 새 Id로 다시 생성.

### 2클라이언트 (Test → Clients and Servers, 플레이어 2명)
1. 두 화면 모두에서 같은 위치·애니메이션·체력바·"!"가 보임.
2. 플레이어 A가 레드를 쏘고 B가 마무리: 처치는 한 번만 집계(카운터 +1), 날아가는 연출 양쪽에서 보임.
3. 레드는 **더 가까운 플레이어**에게서 도망. 화이트는 자기를 때린 플레이어를 쫓음.
4. 쫓기던 플레이어가 쓰러지면(Downed) 화이트가 공격을 멈추고 다른 `Alive` 플레이어(시야 안)로 바꾸거나 귀환.
5. 한 명이 나가도 오류 없음.
6. 동시에 같은 레드를 연사해도 `ReportKill` 1회 (C 카운터로 확인).

### 성능 (30마리)
1. 테스트용 맵/마커로 Red 20 + White 10 생성 (`EnemySpawn` `Count`/`Weight` 조정) + 플레이어 2~4명.
2. Studio `View → Script Performance`에서 `EnemyService` 활동률 확인 (목표: 낮은 한 자릿수 %), `Ctrl+F6` MicroProfiler에서 Heartbeat 스파이크 없음, 서버 FPS 60 근처 유지.

## 성능 메모

- 두뇌: 몬스터당 10Hz, 스폰 순서로 0~0.09초 위상 분산 → 30마리 = 프레임당 약 5개.
- LOS: 시야 거리 안 플레이어에게만, 가까운 순서로 첫 번째 보이는 대상에서 중단. 몬스터×플레이어별 0.3초 캐시 + 프레임당 최대 40레이.
- 걷기 가능 검사: 목표를 새로 고를 때만(배회 도착 시, 도주 0.5초마다), 두뇌 틱당 최대 12회.
- MoveTo: 목표가 0.75스터드 이상 바뀌거나 2초 지났을 때만 다시 호출.
- 길찾기: 막혔을 때만(0.8초에 0.8스터드 미만 진행 2회째), 서버 전체 토큰 버킷 초당 8회, 몬스터당 Path 객체 재사용, 결과 5초 유효.
- 플레이어 목록은 프레임당 1번만 만든다. 몬스터가 없으면 루프는 즉시 반환.

## 알려진 한계 / 확인 필요

- **Studio에서 실행해 보지 못함.** 특히 확인 필요: MoveTo 목표 높이(루트 높이로 넘김), PlatformStand 넉백의 비거리·착지, R6 애니메이션 로드(서버 Animator에서 재생 → 복제).
- 구역의 걷기 가능 판정은 "집과 같은 높이 ±3.5"라서, 구역 안에 계단·경사로가 있으면 다른 층 지점은 배회 목표에서 제외된다(맵 설계 시 구역은 한 층으로).
- 플레이어가 상자 위에 올라서 있으면 화이트는 아래에서 서성일 수 있다(직선 3D 거리 4 밖이면 공격 불가).
- 시체(최대 2.5초)는 충돌이 있어 플레이어를 살짝 밀 수 있고, 클라이언트 레이캐스트에 맞을 수 있다 (서버 `Damage`는 `false` 반환이라 판정은 안전).
- `HasKey` 몬스터 처치 시 열쇠 드롭은 미구현(MVP 기믹, 호출 권한 필요 — 아래 제안 3).
- Bomb/Raptor/Missile은 데이터만 있고 스폰하지 않는다(경고 출력).
- 화이트의 팔 휘두르기는 클라이언트에서 `Right Shoulder.C0`를 잠깐 돌리는 연출(서버 애니메이션 아님).

## 계약 변경 제안

1. **몬스터 속성 추가 명시** (§2.6): `HP`, `MaxHP`, `Attack`(근접 공격할 때마다 +1 되는 숫자 — 클라이언트 연출용), `KeyColor`(HasKey일 때). 현재 계약 목록에 없지만 이미 설정한다.
2. **`Knockback` 방향 의미 명시** (§3.4): "단위 벡터면 기본 속도(45), 길이가 1.5보다 크면 그 길이가 밀어내는 속도". A는 `dir.Unit * Weapons.Bat.Knockback.Speed`를 넘기면 된다.
3. **호출 방향** (§3.4): 열쇠를 가진 몬스터 처치 시 열쇠를 주려면 `EnemyService → Flow:GiveTeamKey` 허용이 필요하다 (MVP).
4. **`Effect EnemyDeath`에 `Kind` 추가** 제안: 클라이언트가 레드/비목표 처치 소리를 구분할 수 있게. (지금은 모든 처치에 `RedDeath` 소리.)
5. **A(무기) 클라이언트 참고**: 레이캐스트로 몬스터 모델을 찾을 때 `State == "Dead"`인 모델은 건너뛰기를 권장(시체가 총알을 먹지 않게).
6. **D(Stage) 참고**: `GeometryParams()`는 `Include = { workspace.Stage }` 형태를 권장. Exclude 형태여도 EnemyService가 몬스터·캐릭터를 자동으로 제외해 동작한다.
7. **C(Flow) 참고**: 몬스터는 `IsPlaying() == true`일 때만 플레이어를 감지·공격한다. `Countdown` 중에는 배회만 한다.

## v0.5 변경

| 단계 | 상태 |
|---|---|
| **자동 검사** | **통과** — `CHECK PASS` (타입 오류 0 / 경고 0, `enemy_logic.spec` 2801 체크, `enemy_purity.spec` 20 체크) |
| **플레이 검증** | **검수 대기** — 래그돌·충돌 그룹·네트워크 소유는 Studio에서만 확인 가능 |

### 바뀐 것

| 파일 | 내용 |
|---|---|
| `Config/Enemies.luau` | 새 필드 `Behavior: "Chase" \| "Flee"`. **Red**: `Behavior="Chase"`, Sight 35, RunSpeed 14, `Leash` 40, `Melee {8, 1.2, 4}`. 예전 도주 수치(`Flee {4, 2, 6}`)는 남겨 둠 — `Behavior="Flee"`로 바꾸면 v0.4 도주 행동 그대로. White는 `Behavior="Chase"` 명시만(수치 동일) |
| `EnemyLogic.luau` | `behaviourOf(cfg)` 공개: `cfg.Behavior` 우선, 없으면 예전 추론(Flee 표 → Flee, Melee+Leash → Chase). 순수 사망 도우미 `CORPSE` 수치, `deathPush`(밀리는 방향 + 앞/뒤로 쓰러질지), `corpseShouldFreeze`(고정 시점), `corpsesToEvict`(12구 초과분) |
| `Services/Enemy/Corpse.luau` (**새 파일**) | 사망 래그돌 + 시체 관리 + 충돌 그룹 (아래) |
| `EnemyService.luau` | 날려 보내기(`fling`) 삭제. 사망 시 `State="Dead"`·HP 0·체력바/"!" 끔 → `Corpse.collapse(model, from)` → `Effect("EnemyDeath", {Id, Pos, From, Kind})` → `Flow:ReportKill`(마지막, 1회). 죽은 몬스터는 즉시 살아 있는 목록에서 빠짐(`IsAlive`/`QueryRadius`/`Damage` 모두 즉시 반영, `GetKind`는 유지). 살아 있는 몬스터 파트는 `FR_Enemy` 그룹. `ClearAll`이 시체도 전부 제거 |
| `EnemyFX.luau` | `EnemyDeath`의 `Kind == "Red"`일 때만 `RedDeath` 소리 (비목표 처치의 `PenaltyKill`은 A의 히트마커가 이미 냄 → 중복 없음). 사망 후 사라지는 페이드 제거(시체 유지). 서버가 시체에 `Fade=true`를 켜면 0.9초 로컬 페이드. 공격 팔 휘두르기 + `WhiteAttack` 소리는 레드에도 적용(속성 `Attack` 공통) |
| `tests/enemy_logic.spec.luau` | 레드 추격 전체 흐름, Flee 변종(예전 테스트를 `Behavior="Flee"`로 유지), 사망 도우미 |

### 레드 행동 (§1.8, §1.12.1)

구역 배회(8) → 시야 35 + LOS 안의 `Alive` 플레이어 → 멈춰서 바라보며 "!" 0.5초 → 추격(14) → 사거리 4 안에서 첫 타 0.35초 준비 후 **1.2초마다 8** (`Flow:DamagePlayer(p, 8, "Red", rootPos)`), 너무 붙으면 멈춰서 바라봄 → 집에서 40 넘으면 `Return`(8, 플레이어 무시) → 집 도착 시 배회. 안 보이는 곳에서 맞으면 "!" 후 쏜 사람을 쫓음. 귀환 중엔 집에서 32 이내일 때만 다시 반응. 대상이 쓰러지면 시야 안 다른 플레이어로 바꾸거나 귀환. 방망이 기절 후에는 같은 대상을 다시 쫓음("!" 없음). 화이트와 같은 코드 경로라 차이는 수치뿐. 시작 방 단계(`IsPlaying()==false`)에는 플레이어를 전혀 감지하지 않는다(기존 게이트 유지).

### 제자리 쓰러짐 (§1.12.2) — `Enemy/Corpse.luau`

1. 애니메이션 정지 → 모든 파트 `CanQuery=false`, `CanTouch=false`, 충돌 그룹 `FR_Corpse`. 몸 파트(몸통·머리·팔다리)는 `CanCollide=true`(바닥에 닿아야 함), 루트·장식 파트는 false.
2. `RootJoint`(루트↔몸통)만 남기고 Motor6D 5개(목·어깨·엉덩이)를 끄고 같은 자리에 **BallSocketConstraint**(목 35°, 어깨 110°, 엉덩이 85°, 비틀림 제한, 반발 0). 관절 기준점은 Motor6D 회전축 위라서 걷던 자세에서 죽어도 튀지 않는다.
3. **Humanoid 제거** — R6 Humanoid는 팔다리 충돌을 계속 끄고 일어서려 하므로 사망 시 없앤다(체력은 원래 속성 `HP`).
4. 각 파트 `SetNetworkOwner(nil)`(관절이 풀리면 팔다리가 각각 별도 어셈블리가 되므로 전부, 다음 프레임에 한 번 더).
5. 작은 밀기: 공격 지점 반대로 몸통 2.5 스터드/초 + 아래로 −2.5, 다리는 거의 그대로(발이 축) → 무릎(엉덩이)이 꺾이며 **70% 뒤로(공격자 반대), 30% 앞으로** 기울이는 회전 2.6 rad/s. 다리 위치가 4.5스터드(밀림 3 + 넘어짐 여유 1.5) 넘게 미끄러지면 수평 속도를 지운다 — 날아가지 않는다.
6. 0.1초마다 검사: 0.9초 이후 모든 파트 속도 < 0.6이 3번 연속이거나 2.5초가 되면(떨어지는 중이면 최대 5초까지 대기) **모든 파트 Anchored + CanCollide=false** → 바닥을 뚫거나 계속 떨지 않음. 0.9초에 아직 똑바로 서 있으면 한 번 더 넘어뜨림. 죽은 자리보다 60 아래로 떨어지면(맵 밖) 제거.
7. 시체는 `ClearAll`(판 종료)까지 유지. 13번째 시체가 생기면 가장 오래된 것에 `Fade=true` → 클라이언트 페이드 → 1초 뒤 제거.

**충돌 그룹** (서버 `Init`에서 `PhysicsService:RegisterCollisionGroup`, 이미 있으면 건너뜀): `FR_Enemy`(살아 있는 몬스터), `FR_Corpse`(시체), `FR_Player`(플레이어 캐릭터). `FR_Corpse`는 `Default`(맵)와만 충돌하고 `FR_Corpse`·`FR_Enemy`·`FR_Player`와는 충돌하지 않는다. 그 외 조합은 기본값(충돌) 그대로라 플레이어↔맵, 플레이어↔몬스터, 몬스터↔맵 동작은 이전과 같다. **플레이어 캐릭터를 `FR_Player`에 넣는 것은 EnemyService(Corpse)가 `CharacterAdded`/`DescendantAdded`로 한다** — 아래 제안 2 참고.

### Studio 검수 체크리스트 (v0.5 추가분)

솔로:
1. 문이 열리기 전(시작 방) 레드가 배회만 하고 "!"가 뜨지 않음. 문 열고 나가면 정상 반응.
2. 레드 시야(35) 안에 보이게 서기 → 레드가 멈춰서 "!" 0.5초 + `Alert` 소리 → **플레이어 쪽으로 달려옴**(걷기 애니메이션). 벽 너머에선 반응 없음.
3. 가만히 있기 → 붙어서 약 1.2초마다 **오른팔을 휘두르며** `WhiteAttack` 소리 + 피해 8 (HUD 체력 −8, 화면 빨개짐은 C).
4. 뒤로 걸으며(16) 쏘기 → 레드(14)가 점점 뒤처짐. 집에서 40 넘게 끌고 가면 포기하고 걸어서 돌아감, 돌아가는 동안 무시. 집 근처에서 다시 보이면 다시 "!".
5. 레드를 벽 뒤에서 저격 → "!" 후 쏜 사람에게 옴.
6. 권총/저격으로 처치 → **그 자리에서 무릎이 꺾이며 앞이나 뒤로 힘없이 쓰러짐**(1~3스터드 정도만 밀림, 회전하며 날아가지 않음), `RedDeath` 소리, 체력바·"!" 사라짐. 2~3초 안에 완전히 멈추고 **바닥에 누운 채 남음**(서 있거나 바닥에 박히거나 떨지 않음). 탐색기에서 시체 파트가 `Anchored=true`, `CanCollide=false`인지 확인.
7. 방망이로 레드 처치(근접) → 뒤로 쓰러지거나 앞(내 쪽)으로 쓰러져도 **내 캐릭터를 밀지 않고 통과**.
8. 시체 위·사이로 걷기 → 걸리지 않고 통과. 다른 레드/화이트가 시체를 지나갈 때도 통과.
9. 시체를 조준하고 쏘기 → 총알이 시체를 통과해 뒤 몬스터/벽에 맞음. 레이더에 시체 점 없음.
10. 경사·상자 위에서 처치 → 바닥(상자 위)에 누움. 상자 가장자리면 아래로 떨어진 뒤 바닥에서 멈춤.
11. 화이트 처치 → 같은 쓰러짐, `RedDeath` 소리 **없음**, 내 화면에만 `PenaltyKill`(A의 히트마커) 1번.
12. 13마리 이상 처치(테스트 맵 또는 1-3 반복) → 가장 오래된 시체가 서서히 사라짐, 항상 12구 이하.
13. 판 종료(결과 화면) → 시체 전부 사라짐. 다음 판 새로 시작.

2클라이언트:
1. 두 화면에서 쓰러지는 모습·최종 누운 자세가 같음(서버 소유 — 한쪽에서만 움직이거나 떨면 네트워크 소유 문제).
2. 시체 옆에 서 있는 플레이어 B가 밀리지 않음.
3. 레드가 더 가까운/먼저 보인 플레이어를 쫓고, 그 플레이어가 쓰러지면 다른 플레이어로 바꾸거나 귀환.

성능: 30마리 + 동시에 여러 마리 처치(시체 12구) 상태에서 서버 Heartbeat 스파이크 없음 (래그돌 검사는 몸마다 10Hz, 고정 후엔 0).

### 알려진 한계 / 확인 필요

- **Studio에서 실행해 보지 못함.** 관절 제한 각도·밀기 속도(`EnemyLogic.CORPSE`)는 추정치. 너무 뻣뻣/흐물하면 `Corpse.luau`의 `R6_JOINTS`와 `CORPSE.PushSpeed/TipSpeed`만 조정하면 된다.
- 쓰러지는 도중(최대 ~2.5초) 시체는 맵과 충돌한다. 무기 픽업·마커 같은 `Default` 그룹 파트도 맵으로 취급된다(문제 없을 것으로 예상).
- 벽에 붙어 죽으면 벽에 기대 비스듬히 멈출 수 있다(한 번 더 넘어뜨리기는 몸통이 거의 수직일 때만).
- 시체가 고정되기 전 다른 시체 위로 떨어지면 서로 겹친다(시체끼리 충돌 없음 — 떨림 방지가 우선).
- `Assets`로 넣은 사용자 리그는 Motor6D C0/C1 기준 일반 래그돌(제한 70°)로 처리.
- 레드가 상자 위 플레이어를 직선거리 4 밖에서는 못 때리는 것은 화이트와 같다.

### 계약 변경 제안 (v0.5)

1. **§2.6 / §3.9 문구 정리**: "죽으면 날아가는 연출 후 3초 안에 제거", "`State="Dead"`로 최대 2.5초" → §1.12.2대로 "제자리 쓰러짐, 판 끝까지 유지(최대 12구), `CanQuery=false`". `State="Dead"` 건너뛰기는 그대로 유효.
2. **충돌 그룹 소유**: 시체가 플레이어를 통과하려면 플레이어 캐릭터가 `Default`가 아닌 그룹이어야 한다. 지금은 B(`Enemy/Corpse.luau`)가 캐릭터 파트를 `FR_Player`로 넣는다. 캐릭터 담당(C)이 다른 그룹을 쓰게 되면 계약에 그룹 이름 표(`FR_Player`, `FR_Enemy`, `FR_Corpse`)를 넣고 C가 캐릭터 지정을 가져가길 제안.
3. **§3.6 Enemies 스키마**에 `Behavior: string?` ("Chase" | "Flee") 추가.
4. **§3.2 `Effect EnemyDeath`**에 `Kind` 추가(구현됨 — §3.9의 "2차로 미룸" 항목 해소).
