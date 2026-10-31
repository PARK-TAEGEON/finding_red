# Agent C 보고서 — 흐름·데이터·HUD (1차 웨이브)

## 1. 만든/고친 파일

| 파일 | 내용 |
|---|---|
| `src/server/Services/Profile.luau` | 순수 모듈. 스키마 v1(`Types.Profile`과 동일 구조), `new/normalize/serialize`, `applyResult`(resultId 기준 멱등, 도장 OR 병합, 클리어 시 BestTime, 골드·처치·판수·클리어 수), `claimReceipt`(Receipts 100개, Results 20개와 분리), `setSensitivity`(0.2~3), `owns/grant/spend`, `stageFlags`, `hasCleared` |
| `src/server/Services/DataService.luau` | OX DataService 이식: 세션 리스 `UpdateAsync`(토큰+시각, `SessionLeaseSeconds`), 로드 4회 재시도 후 킥, 저장 3회 재시도·세션 상실 시 킥, 5초 루프 자동 저장(`AutoSaveSeconds`)·리스 만료 전 킥, `BindToClose`(Start에서 등록, 최대 25초 대기). Studio는 메모리(`StudioStartGold`), `StudioUseDataStore=true`면 `StudioDataStoreName`. 속성 `Gold`/`StageFlags`(JSON)/`Sensitivity`/`DataReady`(+ 보조 `SaveStatus`). `Setting` 리모트 처리 |
| `src/server/Services/StageFlow.luau` | 매치 루프 Lobby→Vote→Countdown→Playing→Result→(Next/Retry→Countdown \| Lobby), 체력·쓰러짐·부활·출혈, 처치 집계, 팀 열쇠, 이탈 처리, 캐릭터 재배치, 공허 낙하 복구 |
| `src/server/Services/Flow/FlowLogic.luau` (신규) | 순수 판단 모듈: 로비 시작 조건, 투표 집계/조기 종료, 피해·회복·출혈·부활 진행, 전원 쓰러짐/실패 사유, 처치 델타, 이탈 시 목표, 결과(도장·골드·NewFlags·첫 클리어), 결과 선택지/기본값, 다음 파티, 배치 위치, 스폰 슬롯. `Rules`는 인자로 주입 |
| `src/client/Controllers/HUDController.luau` | `State` 수신→`ctx.SetState`, 페이즈·Life로 1/3인칭+무기 on/off, 골드·목표 카운터·시간, 레이더, HP·열쇠, 무기·탄약, 피격 비네트, 토스트, 쓰러짐/탈락 오버레이(출혈 타이머·부활 진행), 부활 안내(E 홀드), 카운트다운 숫자, 칠판 미션 배너, 결과 화면, 일시정지 메뉴, Shift 달리기 |
| `src/client/Controllers/LobbyUI.luau` | 파티 목록(✔), 준비 토글, 자동 출발 타이머, 친구 초대(`CanSendGameInviteAsync`→`PromptGameInvite`, pcall), 스테이지 투표 카드(한국어 이름·내 도장 ★☆·표 수) |
| `src/client/Controllers/MobileControls.luau` | 터치 기기 전용 둥근 버튼: 공격(홀드), 조준(토글), 점프, 달리기(토글), 무기변경, 부활(홀드·조건부). 기본 썸스틱/화면 드래그 유지 |
| `src/client/Controllers/UI/Kit.luau` (신규) | Frame/UICorner/UIStroke/Text 기반 UI 헬퍼, 색, 시간 포맷, 열쇠 색 변환 |
| `src/client/Controllers/UI/Actions.luau` (신규) | HUD·모바일 공용: 달리기/점프/부활 대상 탐색·시작·중지, `StageFlags` 디코드, 상태 변경 신호 |
| `src/client/Controllers/UI/Radar.luau` (신규) | 원형 레이더(반경 120, 카메라 방향 회전, 레드=빨강(범위 밖은 테두리에 반투명), 그 외=흰색, 동료=초록) |
| `src/client/Controllers/UI/ResultScreen.luau` (신규) | "미션 성공!!"/"미션 실패", 도장 3개 순차 찍힘(Back 트윈 + `Stamp` 소리), NEW! 표시, 골드, Next/Retry/Lobby 투표 버튼(표 수) |
| `src/client/Controllers/UI/PauseMenu.luau` (신규) | 계속하기 / 회전 감도 슬라이더(0.2~3, 0.1 단위) / 로비로(안내만). Modal 버튼으로 마우스 해제 |
| `tests/profile.spec.luau`, `tests/flow.spec.luau` (신규) | Lune 테스트 |

## 2. 공개 API 구현 상태 (CONTRACT §3.4 / §3.5)

| API | 상태 |
|---|---|
| `DataService.Init/Start/Get/Mutate/Save/ApplyResult/UnlockedStages` | 구현 |
| `StageFlow.Init/Start/GetState/RoundId/GetParty/IsPlaying/GetLife` | 구현 |
| `StageFlow.DamagePlayer` | 구현 (Playing + 파티 + Alive만, `Feedback Hurt {Amount, From, Source}`, HP 0 → Downed) |
| `StageFlow.HealPlayer` | 구현 (Alive만, MaxHP로 클램프) |
| `StageFlow.ReportKill` | 구현 (Countdown·Playing에서 집계, `Config.Enemies`는 방어적으로 읽음) |
| `StageFlow.GiveTeamKey/HasTeamKey` | 구현 (`MatchState.Keys` 반영 + 방송) |
| `HUDController.Init/Start/Toast`, `LobbyUI.Init/Start`, `MobileControls.Init/Start` | 구현 |
| 리모트 | `Ready` `Vote` `Interact` (StageFlow), `Setting` (DataService) 처리. `State`/`Feedback` 송신 |

다른 서비스 호출은 계약 방향만 사용하며, 전부 `pcall`로 감싸 스텁/오류여도 루프가 죽지 않는다 (`Stage:Load` 실패 시 토스트 후 로비 복귀).

## 3. 테스트 + 자동 검사

- `tests/profile.spec.luau` — 217 checks: 쓰레기 값 정규화(nil/숫자/문자/NaN/inf/음수/긴 id/잘못된 레코드), 알 수 없는 키·`_Session` 제거, Results 20·Receipts 100 꼬리 유지, 직렬화 왕복·깊은 복사, `applyResult` 멱등, 도장 OR 병합, BestTime(더 빠를 때만, 실패 무시), 실패는 Plays만, 영수증이 결과를 밀어내지 않음, 감도 클램프, 소유/지출.
- `tests/flow.spec.luau` — 94 checks: 로비 시작 조건, 투표 집계·조기 종료·무투표 폴백, 피해/회복/출혈(부활 중 정지)/부활 진행, 전원 쓰러짐 추적·유예·시간 초과, 처치 델타(트랩 레드 인정, 화이트는 플레이어 처치만 벌점), 이탈 시 목표(내리기만), 결과(도장·첫 클리어 보너스 개인별·실패 보상 동일·NewFlags), resultId 유일성, 결과 선택지/기본값, 다음 파티 상한, 배치, 스폰 라운드로빈.
- `tools/check.sh` → **CHECK PASS** (rojo build ok, 타입 검사 오류 0 / 린트 경고 0, rules·profile·flow 테스트 통과).

## 4. 상태

- **자동 검사 상태**: 통과 (`CHECK PASS`).
- **플레이 검증 상태**: **검수 대기** (Studio 없음. 아래 체크리스트로 확인 필요).

## 5. Studio 검수 체크리스트

### 5.1 솔로 (Play)
1. 시작 직후 화면 위 가운데 골드 `2000`(Studio 메모리 기본), 아래쪽에 파티 패널(내 이름 `…`), `준비!`/`친구 초대` 버튼.
2. `친구 초대` → Roblox 초대 창(Studio에서는 "초대할 수 없어요" 토스트가 정상일 수 있음). 오류 없이 동작.
3. `준비!` → 이름 앞 `✔`, 즉시 투표 화면. 카드 `LEVEL 1-1 / 첫 사냥 / ☆☆☆ / 0표`. 2초 뒤(선택지 1개) 자동 진행.
4. 카운트다운: 큰 숫자 5→1(+`Countdown` 소리 키), 칠판 배너 "LEVEL 1-1 / 레드 1마리 잡기 / 힌트: …", 캐릭터가 스테이지 `PlayerSpawn`으로 이동, 3인칭.
5. "시작!" → 1인칭 + 무기 활성(A 구현 시), 위 가운데 빨간 얼굴 아이콘 `0/1`, 아래 `0:00 / 0:40`(기준 넘으면 회색), 오른쪽 위 레이더에 빨간 점(카메라 돌리면 점도 회전), 왼쪽 위 HP 바 100, 오른쪽 아래 무기 이름·탄약.
6. `Shift` → 달리기(속도 24) 토글, 다시 누르면 16.
7. 화이트에게 맞기 → 화면 가장자리 빨간 번쩍임, HP 감소. HP 0 → "쓰러졌어요!" 오버레이 + 30초 카운트, 이동 느림(4), 점프 불가, 3인칭·무기 끔. 10초 뒤 "미션 실패".
8. 다시 하기 → 레드 처치 → 즉시 "미션 성공!!", 도장 원이 하나씩 쾅 찍힘(빠르게 깨면 `빠름`, 화이트 안 죽이면 `깔끔`), 처음 얻은 도장에 `NEW!`, `+골드` 표시, 버튼 `다음 스테이지 0 / 다시하기 0 / 로비로 0`.
9. `다음 스테이지` 클릭 → 4초 뒤 바로 1-2 카운트다운(결과→카운트다운 15초 이내). 화이트를 쏴서 죽이면 "깔끔 도장 실패" 토스트, 결과에 `깔끔` 없음.
10. `P`(또는 오른쪽 위 `II` 버튼; Esc는 Roblox 메뉴가 먼저 가져갈 수 있음) → 일시정지, 마우스 풀림, 감도 슬라이더 조작 시 회전 속도 변화(A의 `SetSensitivity`), 놓으면 저장. `계속하기`로 복귀 시 1인칭 복귀.
11. 리셋(Esc 메뉴 → Reset) 또는 맵 밖으로 떨어지기 → 플레이 중이면 스테이지 스폰, 로비면 로비 스폰으로 돌아옴. 쓰러진 상태는 유지.
12. 결과에서 `로비로` 투표 → 로비로 이동, 모두 Alive, 준비 패널 다시 표시. 투표 카드에 1-1 `★` 개수 반영, 1-2 해금.

### 5.2 클라이언트 2명 (Test → Clients and Servers, 2 Players)
1. A만 준비 → "모두 준비하면 바로 출발 · 20초 후 자동 출발 (1/2)" → 20초 뒤 A만 투표/출발, B는 로비에 남고 하단 "관전 중" 배너.
2. 결과 화면에서 `다음 스테이지` → B(나중에 남은 사람)도 다음 판 파티에 자동 합류하지 않음(로비 미준비자는 관전). 판 진행 중 **새로 접속한** 사람만 다음 판(Next/Retry)부터 합류.
3. 둘 다 로비에서 준비 → 즉시 투표. 투표 카드에 표 수가 실시간 반영, 둘 다 투표하면 2초 뒤 진행. 동점이면 앞 번호.
4. 목표 수: 1-1 2인 = `0/2`, 레이더에 동료 초록 점.
5. **부활**: A가 쓰러짐 → B 화면에 "A 님이 쓰러졌어요!" 토스트. B가 6스터드 안에서 "E 길게 누르기: A 님 살리기" → E 3초 홀드 → 진행 바 → A가 HP 50으로 일어남(양쪽 토스트, `Revived` 소리). 홀드 중 멀어지거나 E를 떼면 진행 취소. 부활 중에는 A의 출혈 타이머가 멈춤.
6. 둘 다 쓰러짐 → 10초 뒤 실패. 한 명이 30초 방치 → "탈락", 관전.
7. **판 중 이탈**: 1-2(2인 목표 3)에서 한 명 나가기 → 카운터가 `x/2`로 내려가고 칠판 문구도 갱신. 이미 2마리 잡았으면 즉시 성공.
8. 결과 화면: 둘의 골드가 각자 첫 클리어 여부에 따라 다를 수 있음. 투표 버튼 표 수 동기화.
9. 판 진행 중 세 번째 클라이언트 접속(가능하면) → 로비 대기 + "관전 중" 배너, 다음 판에 합류.

### 5.3 모바일 (Studio Device Emulator, 터치 기기)
1. 오른쪽에 `공격`(누르는 동안 공격) `조준`(토글, 노란색) `무기변경` `달리기`(토글) `점프` 버튼. 로비에서는 `달리기`/`점프`만.
2. 동료가 쓰러졌고 가까우면 `부활` 버튼 등장, 누르고 있으면 부활 진행.
3. 레이더 120px, 무기 패널이 레이더 아래로 이동.

### 5.4 저장 (별도 테스트 플레이스)
1. 테스트 플레이스에서 Game Settings → Security → "Enable Studio Access to API Services" 켜기.
2. 로컬에서만 `Config/Game.luau`의 `StudioUseDataStore = true`로 바꿔 빌드(커밋하지 않음) → `StudioDataStoreName` 사용.
3. 1-1 클리어 → 출력 창 오류 없음, 플레이어 속성 `SaveStatus` "저장 완료".
4. 정지 → 다시 Play: 골드(0에서 시작 + 보상), 1-1 도장, 1-2 해금, 감도 값이 유지.
5. 같은 계정으로 두 번 연속 빠르게 접속(이전 세션 종료 직후): 리스가 풀릴 때까지 최대 ~12초 재시도 후 로드되거나, 다른 서버가 쥐고 있으면 킥 메시지.
6. API 접근을 끈 채 `StudioUseDataStore = true` → 경고 후 메모리 모드로 대체(킥되지 않음).

## 6. 알려진 한계 / 판단 사항

- **Esc**: Roblox가 Esc를 자체 메뉴로 가져가 게임에 안 올 수 있어 `P` 키와 화면 `II` 버튼을 함께 둠.
- **Shift**: `StarterPlayer.EnableMouseLockOption`이 켜져 있으면 로비(3인칭)에서 Shift가 시프트락도 토글함 → 아래 제안 1.
- **Dead 상태 비활성화**는 서버 Humanoid에만 적용(클라이언트가 물리 소유자). 그래서 Reset 버튼은 그대로 동작하고, 리스폰된 캐릭터는 현재 페이즈에 맞게 재배치된다(쓰러짐 상태 유지). Humanoid 체력은 서버가 항상 최대로 되돌림.
- 리스폰 시 `Weapon:GiveLoadout`을 다시 부르지 않음(탄약 리필 악용 방지). A가 Tool/Backpack 방식이면 리스폰 후 무기가 사라질 수 있음 → A 확인 필요.
- 판 종료 정리 순서: `Enemy:ClearAll → Weapon:ClearStage → StripLoadout`는 결과 화면 **시작** 시, 결과 투표가 끝나면 **로비로 이동 → `Stage:Unload`** 순(언로드 후 이동하면 한 프레임 낙하 위험이 있어 이동을 먼저 함). `Stage:Unload`는 루프 종료 시 한 번 더 불릴 수 있으므로 D의 Unload는 멱등이어야 함(스텁은 멱등).
- 스폰 위치: `PlayerSpawn` 마커 위치와 `LobbySpawn(i)` 모두 "바닥 근처 점"으로 보고 +3스터드 위에 HumanoidRootPart를 둠. 마커는 `MarkerId`(없으면 Name) 순으로 정렬해 라운드로빈.
- 처치는 Countdown 중에도 집계(무기 지급 후라 레드 손실 방지). 클리어 판정은 Playing 시작 시점부터.
- 출혈 30초는 누군가 부활 홀드 중이면 멈춤(29초에 시작한 부활이 실패하지 않도록).
- `Out` 플레이어는 그 자리에서 관전(속도 16, 무기 없음), 리스폰하면 로비.
- 투표 조기 종료: 파티 전원이 투표하면 Vote는 2초, Result는 4초(도장 연출) 이후 바로 진행. 선택지가 1개면 2초 후 자동 진행.
- 로비 20초 자동 출발 타이머는 **첫 준비 시점**부터. 모두 준비를 취소하면 초기화.
- 결과 기본값: `Next`가 있으면 Next, 없으면 실패 시 Retry, 마지막 스테이지 클리어 시 Lobby.
- `NewFlags`(서버) = 파티 중 **누군가** 처음 얻은 비트. 결과 화면의 NEW! 표시는 클라이언트가 카운트다운 시점 자기 `StageFlags`를 기억해 **개인 기준**으로 계산(없으면 서버 값).
- 판 진행 중 새로 들어온 사람은 다음 Next/Retry 판에 자동 합류(최대 4). 로비에서 준비 안 하고 남은 사람은 로비로 돌아갈 때까지 관전.
- `StudioStartGold`는 메모리 모드에서만 적용(OX와 동일). 데이터스토어 모드의 새 프로필은 0골드.
- Results는 최근 20개만 기억하므로 같은 resultId가 21판 이상 지난 뒤 다시 오면 재적용될 수 있음(resultId에 서버 JobId+RoundId가 들어가 실제로는 재사용되지 않음).
- 모바일: Roblox 기본 점프 버튼이 남아 있어 점프 버튼이 2개. 우리 버튼은 기본 점프 버튼을 피해 배치.
- `Request` 리모트는 처리하지 않음(MVP 이후).

## 6.1 B 통합 사실 반영 확인

- `Flow:IsPlaying()`은 `Phase == "Playing"`일 때만 true (Countdown·Result에서는 false) → B의 인지/공격 조건과 일치.
- 죽은 몬스터(`State == "Dead"`, 최대 ~2.5초 잔류)는 레이더에서 제외.
- 화이트 근접 `Flow:DamagePlayer(p, 10, "White", rootPos)` → Hurt 피드백 `From`/`Source`로 전달.

## 7. 계약 변경 제안

1. `StarterPlayer.EnableMouseLockOption = false`를 `default.project.json`(오케스트레이터)에 추가 — Shift 달리기와 시프트락 충돌 방지.
2. §3.3 플레이어 속성에 `BleedOutAt: number`(쓰러짐 해제 한계 서버 시각, HUD 출혈 타이머용)와 `SaveStatus: string`(저장 상태 표시용, OX 이식) 추가.
3. §3.2 `Feedback Hurt`에 선택 필드 `Source: string`(피해 원인 kind) 추가 — 현재 추가로 보내고 있음.
4. §3.2 `Setting` 리모트 처리 주체를 DataService로 명시(현재 그렇게 구현).
5. §1.1 표에 "전원 투표 시 조기 종료(Vote 2초, Result 4초 최소)"와 "20초 타이머는 첫 준비부터"를 명시.
6. §1.5에 "부활 홀드 중 출혈 시간 정지" 명시.
7. §3.4 `StageService.Unload`는 멱등, `LobbySpawn`/`PlayerSpawn`은 바닥 근처 점(+3 위에 배치)이라는 규약 명시. 판 종료 순서를 "로비 이동 → Unload"로 바꾸는 것을 제안.
8. §3.1 `StageResult.NewFlags` 정의를 "파티 중 한 명이라도 처음 얻은 비트"로 명시.
