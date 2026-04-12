# Flows

이 문서는 프로젝트의 주요 흐름을 Mermaid로 한눈에 보여주기 위한 문서입니다.

## 시스템 상위 흐름

<!-- AI-SYMBIOTE:START flows:system-flow -->
```mermaid
flowchart LR
    A["사용자 요청"] --> B["적절한 스킬 선택"]
    B --> C["shared/ 원본 수정"]
    C --> D["테스트 실행"]
    D --> E["build-all.sh"]
    E --> F["Claude/Codex 번들 반영"]
```
<!-- AI-SYMBIOTE:END flows:system-flow -->

## 데이터 흐름

<!-- AI-SYMBIOTE:START flows:data-flow -->
```mermaid
flowchart TD
    A["프로젝트 코드"] --> B["setup/evolve 감지"]
    B --> C["manifest.json / context.md"]
    C --> D["SessionStart 주입"]
    D --> E["에이전트 작업"]
    E --> F["harness-log.jsonl"]
    F --> G["stats / gc / 다음 세션 분석"]
```
<!-- AI-SYMBIOTE:END flows:data-flow -->

## 사용자 / 운영자 흐름

<!-- AI-SYMBIOTE:START flows:user-or-operator-flow -->
```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Skill as Skill
    participant Build as Build Scripts
    Dev->>Skill: shared/ 또는 docs/ 수정
    Dev->>Build: bash scripts/build-all.sh
    Build-->>Dev: plugins/ + dist/ 갱신
    Dev->>Dev: 결과 확인 및 테스트
```
<!-- AI-SYMBIOTE:END flows:user-or-operator-flow -->

## 운영 흐름

<!-- AI-SYMBIOTE:START flows:operational-flow -->
```mermaid
flowchart TD
    A["공용 변경"] --> B["shared/ 수정"]
    B --> C["테스트"]
    C --> D["build-claude.sh / build-codex.sh"]
    D --> E["번들 산출물 생성"]
    E --> F["설치 또는 업데이트"]
```
<!-- AI-SYMBIOTE:END flows:operational-flow -->
