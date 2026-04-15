# Flows

이 문서는 프로젝트의 주요 흐름을 Mermaid로 한눈에 보여주기 위한 문서입니다.

## 시스템 상위 흐름

<!-- AI-SYMBIOTE:START flows:system-flow -->
```mermaid
flowchart TD
    A["사용자 요청"] --> B{"Synapse 오케스트레이터"}
    B -->|"Skill Direct Route<br/>(skill-store, messenger,<br/>evolve, setup 등)"| C["스킬 직접 실행"]
    B -->|"Intent Contract 분석"| D{"의도 분류"}
    D -->|"none"| E["직접 처리 (단순 작업)"]
    D -->|"analysis"| F1["analysis 팀<br/>Parallel Fan-Out + Hierarchical"]
    D -->|"implementation"| F2["implementation 팀<br/>Sequential Pipeline + Reflection"]
    D -->|"review"| F3["review 팀<br/>Parallel Fan-Out + Multi-Agent"]
    D -->|"planning"| F4["planning 팀<br/>Sequential Pipeline"]
    D -->|"research"| F5["research 팀<br/>Parallel Fan-Out + Routing"]
    D -->|"dynamic"| F6["dynamic 팀<br/>Routing + ReAct (fallback)"]
    F1 & F2 & F3 & F4 & F5 & F6 --> G["역할 배정<br/>Scout · Architect · Builder · Inspector"]
    G --> H{"Inspector 검증"}
    H -->|"PASS"| I["결과 전달"]
    H -->|"FAIL"| J["harness-learn.sh<br/>실수 기록 + 패턴 학습"]
    J --> G
```
<!-- AI-SYMBIOTE:END flows:system-flow -->

## 데이터 흐름

<!-- AI-SYMBIOTE:START flows:data-flow -->
```mermaid
flowchart TD
    A["프로젝트 코드 변경"] --> B["setup / evolve / security 스킬"]
    B --> C["manifest.json<br/>(스택, 설정, 플러그인 상태)"]
    B --> D["context.md<br/>(컨벤션, 하네스 규칙, 시드,<br/>Security Baseline 요약)"]
    B --> D2["security-baseline.json<br/>(점수, top risks, tools)"]

    E["SessionStart"] -->|"setup-check.sh"| F["context.md + prioritized security summary →<br/>systemMessage 주입"]
    E -->|"이전 세션 분석"| G["rule_prevented 카운터"]

    H["에이전트 작업"] -->|"PreToolUse"| I["guard-shell.sh<br/>위험 명령 + 보안 패턴 차단"]
    H -->|"PostToolUse"| J["harness-learn.sh<br/>실수 감지 + 패턴 학습"]
    H -->|"PostToolUse"| J2["security-guard.sh<br/>파일 보안 스캔"]
    H -->|"PostToolUse"| K["usage-tracker.sh<br/>사용 통계"]

    I & J -->|"이벤트 기록"| L["harness-log.jsonl (v1/v2)"]
    I & J2 -->|"보안 이벤트"| L2["security-log.jsonl"]
    J -->|"7일 내 2회+ 반복"| M["context.md에<br/>규칙 자동 추가"]
    J -->|"동일 확장자 3개+"| N["패턴 규칙 일반화"]

    D2 --> O["/security status<br/>빠른 상태 조회"]
    L2 --> O["최근 blocked/warned<br/>활동 요약"]
    D2 --> O2["state/security-tool-<br/>recommendations.json"]
    L & L2 --> P["stats 스킬<br/>(진화 지표 + 보안 텔레메트리)"]
    L --> Q["gc 스킬<br/>(30일+ 미사용 정리)"]
    L --> R["다음 세션<br/>rule_prevented 분석"]
```
<!-- AI-SYMBIOTE:END flows:data-flow -->

## 사용자 / 운영자 흐름

<!-- AI-SYMBIOTE:START flows:user-or-operator-flow -->
```mermaid
sequenceDiagram
    participant Dev as 개발자
    participant CLI as Claude/Codex CLI
    participant Hook as Hooks
    participant State as ~/ai-symbiote/{slug}/

    Dev->>CLI: 스킬 호출 (/ai-symbiote:setup, /ai-symbiote:security 등)
    CLI->>Hook: SessionStart → setup-check.sh
    Hook->>State: context.md 로드 → systemMessage 주입
    CLI->>CLI: Synapse가 의도 분석 → 팀 구성

    rect rgb(245, 250, 255)
        Dev->>CLI: /ai-symbiote:security scan
        CLI->>State: security-baseline.json 갱신
        CLI->>State: context.md Security Baseline 블록 동기화
        CLI-->>Dev: 점수 + 상위 위험 3개 + 선택 도구 추천
    end

    rect rgb(240, 240, 255)
        Note over CLI,Hook: 작업 루프
        CLI->>Hook: PreToolUse(Bash) → guard-shell.sh
        Hook-->>CLI: 위험 명령/보안 위반 차단 또는 허용
        CLI->>CLI: 에이전트 작업 수행
        CLI->>Hook: PostToolUse(Write|Edit) → security-guard.sh
        Hook-->>CLI: 보안 경고 (시크릿, SQLi, XSS)
        CLI->>Hook: PostToolUse(Write|Edit) → harness-learn.sh
        Hook->>State: harness-log.jsonl + security-log.jsonl 기록
    end

    CLI-->>Dev: 결과 전달
    Dev->>Dev: 코드 확인 및 테스트
```
<!-- AI-SYMBIOTE:END flows:user-or-operator-flow -->

## 운영 흐름

<!-- AI-SYMBIOTE:START flows:operational-flow -->
```mermaid
flowchart TD
    subgraph "개발"
        A["shared/ 수정"] --> B["tests/test-*.sh 실행"]
        B --> C["bash scripts/build-all.sh"]
        C --> D["python3 scripts/version_sync.py --check"]
    end
    subgraph "CI (ci.yml)"
        E["PR / push main"] --> F["version_sync.py --check"]
        F --> G["build-all.sh"]
        G --> H["git diff --exit-code"]
        H -->|"변경 있음"| I["CI FAIL<br/>(빌드 산출물 미갱신)"]
        H -->|"변경 없음"| J["CI PASS"]
    end
    subgraph "릴리즈 (release.yml)"
        K["VERSION/CHANGELOG 변경<br/>또는 수동 트리거"] --> L["버전 검증 + 빌드"]
        L --> M["CHANGELOG에서<br/>릴리즈 노트 추출"]
        M --> N["git tag v{VERSION}"]
        N --> O["GitHub Release 생성"]
    end
    D --> E
    J --> K
```
<!-- AI-SYMBIOTE:END flows:operational-flow -->
