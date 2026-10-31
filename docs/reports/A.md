# 에이전트 A (무기) 보고서 — 1차 웨이브

## 1. 만든 / 고친 파일

| 파일 | 내용 |
|---|---|
| `src/shared/Config/Weapons.luau` | 무기 수치 (§1.9, §3.6). `Bat` `Pistol` `Sniper` 완성 + `Rifle` `Shotgun` `Grenade` `Rocket` 자리(MVP용 데이터만). `export type WeaponSpec` 추가, 근접 콘 반각 `Cone` 필드 추가(선택 필드) |
| `src/shared/WeaponMath.luau` | 순수 모듈: 벡터 도우미, 연사 간격(10% 여유), 발사 시각 클램프, 랙 보정 시각, 원점·방향 검사, 조준점(사거리·3°) 검사, 과거 위치 거리 검사, 근접 대상 선택, 탄창/예비탄/재장전/탄약 % 계산, 로드아웃 목록·순환, 픽업 거리, 폭발 피해 |
| `src/shared/Models/WeaponModels.luau` | 파트로 조립한 방망이·권총·저격총(+MVP 무기 임시 모델), 1인칭 팔, 픽업 전시 모델(링·빛·이름표). `Assets.get("Weapon/<Id>")`가 있으면 그걸 먼저 씀 |
| `src/server/Services/WeaponService.luau` | 로드아웃·속성, `Fire`/`Reload`/`Equip` 검증, 히트스캔·방망이, 픽업, `Explode` |
| `src/client/Controllers/CameraController.luau` | 1인칭/3인칭, 줌(FOV 트윈), 감도 |
| `src/client/Controllers/WeaponController.luau` | 입력, 발사(클라 레이캐스트), 조준/스코프, 재장전, 무기 전환, 리모트 처리 |
| `src/client/Controllers/Weapon/Viewmodel.luau` (새 파일) | 카메라에 붙는 팔+무기, 대기/걷기 흔들림, 반동, 방망이 스윙, 재장전 기울임, 꺼내기, 조준 자세 |
| `src/client/Controllers/Weapon/Overlay.luau` (새 파일) | 조준점, 히트마커(흰 X / 벌점이면 빨간 X, 처치 시 크게), 저격 스코프(검은 원형 가림 + 십자선) |
| `src/client/Controllers/Weapon/Fx.luau` (새 파일) | 궤적, 총구 섬광, 착탄, 폭발, 픽업 전시물 회전·위아래 움직임, 내가 주운 픽업 로컬 숨김 |
| `tests/weapons.spec.luau` | WeaponMath + Config/Weapons 테스트 148개 |

## 2. 계약 API 구현 상태

| API | 상태 | 비고 |
|---|---|---|
| `WeaponService:Init/Start` | 완료 | Start에서 `Fire` `Reload` `Equip` 연결, PlayerRemoving 정리, 0.2초 픽업 루프 |
| `PrepareStage(handle)` | 완료 | `handle.Markers.WeaponPickup`의 `Weapon`/`MarkerId` 속성 → `workspace.Stage.WeaponPickups/Pickup_<MarkerId>` (태그 `WeaponPickupDisplay`). 바닥은 `GeometryParams` 레이캐스트로 찾음 |
| `ClearStage()` | 완료 | 전시물 삭제, 획득 기록 초기화, 그 판에서 주운 무기 회수(장착 중이면 권총으로) |
| `GiveLoadout(player)` | 완료 | `Data:Get(p).Owned` ∪ `Default`, 탄약 가득, 기본 장착 `Pistol`. 속성 `Weapons` `Equipped` `Mag_<Id>` `Ammo_<Id>` |
| `StripLoadout(player)` | 완료 | 상태·속성 모두 제거 |
| `AddAmmoPercent(player, %)` | 완료 | 전체 용량의 %를 예비탄에 추가(상한 = 가득 찬 상태) |
| `Explode(center, r, eDmg, pDmg, byPlayer)` | 완료 | 몬스터는 `QueryRadius` + `Damage(…,"Explosion")`, 플레이어는 `byPlayer == nil`일 때만 `Flow:DamagePlayer`. `Effect Explosion` 방송. 플레이어 폭발이면 그 플레이어에게 히트마커 |
| `CameraController:SetFirstPerson/SetZoom/SetSensitivity` | 완료 | 터치 시점 감도는 아래 한계 참고 |
| `WeaponController:SetEnabled/Attack/Aim/Reload/Cycle` | 완료 | 모바일 버튼(C)이 그대로 호출하면 됨 |

### 서버 검증 순서 (`Fire`)
1. `Net.throttle(0.03s)`, payload 표, `R == Flow:RoundId()`, `W` 보유, `O`/`D` 벡터(NaN·∞ 거부), `Flow:GetLife == "Alive"`, Head 존재
2. `W`가 장착 무기와 다르면 장착으로 처리(재장전 취소). 재장전 중이면 거부
3. 연사: `T`를 `[now-0.4, now+0.1]`로 자른 발사 시각끼리 `1/Rate × 0.9` 이상 (네트워크 흔들림에 강하고, 위조해도 장기 연사율은 못 올림 — 테스트로 확인)
4. 탄창 > 0, 원점이 머리 8스터드 이내, |D|≈1, 머리→원점 사이 지형 없음
5. **여기까지 통과하면 발사 확정**: 탄 1발 차감(맞든 안 맞든)
6. 명중 주장(`Id`+`P`): 사거리, 방향과 지점 각도 < 3°, `PositionAt(Id, clamp(T, now-0.4, now))`가 `P`에서 `GetRadius+2.5` 이내, 원점→지점 지형 없음 → `Enemy:Damage(…,"Bullet",O)` + `Feedback Hit`
7. `Effect Shot {From, To, W, UserId}` 방송 (`To` = 검증된 `P` 또는 `O + D×사거리`)

방망이: `QueryRadius(root, 11)` → 살아 있는 몬스터의 `PositionAt(now)` → 수평 7스터드 이내·높이차 6 이내·앞쪽 60° 콘(몸 반지름만큼 넓힘) 중 가장 가까운 것, 지형에 막히면 무효. `Config.Enemies[kind].Penalty == true`면 `Knockback(id, 수평 단위벡터, 2)`(피해 0), 아니면 `Damage(id, 35, p, "Melee", root)`. `Effect Melee {UserId, Target}`.

## 3. 테스트와 자동 검사

- `tests/weapons.spec.luau`: **148 checks passed** — 정상 사격, 거부 사유별(원점 멂, 방향 길이, 사거리, 각도 2° 통과 / 4° 거부, 과거 위치 멂, 기록 없음), NaN/∞(벡터·시각·반지름·%), 연사(정확한 간격, 10% 여유, 같은 시각 연타 1발만, 지터 있는 정직한 4발/초 40발 전부 통과, 위조 시각 장기 연사 제한), 근접 선택(정면·뒤·옆·사거리·높이·겹침·콘 가장자리), 탄약·재장전·탄약 %·로드아웃·순환·픽업 거리·폭발, Config 수치(§1.9 표와 일치)
- `tools/check.sh` → **CHECK PASS** (rojo 빌드, luau-lsp 타입 검사 경고 0, Lune 테스트 2개)

## 4. 상태

- **자동 검사 상태: 통과 (CHECK PASS)**
- **플레이 검증 상태: 검수 대기** — Studio가 없어 실행해 보지 못함. 다른 에이전트(B 몬스터, C 흐름/HUD, D 맵) 결과물과 합친 뒤 아래 체크리스트로 확인 필요. 스텁 상태(예: `Flow:GetLife` 스텁 = `"Spectating"`)에서는 서버가 모든 사격을 거부하는 것이 정상.

## 5. Studio 검수 체크리스트

사전 조건: 통합 빌드(`rojo build -o FindingRed.rbxl`), C의 `HUDController`가 `State`를 받아 `ctx.SetState` 하고 Playing에서 `Camera:SetFirstPerson(true)`, `Weapon:SetEnabled(true)` 호출. 출력 창에 `[WeaponService]` 경고가 없는지 함께 본다.

### 솔로 (Play)
1. 로비: 3인칭, 마우스 커서 보임, 화면에 무기 없음, 조준점 없음.
2. 1-1 시작(카운트다운→Playing): 1인칭으로 바뀌고 마우스가 가운데 잠김, 커서 숨김, 화면 가운데 흰 조준점. 오른쪽 아래에 **권총 + 팔**이 보이고 걸을 때 흔들림, 가만히 있으면 살짝 숨쉬듯 움직임.
3. 속성 확인(Explorer → Players → 내 플레이어 → Attributes): `Weapons = "Bat,Pistol"`, `Equipped = "Pistol"`, `Mag_Pistol = 12`, `Ammo_Pistol = 48`. (C의 HUD 탄약 표시가 같은 숫자인지)
4. `1` → 방망이(어깨 위로 비스듬히), `2` → 권총, `Q` → 순환. 전환할 때 아래에서 올라오는 동작. `Equipped` 속성이 따라 바뀜.
5. 권총 좌클릭: 발사음(`PistolShot`, ID 비어 있으면 무음), 총구 섬광, 노란 궤적, 반동. 한 번 클릭 = 한 발 (꾹 눌러도 연사 안 됨), 빠르게 연타해도 초당 4발까지. `Mag_Pistol`이 1씩 줄어듦(빗나가도 줄어듦).
6. 레드를 맞히면 **흰 X 히트마커** + `HitMarker` 소리, 레드 HP(B의 체력바) 15씩 감소. 2발이면 레드(30) 처치 → X가 크게.
7. 벽 뒤에 숨은 레드를 벽에 대고 쏘면 피해 없음(벽에 착탄).
8. 우클릭(누르고 있기): 권총 조준 — FOV 55로 부드럽게 줌, 권총이 화면 가운데로. 떼면 원래대로.
9. 12발 다 쏘면 빈 탄창에서 `DryFire` + 자동 재장전(총이 기울었다 돌아옴, 1.2초) → `Mag 12 / Ammo 36`. 중간에 `R` 수동 재장전도 확인. 재장전 중 발사 안 됨, 재장전 중 무기 바꾸면 재장전 취소.
10. 예비탄까지 모두 쓰면 `DryFire`만 나고 재장전 안 됨.
11. 1-2: 저격총 픽업이 링 위에서 **천천히 돌며 위아래로 떠 있음**, 위에 "저격총" 글자. 4스터드 안으로 걸어가면 자동 획득: `Pickup` 소리, (C가 Text를 띄우면) "저격총 획득!", 전시물이 **내 화면에서** 사라짐. `Weapons = "Bat,Pistol,Sniper"`, `Mag_Sniper = 5`, `Ammo_Sniper = 10`.
12. `3` → 저격총. 우클릭 → **스코프**: FOV 20, 화면이 검은 원형으로 가려지고 십자선 + 빨간 점, 팔·총 모델 숨김, 마우스 감도가 줌에 맞춰 느려짐. 저격 한 발(100)로 레드 처치. 연사 간격 약 1.25초. 재장전 2.2초(재장전 시작하면 스코프 해제).
13. 같은 픽업 자리로 다시 가도 다시 안 주워짐(플레이어별 1회).
14. 1-3: 화이트를 **방망이**로 치기(7스터드 이내, 정면) → 화이트가 맞은 방향으로 밀려나고 2초 기절(B 연출), 피해 없음, 흰 X. 레드를 방망이로 치면 35 피해 → 한 대에 처치. 허공 스윙은 `BatSwing`만.
15. 화이트를 총으로 죽이면 **빨간 X** + `PenaltyKill` 소리 (C의 PenaltyKills +1).
16. 판 종료 → 결과: 3인칭 복귀, 마우스 풀림, 무기·조준점·스코프 사라짐, `Weapons`/`Equipped`/`Mag_*`/`Ammo_*` 속성 제거. 다음 판에 저격총이 없어졌다가(픽업 무기는 그 판만) 1-2에서 다시 주울 수 있음.
17. 플레이 중 Esc(C의 일시정지)가 `Modal` 버튼을 쓰면 커서가 보이는지.
18. 쓰러짐(`Life = Downed`): 좌클릭해도 발사 안 됨, 조준 풀림.

### 클라이언트 2명 (Test → Clients and Servers, 2 players)
1. 두 명 모두 1인칭, 서로의 사격이 **상대 화면에 궤적**(상대 캐릭터 오른팔 쪽에서 출발) + 위치 소리로 보임. 내 총알은 동료 몸을 통과(아군 사격 없음).
2. 1-2에서 A가 저격총을 주우면 **A 화면에서만** 사라지고 B 화면에는 그대로. B도 걸어가면 따로 주울 수 있음.
3. A가 레드에 맞히면 히트마커는 **A에게만**.
4. A가 이동하며(달리기 24) 쏴도 정상 명중(랙 보정). Studio의 네트워크 지연 설정(Incoming Replication Lag 0.2)을 켜고도 움직이는 레드 명중이 되는지.
5. 한 명이 나가도 서버 오류 없음(출력 창).
6. 한 명이 쓰러진 상태로 다른 사람이 사격 → 정상.

### 치트 방지 확인 (선택, 서버 명령 창)
- 클라이언트 명령 창에서 `game.ReplicatedStorage.Remotes.Fire:FireServer({R=0/0, W="Sniper", O=Vector3.new(0/0,0,0), D=Vector3.zero, T=0})` 같은 값 → 아무 일 없음, 오류 없음.
- 같은 `T`로 100번 보내도 1발만 처리(탄 1발만 줄어듦).

## 6. 알려진 한계

- **터치 시점 감도**: Roblox 기본 터치 카메라는 `MouseDeltaSensitivity`를 안 쓰고 스크립트로 바꿀 감도 값도 없다. PC 마우스만 적용. 모바일까지 하려면 PlayerModule 카메라 입력을 포크해야 함(웨이브 2 제안).
- `Rifle` `Shotgun` `Grenade` `Rocket`은 **데이터만**. 서버는 `Kind`가 `Hitscan`/`Melee`가 아니면 `Fire`를 버린다. 샷건 펠릿(`Fire`에 Id/P가 하나뿐)과 투척·투사체(`Throw` 리모트)는 다음 웨이브. `Rifle`은 Hitscan+Auto라 실제로는 지금도 동작함(꾹 누르면 연사).
- 서버는 `Flow:IsPlaying`을 부를 수 없어서(호출 방향 표에 없음) **카운트다운 중 사격 차단은 클라이언트(`Phase == "Playing"`)와 C의 `Life`/`SetEnabled`에 의존**. 서버는 RoundId·Life만 본다.
- `Enemy:Damage`의 반환값 의미가 계약에 명확하지 않아 쓰지 않는다. 처치 여부는 `Damage` 직후 `Enemy:IsAlive(id) == false`로 판단 → B가 `Damage` 안에서 즉시 `IsAlive=false`로 만들어야 히트마커의 Killed/Penalty가 맞음(§2.6에 그렇게 적혀 있음).
- 방망이 판정은 과제 지시대로 `PositionAt(id, now)`(현재 위치)를 쓴다. 지연이 큰 플레이어는 빠르게 도망치는 레드를 근접으로 맞히기 조금 어려울 수 있음.
- 클라이언트는 탄창 수를 예측(로컬 차감)하고 서버 속성으로 맞춘다. 탄이 0일 때 아주 드물게 서버가 거부하는 "유령 발사"(궤적만 보이고 탄 변화 없음)가 한 발 생길 수 있음.
- 픽업 전시물 회전은 각 클라이언트에서 로컬로 한다(서버는 정지 상태 모델만 만듦 → 네트워크 부담 없음).
- 뷰모델 팔 색은 캐릭터 `BodyColors`(팔/몸통 색)를 따르고, 없으면 기본 피부색/파란 소매.
- Lune에서 실행할 수 없는 부분(레이캐스트, GUI, 뷰모델 자세)은 코드 검토만 했다. 특히 **스코프 원형 가림**(UICorner + 두꺼운 UIStroke + 바깥 검은 막대 4개)과 **방망이 스윙 각도**는 눈으로 확인이 필요.

## 7. 계약 변경 제안 / 다른 에이전트에게

1. **`EnemyService:Damage` 반환값 정의** (오케스트레이터/B): "피해가 들어갔으면 true" 또는 "이번 피해로 죽었으면 true" 중 하나로 명시. A는 현재 둘 다 동작하게 `IsAlive`로 판정.
2. **WeaponService → `Flow:IsPlaying` 호출 허용** (오케스트레이터): 서버에서도 Playing 이외 페이즈의 사격·픽업을 막을 수 있게.
3. **`Knockback` 방향 크기** (B): A는 수평 **단위 벡터**를 보낸다. 밀어내는 속도는 B가 정하거나 `Config.Weapons.Bat.Knockback.Speed`(45)를 읽어 쓰면 됨. 계약에 "direction은 단위 벡터"라고 적기 제안.
4. **`Feedback`/`Fire` 필드 추가 기록**: `Feedback Hit`에 방망이 넉백이면 `Knockback = true`, `Feedback PickedUp`에 `Text = "저격총 획득!"`(HUD가 토스트로 쓸 수 있음). `Fire`의 `P`는 `Id` 없이도 올 수 있음(빗나간 탄의 벽 착탄 지점 → 궤적 끝점용, 피해 없음).
5. **`Config/Weapons` 스키마에 `Cone: number?`**(근접 콘 반각, 도) 추가.
6. **C(HUD)에게**: HUD `ScreenGui`의 `DisplayOrder`를 1 이상으로(A의 오버레이 = 0) 해야 스코프 위에 탄약 표시가 보임. 일시정지 메뉴는 `Modal = true`인 버튼을 넣어야 1인칭에서 커서가 풀림. 탄약 표시는 `Equipped`와 `Mag_<Equipped>`/`Ammo_<Equipped>`를 읽으면 되고 `Bat`은 이 속성이 없음(∞).
7. **B에게**: `Effect Explosion`은 A의 `Explode`가 방송하고 A가 그림(불덩이+연기). B는 따로 그리지 않아도 됨. 몬스터 모델이 죽는 연출 중이면 `State = "Dead"`로 두면 클라 레이캐스트가 시체를 통과한다.
8. **D에게**: `StageService:GeometryParams()`는 몬스터·캐릭터를 빼야 함(A는 방어적으로 몬스터/캐릭터 히트를 무시하고 계속 레이캐스트하긴 함). 픽업 전시물은 `workspace.Stage.WeaponPickups` 아래에 생기며 전부 `CanQuery=false`/`CanCollide=false`. `WeaponPickup` 마커는 바닥 위 10스터드 이내(아래로 레이캐스트해서 링을 바닥에 놓음).

## v0.5 변경

### 1. 바뀐 / 새 파일

| 파일 | 내용 |
|---|---|
| `src/shared/Config/Weapons.luau` | `Pickups = { Reach = 4, Health = 40, AmmoPercent = 50, AmmoCapMultiplier = 2 }` 추가 (무기 항목 아님: `Kind` 없음, `Order`에 없음 → `WeaponsConfig[id]` 조회는 그대로 건너뜀) |
| `src/shared/WeaponMath.luau` | 순수 함수 추가: `pickupKey(kind, id)`, `canClaim(prepared, stageCurrent, inParty, life)`, `healGain(hp, maxHp, amount)`, `ammoPickup(mag, reserveMax, reserve, percent, capMult) -> (newReserve, added)` |
| `src/shared/Models/WeaponModels.luau` | `supplyDisplay("Health"|"Ammo", groundCf)` — 체력 = 흰 상자 + 면마다 빨간 십자(위 포함), 탄약 = 초록 상자 + 노란 띠 + 뚜껑·손잡이·탄 3발. 바닥 링(빨강/초록 빛). `worldModel(id)` — 3인칭용 무기(0.85배) |
| `src/server/Services/WeaponService.luau` | 픽업을 `Weapon`/`Health`/`Ammo` 3종으로 일반화 (아래 규칙). `Config.Game.MaxHP` 읽음 |
| `src/client/Controllers/WeaponController.luau` | 시작 방 클릭 무반응(아래), 3인칭 무기 초기화, 동료 궤적 시작점을 3인칭 무기 총구로 |
| `src/client/Controllers/Weapon/Fx.luau` | 전시물 회전 대상이 `Weapon` 또는 `Item`(체력·탄약 상자) |
| `src/client/Controllers/Weapon/ThirdPerson.luau` (새 파일) | 다른 플레이어 오른손에 무기 모델 (클라이언트 전용) |
| `tests/weapons.spec.luau` | 45개 추가 → **193 checks** |

### 2. 체력·탄약 픽업 (§1.12.6)

- `PrepareStage`가 `handle.Markers.WeaponPickup` / `HealthPickup` / `AmmoPickup`를 모두 읽어 `workspace.Stage.WeaponPickups/Pickup_<key>` 전시물을 만든다 (태그 `WeaponPickupDisplay` 공통, 속성 `MarkerId = key`, `PickupKind`). 바닥은 기존처럼 아래로 레이캐스트.
- **획득 키**: 무기는 마커 `MarkerId` 그대로(1차와 같음), 체력·탄약은 `"Health:<Id>"` / `"Ammo:<Id>"` — 태그가 다른 마커가 같은 Id를 써도 충돌하지 않음. `Feedback.Marker`·`Effect Pickup.Marker`도 이 키.
- 서버 0.2초마다, 4스터드(수평)·높이차 6 이내면 자동 획득. 플레이어별·마커별 1회.
- **체력**: `HP` 속성 < `MaxHP`일 때만 `Flow:HealPlayer(p, 40)`. 호출 뒤 `HP`가 실제로 올랐을 때만 획득 기록 → 피가 가득이면 그대로 남아서 나중에 다시 와서 먹을 수 있다. `Feedback {Kind="PickedUp", Item="Health", Text="체력 +N", Marker}` — **N은 실제로 회복된 양**(HP 75에서 먹으면 "체력 +25"; 40 미만일 수 있음).
- **탄약**: 서버의 장착 무기 기준. 방망이(탄창 없음)면 건너뜀(기록 안 함). 예비탄 += `ceil(Reserve × 50%)`(최소 1), 상한 `Reserve × 2` (권총 +24 / 상한 96, 저격총 +5 / 상한 20). 이미 상한이면 건너뜀. `Feedback {Kind="PickedUp", Item="Ammo", Weapon, Text="탄약 +N", Marker}`. `Ammo_<Id>` 속성 갱신 → 클라 탄약 표시·재장전에 바로 반영.
- 모두 `Effect("Pickup", {UserId, Marker})` 방송, 클라이언트는 `PickedUp`을 받으면 `Pickup` 소리 + 그 전시물을 **내 화면에서만** 숨김 (무기 픽업과 같은 코드).

### 3. 픽업 가능 시점 (규칙)

**"스테이지가 준비돼 있고(PrepareStage 후 ClearStage 전) 그 스테이지가 아직 `Stage:Current()`이며, 플레이어가 `Flow:GetParty()`에 있고 `Flow:GetLife() == "Alive"`"** 이면 획득 가능. 페이즈는 보지 않는다.
- 이유: `GetState`는 호출 허용 목록에 없고 `IsPlaying()`은 시작 방(Countdown)에서 false라 쓸 수 없다. 픽업은 `PrepareStage`(Countdown 시작) ~ `ClearStage`(Result 시작) 사이에만 존재하므로 이 규칙 = Countdown + Playing.
- 경기장의 체력·탄약 상자는 문이 닫혀 있어 시작 방 단계에 닿을 수 없다. 시작 방에 놓인 무기는 문 열기 전에 주울 수 있다.
- 사격은 그대로 `Flow:IsPlaying()`일 때만 (오케스트레이터 패치 유지). 장착 전환·재장전은 시작 방에서도 가능.

### 4. 시작 방 사격

- 서버: 변경 없음(IsPlaying 게이트 유지). 클라 `T = seenTime()` 유지.
- 클라: `Phase ~= "Playing"`이면 클릭해도 **아무 것도 안 함** (스윙·발사음·`DryFire`·자동 재장전 없음). 누른 채로 문이 열려도 자동 연사가 저절로 시작되지 않음(`Attack`에서 `triggerHeld`도 Playing일 때만 켬). 조준(우클릭)은 시작 방에서도 됨.

### 5. 3인칭 무기 (동료)

- `Weapon/ThirdPerson.luau`: 다른 플레이어의 `Equipped` 속성(서버가 이미 복제하는 값)을 보고 그 무기 모델을 만들어 매 프레임 R6 `Right Arm`(R15면 `RightHand`) 끝에 붙인다. 총은 손에서 앞으로(허리 높이), 방망이는 위·앞으로 기울여 든다. 리플리케이션 비용 0, 파트는 고정·충돌 없음·`CanQuery=false` (총알·레이캐스트에 영향 없음), `workspace.FR_ThirdPersonWeapons` 아래.
- `Life`가 `Out`/`Spectating`이거나 `Equipped`가 없으면(로비·결과) 무기 없음. 250스터드 밖이거나 캐릭터가 없으면 숨김.
- 동료의 사격 궤적은 이제 그 3인칭 무기의 총구에서 시작.

### 6. 테스트·자동 검사

- `tests/weapons.spec.luau` **193 checks passed** (새 45개: 키 충돌 없음, 획득 규칙 8가지 생명 상태, 회복량(가득·0·NaN·음수), 탄약(권총·저격·로켓 수치, 상한, 상한 초과 시 줄이지 않음, 방망이, NaN/∞/0%/배수<1), Config 수치)
- `tools/check.sh` → **CHECK PASS** (타입 경고 0)

### 7. Studio 검수 체크리스트 (v0.5)

사전: D의 맵에 `HealthPickup`/`AmmoPickup` 마커(속성 `MarkerId`)가 있어야 함. 없으면 Studio에서 투명 파트에 태그 + `MarkerId` 속성을 달아 경기장 바닥 위 2스터드에 두면 됨.

솔로
1. 시작 방(Countdown): 바닥의 무기 전시물이 돌고 떠 있음. 걸어가면 획득("저격총 획득!" + `Pickup` 소리, 내 화면에서 사라짐). 문 열기 전.
2. 시작 방에서 좌클릭/모바일 공격: **아무 반응 없음**(소리·스윙·궤적·탄 감소 없음). 1/2/3·Q 전환과 우클릭 조준은 됨.
3. 좌클릭을 누른 채 문 열기 → 문이 열려도 저절로 쏘지 않음. 다시 클릭하면 정상 사격.
4. 경기장의 체력 상자: 흰 상자에 빨간 십자(네 옆면 + 윗면), 빨간 빛 링 위에서 돌며 떠 있음. 탄약 상자: 초록 상자 + 노란 띠 + 위에 탄 3발, 초록 링.
5. HP 100에서 체력 상자로 가면 **안 먹어짐**(그대로 보임). 레드에게 맞아 HP 60 → 다시 가면 "체력 +40", HP 100, 상자가 내 화면에서 사라짐. HP 80에서 먹으면 "체력 +20".
6. 권총 예비탄 48(가득)에서 탄약 상자 → "탄약 +24", `Ammo_Pistol = 72`. 방망이를 든 채로 가면 안 먹어짐 → 권총으로 바꾸면 그 자리에서 먹어짐. 예비탄 96이면 안 먹어짐.
7. 저격총을 든 채로 → `Ammo_Sniper` 10 → 15.
8. 쓰러진 상태로 상자 위를 지나가도 안 먹어짐.
9. 한 번 먹은 상자 자리로 다시 가도 다시 안 먹어짐. 다음 판엔 다시 보임.

클라이언트 2명
1. A가 체력·탄약 상자를 먹으면 A 화면에서만 사라지고 B는 따로 먹을 수 있음. `Pickup` 소리는 먹은 사람만.
2. **3인칭 무기**: B 화면에서 A의 오른손에 A가 든 무기(권총/방망이/저격총)가 보이고, A가 1/2/3을 바꾸면 B 화면의 무기도 바뀜. 걸을 때 팔과 함께 흔들림. 로비·결과 화면에선 맨손.
3. A가 쏘면 B 화면의 궤적이 A 손의 총구에서 시작.
4. 3인칭 무기가 총알을 막지 않음(동료 손 근처의 레드도 맞음).

### 8. 알려진 한계 (v0.5)

- 3인칭 무기는 **팔 애니메이션이 없다**: 캐릭터는 툴을 든 것이 아니므로 팔이 내려간 채로 걷기 흔들림을 따른다(총은 허리 높이에서 앞을 향함). 팔을 드는 자세는 로컬 애니메이션/Motor6D 조작이 필요해 이번엔 뺐다. 위치·각도(`R6_GUN`, `R6_GRIP.Bat`)는 Studio에서 눈으로 보고 조정 필요할 수 있음.
- 체력 획득 문구는 실제 회복량("체력 +25" 등)이다. 항상 "+40"으로 보이길 원하면 한 줄 수정.
- 탄약 상자는 **장착 중인 총만** 채운다(과제 지시대로). 방망이를 들고 있으면 먹어지지 않는다.
- 예비탄 상한이 `Reserve × 2`로 늘었으므로 HUD가 예비탄 최대값을 `Reserve`로 가정하고 막대를 그린다면 넘칠 수 있음(C 확인).
- 체력 판정은 `HP` 속성을 읽는다(StageFlow가 쓰는 값). `HealPlayer` 후 값이 안 오르면 기록하지 않는다.

### 9. 계약 변경 제안 (v0.5)

1. `Feedback PickedUp`에 `Item: "Weapon"|"Health"|"Ammo"` 필드 추가 기록(HUD가 아이콘을 고를 때 쓸 수 있음). 체력·탄약은 `Weapon` 대신(탄약은 대상 총 Id를 `Weapon`에 담음).
2. `Config/Weapons.Pickups` 스키마(`Reach`, `Health`, `AmmoPercent`, `AmmoCapMultiplier`)를 §3.6에 기록.
3. §3.9의 "서버는 `IsPlaying()`이 false면 픽업을 받지 않는다"를 v0.5 시작 방에 맞게 "픽업은 스테이지 준비~결과 시작 사이, Alive 파티원만"으로 고치기.
