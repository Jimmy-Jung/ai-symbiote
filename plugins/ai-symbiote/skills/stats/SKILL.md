---
name: stats
description: 스킬, 커맨드의 사용 빈도를 분석합니다.
argument-hint: [--reset]
user-invocable: true
allowed-tools: [Read, Glob, Grep, Bash]
---

# Stats -- 사용 통계 조회

## 워크플로우

### Step 1: 사용 데이터 수집

`~/ai-symbiote/{slug}/usage-data/` 디렉터리에서 추적 데이터를 읽습니다.

데이터 형식: 각 파일은 `{count}|{ISO8601 timestamp}` 형태입니다.

```
~/ai-symbiote/{slug}/usage-data/
  .tracked-since          # 추적 시작일
  skills/{name}           # 스킬별 카운터
  commands/{name}         # 커맨드별 카운터
```

추적 데이터가 없으면 안내 메시지를 출력합니다.

### Step 2: 전체 항목 스캔

실제 존재하는 모든 항목을 디렉터리에서 수집합니다:

- 스킬: 현재 플러그인 루트의 `skills/*/SKILL.md` -- Glob으로 검색
- 커맨드: 슬래시 커맨드 목록 (argument-hint가 있는 스킬)

### Step 3: 데이터 병합 및 정렬

각 항목에 대해:
1. usage-data에 카운터 파일이 있으면 count와 lastUsed 읽기
2. 없으면 count=0으로 처리
3. 카테고리별로 count 내림차순 정렬

### Step 4: 통계 출력

```
[사용 통계] 추적 기간: {시작일} ~ 현재 ({N}일)

스킬 ({전체}개, 활성 {1회 이상}개):
  #1  {name}          {count}회  (최근: {상대시간})
  ...
  --- 미사용 (0회) ---
  {name}              0회

커맨드 ({전체}개, 활성 {1회 이상}개):
  #1  {name}          {count}회  (최근: {상대시간})
  ...
```

### Step 5: 추적 초기화 (--reset)

사용자가 "추적 초기화", "stats --reset" 등을 요청하면:
1. 초기화 범위를 확인
2. 현재 통계를 요약 표시
3. 확인 후 해당 카운터 파일 삭제
4. 결과 보고
