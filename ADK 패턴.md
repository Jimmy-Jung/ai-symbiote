ADK(Agent Development Kit)에서 말하는 패턴들은 **에이전트의 실행 전략(Execution Strategy)**을 구조화한 것이다. 단순한 디자인 패턴이 아니라, **LLM + Tool 기반 시스템에서의 “작업 분해 및 실행 방식”**에 가깝다.

아래에서 주요 패턴들을 구조 / 언제 쓰는지 / 장단점 기준으로 정리한다.

⸻

1. Sequential Pipeline Pattern

구조

Task → Step1 → Step2 → Step3 → Result

설명
	•	작업을 순차적으로 단계별 처리
	•	각 단계의 output이 다음 단계의 input

예시

문서 생성:
1. 데이터 수집
2. 요약
3. 보고서 작성

특징
	•	단순하고 예측 가능
	•	디버깅 용이

단점
	•	병렬 처리 불가 → 느림
	•	중간 단계 실패 시 전체 영향

사용 시점
	•	단계 간 의존성이 강할 때
	•	deterministic workflow 필요할 때

⸻

2. Parallel Fan-Out / Gather Pattern

구조

        → Task A →
Input → → Task B → → Gather → Result
        → Task C →

설명
	•	작업을 여러 하위 작업으로 동시에 분산(fan-out)
	•	결과를 다시 모아서(gather) 통합

예시

리서치:
- 여러 웹사이트 동시에 검색
- 결과 취합 후 요약

특징
	•	성능 향상 (latency 감소)
	•	다양한 관점 확보 가능

단점
	•	결과 통합(gather) 복잡
	•	중복/충돌 처리 필요

사용 시점
	•	독립적인 작업 병렬 처리
	•	IO-bound 작업

⸻

3. Map-Reduce Pattern

구조

Input → Map → Intermediate → Reduce → Result

설명
	•	데이터를 여러 조각으로 나누고(Map)
	•	결과를 합쳐서(Reduce) 최종 결과 생성

예시

대량 문서 요약:
- 각 문서 요약 (Map)
- 전체 요약 (Reduce)

특징
	•	대규모 데이터 처리에 적합
	•	확장성 뛰어남

단점
	•	Reduce 단계에서 정보 손실 가능
	•	설계 난이도 있음

사용 시점
	•	large-scale 텍스트 처리
	•	batch processing

⸻

4. Routing Pattern

구조

          → Agent A →
Input → Router → Agent B → → Result
          → Agent C →

설명
	•	입력을 분석해서 적절한 에이전트로 라우팅

예시

고객 문의:
- 결제 → Billing Agent
- 기술 → Tech Agent

특징
	•	specialization 가능
	•	정확도 향상

단점
	•	라우팅 오류 리스크
	•	분기 로직 관리 필요

사용 시점
	•	다양한 유형의 요청 처리
	•	multi-agent 환경

⸻

5. Tool-Using (ReAct) Pattern

구조

Reason → Act → Observe → Repeat

설명
	•	LLM이 reasoning하면서 필요한 tool을 선택
	•	결과를 보고 다음 행동 결정

특징
	•	가장 핵심적인 ADK 패턴
	•	동적 의사결정

단점
	•	실행 비용 증가
	•	loop 관리 필요

사용 시점
	•	불확실한 문제
	•	탐색 기반 작업

⸻

6. Reflection Pattern

구조

Generate → Critique → Improve → Result

설명
	•	결과를 스스로 평가하고 개선

예시

코드 생성 → 리뷰 → 수정

특징
	•	품질 향상
	•	self-correction

단점
	•	latency 증가
	•	비용 증가

사용 시점
	•	정확도 중요한 작업
	•	코드/문서 생성

⸻

7. Planning Pattern (Plan-and-Execute)

구조

Plan → Execute Steps → Result

설명
	•	먼저 전체 계획을 세우고
	•	계획에 따라 실행

특징
	•	안정적 실행
	•	구조적 작업에 적합

단점
	•	계획이 틀리면 전체 실패
	•	유연성 낮음

사용 시점
	•	복잡하지만 구조화 가능한 문제

⸻

8. Multi-Agent Collaboration Pattern

구조

Agent A ↔ Agent B ↔ Agent C → Result

설명
	•	여러 에이전트가 협업

역할 예시
	•	Planner
	•	Executor
	•	Reviewer

특징
	•	역할 분리
	•	확장성 높음

단점
	•	coordination 비용
	•	상태 관리 복잡

사용 시점
	•	복잡한 시스템
	•	조직형 AI

⸻

9. Hierarchical Pattern

구조

        Manager Agent
            ↓
   ┌───────────────┐
   ↓               ↓
Worker A       Worker B

설명
	•	상위 에이전트가 하위 에이전트 관리

특징
	•	구조적 제어
	•	확장 용이

단점
	•	bottleneck 가능성
	•	설계 복잡

⸻

10. Event-Driven Pattern

구조

Event → Trigger → Agent Action

설명
	•	이벤트 기반으로 실행

예시
	•	이메일 수신 → 자동 처리

특징
	•	비동기 처리
	•	실시간 대응

⸻

11. Retry / Fallback Pattern

구조

Try → Fail → Retry or Fallback → Result

설명
	•	실패 시 재시도 또는 대체 경로

특징
	•	안정성 향상

⸻

12. Human-in-the-Loop Pattern

구조

Agent → Human Review → Continue

설명
	•	중요한 단계에서 인간 개입

특징
	•	리스크 제어
	•	품질 보장

⸻

패턴 간 관계 요약

패턴	성격
Sequential	기본 흐름
Parallel	성능 최적화
Map-Reduce	대규모 처리
Routing	분기
ReAct	핵심 실행 루프
Reflection	품질 개선
Planning	전략 기반
Multi-Agent	협업
Hierarchical	구조화
Event-driven	트리거 기반
Retry/Fallback	안정성
Human-in-loop	통제


⸻

핵심 정리

ADK에서 패턴은 결국 세 가지 축으로 정리된다:

1. 실행 방식
	•	Sequential / Parallel / MapReduce

2. 의사결정 방식
	•	Routing / ReAct / Planning

3. 시스템 구조
	•	Multi-Agent / Hierarchical / Event-driven

⸻