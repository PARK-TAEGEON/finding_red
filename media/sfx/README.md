# 효과음 (슬라이스용)

`tools/sfx/make_sfx.py`로 직접 합성한 소리예요. 외부 소리를 쓰지 않아서 저작권 걱정이 없어요.
다시 만들려면: `python3 tools/sfx/make_sfx.py`

## 올리는 방법
1. Roblox Studio → **View → Asset Manager** → **Bulk Import**(또는 Creator Hub → Creations → Development Items → Audio → Upload)로 이 폴더의 `.ogg` 19개를 올린다. 계정에 따라 월 업로드 한도가 있을 수 있다.
2. 각 오디오의 ID(`rbxassetid://숫자`)를 `src/shared/Config/Audio.luau`의 같은 이름 키에 넣는다. 파일 이름 = 키 이름.
   - 직접 넣기 어려우면 "이름: 숫자" 목록만 오케스트레이터에게 주면 된다.

| 키 | 언제 |
|---|---|
| PistolShot / SniperShot | 사격 |
| BatSwing / BatHit | 방망이 휘두름 / 맞음 |
| Reload / DryFire | 재장전 / 빈 탄창 |
| HitMarker / PenaltyKill | 명중 / 비목표 처치(벌점) |
| RedDeath | 레드 처치 |
| Alert / WhiteAttack | 몬스터 "!" 발견 / 화이트 공격 |
| PlayerHurt / Downed / Revived | 피격 / 쓰러짐 / 부활 |
| Pickup | 무기 줍기 |
| Countdown / StageClear / StageFail / Stamp | 카운트다운 / 성공 / 실패 / 도장 |
