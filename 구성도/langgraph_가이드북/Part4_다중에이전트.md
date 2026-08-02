# Part 4. 다중 에이전트 시스템 구현

> 출처: WikiDocs "LangGraph 가이드북 - 에이전트 RAG with 랭그래프 [ver 1.0+]" (판다스 스튜디오), https://wikidocs.net/book/16723
> 이 문서는 원문을 그대로 옮긴 것이 아니라 핵심 개념 위주로 재구성한 정리본입니다. 각 절 제목 아래 원본 URL을 표기했습니다.
> 00_목차.md 기준 Part 4의 마지막 절은 4-2-2이며(2026-07-19 시점 책 목차), 이후 절이 추가되면 이 파일도 갱신이 필요합니다.

## 개요
Part 4는 하나의 에이전트로 모든 일을 처리하는 대신, 전문화된 여러 에이전트가 역할을 나눠 협력하는 다중
에이전트 시스템의 설계 원칙과 두 가지 핵심 구현 패턴(Subagents/Supervisor, Handoffs)을 다룬다.
(https://wikidocs.net/261606)

---

## 4-1. 다중 에이전트 시스템 개요 및 설계
원본: https://wikidocs.net/293329

### 4-1-1. 다중 에이전트 아키텍처 패턴
원본: https://wikidocs.net/293330

- 단일 에이전트에 도구가 계속 늘어나면 여러 문제가 생긴다: 모든 도구를 한 번에 로드해 컨텍스트가
  낭비되고, 도구 하나를 추가/수정할 때 전체 시스템에 영향이 가며, 한 사람(팀)이 전체를 관리해야 해서
  확장이 어려워진다. 다중 에이전트는 각 에이전트가 필요한 도구만 갖고, 독립적으로 확장·개발될 수 있게
  해 이 문제들을 완화한다.
- LangChain 1.0이 제시하는 세 가지 핵심 패턴:
  - **Subagents(Supervisor) 패턴**: 중앙 감독자 에이전트가 여러 전문 워커 에이전트를 "도구"처럼 호출해
    작업을 조율한다. 워커 에이전트를 `create_agent`로 만든 뒤 `@tool`로 감싸 Supervisor의 도구 목록에
    등록하는 방식이다.
  - **Handoffs 패턴**: 대화 상태(예: 진행 단계)에 따라 담당 에이전트가 전환되는 방식으로, 고객 지원
    센터에서 부서 간 전화를 넘기는 것에 비유된다.
  - **StateGraph 패턴**: 위 두 패턴을 `StateGraph`로 직접 구현해 세밀하게 제어하는 방식(Part 1~2에서
    다룬 저수준 구성 요소를 다중 에이전트 조율에 그대로 적용).
- 세 패턴은 상호 배타적이지 않으며, 작업의 정형성(고정된 라우팅 vs 동적 판단 필요)과 팀의 개발 방식에
  따라 선택하거나 조합해서 쓸 수 있다.

```python
@tool
def web_search(request: str) -> str:
    """실시간 웹 검색을 수행합니다."""
    result = web_agent.invoke({"messages": [HumanMessage(content=request)]})
    return result["messages"][-1].text

supervisor = create_agent(model="openai:gpt-4.1-mini", tools=[web_search, wiki_search])
```

### 4-1-2. 에이전트 간 통신 메커니즘
원본: https://wikidocs.net/293331

여러 에이전트가 정보를 주고받는 네 가지 메커니즘을 다룬다.

- **공유 상태(Shared State)**: `StateGraph`의 `TypedDict` 상태를 여러 노드(=여러 역할의 에이전트)가
  함께 읽고 쓰는 가장 기본적인 방식. 예를 들어 `research_result`는 리서처 노드가, `analysis_result`는
  분석가 노드가 각각 채우는 식으로 역할을 나눈다. 여기서도 "노드는 변경된 키만 반환한다"는 Part 1의
  State 원칙이 그대로 지켜져야 한다.
- **메시지 기반 통신**: `MessagesState`의 `messages` 리스트를 공유 대화 기록으로 사용해, 에이전트들이
  서로의 발화를 이어받아 처리하는 방식.
- **`Command` 객체를 통한 상태 전환**: 도구나 노드가 `Command(update=..., goto=...)`를 반환하면 상태
  갱신과 다음 담당(에이전트/노드)으로의 전환을 동시에 수행할 수 있다 — Handoffs 패턴의 핵심 메커니즘.
- **`@tool` 래핑을 통한 에이전트 간 호출**: 한 에이전트를 함수처럼 호출하는 도구로 감싸 다른(Supervisor)
  에이전트가 사용하게 하는 방식 — Subagents 패턴의 핵심 메커니즘.
- 여기에 더해 `InMemorySaver` 같은 체크포인터로 여러 에이전트가 관여하는 대화 전체의 히스토리를 세션
  단위로 일관되게 유지하는 방법도 함께 다룬다.

```python
class CollaborationState(TypedDict):
    task: str
    research_result: Optional[str]   # Researcher가 채움
    analysis_result: Optional[str]   # Analyst가 채움
    messages: Annotated[list, add_messages]
```

## 4-2. 전문화된 에이전트 구현
원본: https://wikidocs.net/293333

Part 4-1에서 소개한 두 패턴(Subagents, Handoffs)을 실전 시나리오로 구현하는 실습 절.

### 4-2-1. Subagents (Supervisor) 패턴
원본: https://wikidocs.net/293335

- 구현은 3단계: (1) 검색 도구 준비 — `TavilySearchResults`(실시간 웹 검색, API 키 필요, 무료 월 1,000회)
  와 `WikipediaQueryRun`(백과사전 검색, API 키 불필요)처럼 검색 도메인별로 도구를 마련, (2)
  `create_agent(model=..., tools=[...], system_prompt=...)`로 도메인별 워커 에이전트 생성(예: 웹 검색
  전문 에이전트, 위키백과 전문 에이전트), (3) 각 워커 에이전트를 `@tool`로 감싸 Supervisor의 도구
  목록에 등록하고 `create_agent`로 Supervisor를 생성.
- 이 패턴의 특징: **중앙 집중식 제어**(모든 라우팅 판단이 Supervisor를 거침), **병렬 실행 가능**
  (Supervisor가 여러 워커를 동시에 호출할 수 있음), **도구로서의 에이전트**(Supervisor 입장에서 워커
  에이전트는 그냥 하나의 도구로 보인다는 점이 이 패턴을 간결하게 만드는 핵심).
- 연습문제로 ArXiv 논문 검색 도구를 추가한 세 번째 워커 에이전트를 Supervisor에 통합하는 과제가
  제시된다.

```python
web_search_agent = create_agent(
    model="openai:gpt-4.1-mini",
    tools=[tavily_search],
    system_prompt="당신은 웹 검색 전문가입니다.",
)
```

### 4-2-2. Handoffs 패턴
원본: https://wikidocs.net/293339

- 고객 지원 시나리오(정보 수집 → 문제 분류 → 해결)를 세 단계로 나눠 구현한다: `AgentState`를 상속한
  `SupportState`에 `current_step`(현재 담당 단계를 나타내는 Literal 타입)과 `warranty_status`,
  `issue_type` 같은 도메인 필드를 추가한다.
- 각 단계 전환은 **전환 도구**(예: `record_warranty_status`)가 `Command(update={...})`를 반환하는
  방식으로 이뤄진다 — 도구 호출 하나가 상태 갱신과 다음 단계로의 이동을 동시에 수행한다.
- 특징 정리: **상태 기반 전환**(`current_step` 값이 지금 누가 담당인지 결정), **순차적 처리**(정보
  수집→분류→해결의 단계적 진행), **사용자와의 직접 대화**(각 단계의 에이전트가 사용자와 직접 소통,
  Subagents 패턴처럼 감독자를 거치지 않음), `@wrap_model_call` 미들웨어로 현재 단계에 맞는 시스템
  프롬프트·도구 집합을 동적으로 바꿔 끼운다.
- **Subagents vs Handoffs**: Subagents는 "감독자가 작업을 여러 전문가에게 나눠주고 결과를 취합"하는
  구조(병렬·중앙집중), Handoffs는 "한 번에 한 명의 담당자가 사용자와 직접 대화하며 상태에 따라 담당이
  바뀌는" 구조(순차·분산)로 대비된다. 연습문제로 결제 처리 단계를 워크플로우에 추가하는 과제가 제시된다.

```python
class SupportState(AgentState):
    current_step: Literal["warranty_collector", "issue_classifier", "resolution_specialist"]
    warranty_status: str | None

@tool
def record_warranty_status(status: Literal["in_warranty", "out_of_warranty"]):
    """보증 상태를 기록하고 문제 분류 단계로 이동합니다."""
    return Command(update={"warranty_status": status, "current_step": "issue_classifier"})
```
