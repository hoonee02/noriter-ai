# Part 2. ReAct 에이전트 구현

> 출처: WikiDocs "LangGraph 가이드북 - 에이전트 RAG with 랭그래프 [ver 1.0+]" (판다스 스튜디오), https://wikidocs.net/book/16723
> 이 문서는 원문을 그대로 옮긴 것이 아니라 핵심 개념 위주로 재구성한 정리본입니다. 각 절 제목 아래 원본 URL을 표기했습니다.

## 개요
Part 2는 ReAct(Reasoning + Acting) 패러다임의 개념부터, `create_agent`를 이용한 빠른 구현, `StateGraph`
기반 커스텀 구현, Human-in-the-Loop, Guardrails(안전장치)까지 도구 사용 에이전트를 만드는 전체 과정을
다룬다. (https://wikidocs.net/261605)

---

## 2-1. ReAct 에이전트 개요
원본: https://wikidocs.net/261608

### 2-1-1. ReAct 패러다임 소개
원본: https://wikidocs.net/261612

#### 2-1-1-1. ReAct 기본 개념과 탄생 배경
원본: https://wikidocs.net/294436

- ReAct = REAsoning(추론) + ACTing(행동)의 합성어로, 2022년 프린스턴대·구글 리서치 논문에서 제안된
  패러다임이다. LLM이 한 번에 최종 답을 내놓는 대신 "생각(Think) → 행동(Act, 도구 호출) → 관찰
  (Observe, 도구 결과 확인)"을 반복하며 문제를 푼다.
- 전통적 LLM 단독 호출의 한계: 학습 데이터 시점 이후의 실시간 정보에 답할 수 없고, 복잡한 수치 계산도
  추론만으로 처리해 오차가 생길 수 있다.
- ReAct 에이전트는 웹 검색·계산기 같은 외부 도구를 호출해 이 한계를 보완한다. LangChain의
  `create_agent(model=..., tools=[...], system_prompt=...)`가 가장 간단한 구현 진입점이다.

```python
@tool
def calculator(expression: str) -> str:
    return str(eval(expression))

agent = create_agent(model="openai:gpt-4.1-mini", tools=[tavily_search, calculator])
```

#### 2-1-1-2. 2025년 ReAct 발전 동향
원본: https://wikidocs.net/294437

- 2024~2025년 ReAct의 세 가지 발전 방향: (1) **멀티모달 ReAct** — 이미지·음성·비디오까지 입력으로 받아
  도구를 호출(예: 차트 이미지를 읽고 계산 도구로 성장률 산출), (2) **Self-Correcting ReAct** — 에이전트가
  자기 답변을 스스로 검증하고 부족하면 재생성하는 패턴(StateGraph로 구현), (3) **Collaborative ReAct** —
  여러 전문 에이전트가 협력해 하나의 작업을 나눠 처리.
- 비용 관리도 중요한 화두로 다뤄지며, API 호출 횟수·토큰 사용량을 추적해 무분별한 반복 호출을 막는
  전략이 함께 소개된다.

#### 2-1-1-3. ReAct vs 전통적 방식 상세 비교
원본: https://wikidocs.net/294438

- 세 가지 비교 시나리오를 통해 차이를 보여준다: (1) 복잡한 수학 문제 — 전통 방식은 LLM이 암산하듯 추론해
  반올림 오차가 나지만, ReAct는 계산기 도구로 정확한 값을 구한다. (2) 실시간 정보가 필요한 질문 — 전통
  방식은 답할 수 없지만 ReAct는 검색 도구로 최신 정보를 가져온다. (3) 다단계 추론 작업 — ReAct는 검색과
  계산을 조합해 "계산 + 업계 비교 분석" 같은 복합 결과까지 만들어낸다.
- 공통적으로 ReAct 방식이 더 느리고(여러 번의 LLM+도구 호출) 비용이 크지만, 정확도와 최신성에서 뚜렷한
  우위를 보인다는 트레이드오프가 강조된다.

#### 2-1-1-4. 성능 벤치마크 및 실습 가이드
원본: https://wikidocs.net/294439

- 실습으로 커스텀 도구(계산기, 날짜 조회, 단위 변환 등)를 `@tool`로 정의해 에이전트에 연결하는 과정을
  다룬다.
- **무한 루프 방지**: 에이전트가 Think→Act→Observe를 무한 반복하지 않도록 `recursion_limit`(최대
  super-step 수)을 설정해야 한다. 값이 너무 작으면 정상 작업도 조기 종료되고, 너무 크면 오류 시 자원을
  낭비하므로 작업 복잡도에 맞춰 조정한다.
- 에러 처리 미들웨어(도구 호출 실패 시 재시도/폴백)와, 검색+계산+요약을 결합한 "종합 리서치 에이전트"
  실습으로 마무리된다.

### 2-1-2. LangGraph에서의 ReAct 구현 방법
원본: https://wikidocs.net/261613

#### 2-1-2-1. StateGraph 구성요소와 ReAct 패턴 매핑
원본: https://wikidocs.net/294465

- `StateGraph`의 State·Node·조건부 Edge가 ReAct의 각 단계에 정확히 대응된다: **State**는 에이전트의
  기억 저장소(`MessagesState`를 확장해 `thoughts`/`actions`/`observations`를 `Annotated[list, add]`로
  누적, `iteration_count`/`max_iterations`로 반복 제한, `final_answer`/`is_complete`로 종료 판정),
  **Node**는 Think(추론) 노드·Act(도구 실행, `ToolNode`) 노드·Observe(결과 반영) 노드로 나뉘고,
  **조건부 Edge**는 "도구를 더 호출할지, 답변을 종료할지"를 판단하는 라우팅 함수로 구현된다.
- 노드는 상태 전체가 아니라 변경된 필드만 반환하고, 리듀서(`operator.add`)가 사고/행동/관찰 기록을
  계속 누적해 나간다는 점은 Part 1의 State 설계 원칙과 동일하게 적용된다.

```python
class AdvancedReActState(MessagesState):
    thoughts: Annotated[list[str], operator.add]
    actions: Annotated[list[dict], operator.add]
    observations: Annotated[list[str], operator.add]
    iteration_count: int
    max_iterations: int
    final_answer: str
    is_complete: bool
```

#### 2-1-2-2. 도구 통합 아키텍처 및 Function Calling
원본: https://wikidocs.net/294466

- 도구 정의 방식 2가지: (1) `langchain-tavily`의 `TavilySearch`처럼 패키지가 제공하는 완성된 도구를
  바로 사용(`max_results`, `topic`, `search_depth`, `time_range`, `include/exclude_domains` 등으로
  세밀 조정), (2) `@tool` 데코레이터로 직접 함수를 작성해 커스텀 도구로 등록(함수의 docstring이 LLM에게
  도구 설명으로 전달되므로 명확히 작성해야 함).
- `llm.bind_tools(tools)`로 LLM에 도구 스펙을 바인딩하면 모델이 Function Calling으로 어떤 도구를 어떤
  인자로 호출할지 결정하고, LangGraph의 `ToolNode`가 실제 도구 실행을 담당한다.
- 여러 도구 호출을 한 번에 요청하는 **병렬 도구 호출(Parallel Tool Calls)**도 지원되며, `stream_mode`로
  에이전트의 추론 과정(어떤 도구를 왜 호출했는지)을 실시간 추적할 수 있다.

#### 2-1-2-3. 메모리 관리 및 성능 최적화
원본: https://wikidocs.net/294467

- 체크포인터(`InMemorySaver`/`SqliteSaver`)로 에이전트의 대화 상태를 저장·복원한다 — 기본 구조는
  `agent` 노드(LLM+도구 바인딩 호출) → 조건부 엣지(`tool_calls` 존재 여부로 `tools`행 or `END`) →
  `ToolNode`(도구 실행) → 다시 `agent`로 돌아가는 순환 그래프.
- **컨텍스트 윈도우 관리**: 대화가 길어지면 메시지 수를 제한하거나, 오래된 메시지를 요약해 압축하는
  전략으로 토큰 비용과 지연시간을 관리한다.
- 스트리밍 응답과 실행 시간·토큰 사용량 모니터링을 결합해 프로덕션 환경에서 성능을 추적하는 방법도
  함께 다룬다. 체크포인터 선택 기준은 Part 1-4-2와 동일(테스트: InMemory, 로컬: Sqlite, 프로덕션: Postgres).

---

## 2-2. create_agent로 빠른 시작
원본: https://wikidocs.net/261609

`create_agent`는 도구를 사용하는 ReAct 에이전트를 그래프를 직접 조립하지 않고 한 줄로 만들어주는
LangChain의 고수준 헬퍼다. 내부적으로는 Part 2-1-2에서 본 "LLM+도구 바인딩 노드 ↔ ToolNode"의 순환
그래프와 동등한 구조가 자동 구성된다.

### 2-2-1. 도구 정의와 에이전트 생성
원본: https://wikidocs.net/261614

- 커스텀 도구는 `@tool` 데코레이터로 만든다. 함수의 **docstring이 곧 도구 설명**이 되어 LLM이 언제 그
  도구를 호출할지 판단하는 근거가 되므로 명확하게 작성해야 한다.
- 보안 팁: 계산기 도구처럼 `eval`을 쓸 때는 정규식으로 허용 문자를 제한하고 `eval(expr, {"__builtins__": {}}, {})`
  형태로 내장 함수 접근을 차단하는 것이 최소한의 안전장치이며, 프로덕션에서는 `numexpr`/`sympy` 같은
  전용 수식 평가 라이브러리 사용을 권장한다.
- 전체 흐름: `@tool`로 커스텀 도구 정의 → `TavilySearch` 같은 패키지 도구 추가 → `init_chat_model`로
  모델 초기화 → `create_agent(model=..., tools=[...])`로 에이전트 생성 → `agent.invoke(...)`로 실행 →
  필요 시 체크포인터를 붙여 대화 기억 유지.

```python
@tool
def calculator(expression: str) -> str:
    """수학 계산을 수행합니다. 사칙연산, 거듭제곱, 괄호 등을 지원합니다."""
    import re
    if not re.match(r'^[0-9+\-*/().%\s]+$', expression):
        return "오류: 허용되지 않는 문자가 포함되어 있습니다."
    return f"{expression} = {eval(expression, {'__builtins__': {}}, {})}"

agent = create_agent(model=init_chat_model("openai:gpt-4.1-mini"), tools=[calculator, tavily_search])
```

### 2-2-2. 스트리밍, 미들웨어, 디버깅
원본: https://wikidocs.net/261615

- `invoke()`는 완료까지 기다렸다가 결과만 반환하지만, `stream()`은 노드별 중간 출력을 실시간으로 흘려
  추론 과정(모델이 도구를 호출하는 순간, 도구 결과가 돌아오는 순간)을 관찰할 수 있게 해준다.
- **미들웨어**는 에이전트 실행 파이프라인에 가로채기 로직을 끼워 넣는 기능으로, 대표 3종: `PIIMiddleware`
  (개인정보 자동 마스킹/차단), `SummarizationMiddleware`(길어진 대화를 자동 요약해 컨텍스트 절약),
  `HumanInTheLoopMiddleware`(특정 도구 호출 전에 사람의 승인을 요구 — Part 2-4와 연결됨).
- 에러 처리는 두 층위로 나뉜다: 도구 레벨(개별 `@tool` 함수 내부에서 예외를 잡아 에러 메시지를 반환값
  으로 돌려줌 — 에이전트가 이를 보고 재시도/대안 판단 가능)과 에이전트 레벨(전체 실행 자체가 실패했을
  때의 폴백 처리).

```python
for chunk in agent.stream({"messages": [{"role": "user", "content": "..."}]}):
    for node_name, output in chunk.items():
        print(node_name, output)
```

## 2-3. StateGraph 커스텀 에이전트
원본: https://wikidocs.net/261610

`create_agent`가 빠른 구현을 제공한다면, `StateGraph`로 직접 구현하는 방식은 상태 구조·노드 로직·라우팅
전체를 세밀하게 통제하고 싶을 때 사용한다. Part 2-1-2-1에서 다룬 State/Node/Edge ↔ ReAct 매핑이 여기서
실제 구현으로 이어진다.

### 2-3-1. State 설계와 그래프 구조
원본: https://wikidocs.net/261616

- State 설계는 두 갈래로 나뉜다: (1) 대화 메시지만 다루면 충분할 때는 `MessagesState`를 그대로 사용
  (내부적으로 메시지 리스트를 자동 누적 관리), (2) 반복 횟수 제한(`tool_call_count`, `max_iterations`),
  노드 간 공유 데이터, 별도 결과 필드 등이 필요할 때만 `MessagesState`를 상속해 커스텀 필드를 추가한다
  — 책은 "대부분의 경우 `MessagesState`만으로 충분하니, 정말 필요할 때만 커스텀 State를 고려하라"는
  점을 강조한다.
- 그래프 구조는 도구·모델을 준비(`TavilySearch`, `@tool` 계산기 등을 `init_chat_model` 기반 LLM에
  바인딩) → `reasoning` 노드(LLM 호출) 구현 → 조건부 라우팅 함수(도구 호출 여부로 `tools`/`END` 분기)
  → 그래프 조립·컴파일 순서로 진행되며, 이렇게 직접 만든 결과가 `create_agent`가 내부적으로 만드는
  구조와 동일하다는 점을 비교로 보여준다.

```python
class AgentState(MessagesState):
    tool_call_count: int
    max_iterations: int
```

### 2-3-2. 고급 기능: 에러 처리, 메모리, 스트리밍
원본: https://wikidocs.net/261617

- **에러 처리**: 도구 함수 내부에서 예외를 잡아 LLM이 이해할 수 있는 에러 메시지 문자열로 반환하는
  것이 기본 패턴이며, 한 걸음 더 나아가 주 도구(예: Tavily 검색)가 실패하면 대체 도구(예: DuckDuckGo)로
  자동 전환하는 **Fallback 패턴**도 다룬다.
- **최대 반복 제한**: `iteration_count` 같은 필드를 커스텀 State에 추가해 매 턴마다 증가시키고, 조건부
  라우팅에서 이 값이 한도를 넘으면 강제로 종료시켜 무한 루프를 방지한다 — 커스텀 State가 필요한 대표
  사례로 제시된다.
- **메모리**: `InMemorySaver`(개발용)와 `SqliteSaver`(프로덕션용)를 세션(`thread_id`) 단위로 붙이는
  방식은 Part 1-4와 동일하며, **스트리밍**은 노드별 스트리밍과 이벤트 기반 스트리밍 두 방식을 조합해
  "프로덕션 레디(production-ready)"한 에이전트 예제로 마무리한다.

```python
@tool
def search_with_fallback(query: str) -> str:
    """웹 검색을 수행합니다. 주 검색 엔진 실패 시 대체 검색을 시도합니다."""
    try:
        return TavilySearch(max_results=3).invoke(query)
    except Exception:
        return DuckDuckGoSearchRun().invoke(query)
```

## 2-4. Human-in-the-Loop
원본: https://wikidocs.net/261611

민감하거나 되돌리기 어려운 행동(결제, 이메일 발송, 데이터 삭제 등)을 실행하기 전에 사람의 승인을 받도록
그래프 실행을 일시 정지시키는 패턴이다.

### 2-4-1. interrupt()와 승인 워크플로우
원본: https://wikidocs.net/261618

- `langgraph.types.interrupt(값)`을 노드 안에서 호출하면 그래프 실행이 그 지점에서 즉시 멈추고, 전달한
  값(질문·컨텍스트 등 JSON 직렬화 가능한 데이터)이 결과의 `__interrupt__` 필드에 담겨 호출자에게
  반환된다. 상태는 체크포인터에 저장되므로, 이후 같은 `thread_id`로 `Command(resume=응답값)`을 넘겨
  `invoke`하면 `interrupt()` 호출 지점이 그 `resume` 값을 돌려받은 것처럼 이어서 실행된다.
- 기본 승인 패턴: 노드에서 `interrupt({"message": ..., "action": ..., "options": ["approve", "reject"]})`
  로 사람에게 승인 여부를 묻고, 반환값이 `"approve"`면 정상 진행 메시지를, 아니면 거부 메시지를 반환한다.
- **필수 전제조건**: `interrupt()`가 동작하려면 그래프를 `compile(checkpointer=...)`로 컴파일할 때
  반드시 체크포인터가 지정돼 있어야 하며, `thread_id`로 어느 세션이 어느 지점에서 멈춰 있는지 구분한다.
  `create_agent`를 쓰는 경우에는 `HumanInTheLoopMiddleware`로 같은 패턴을 더 간결하게 적용할 수 있다.

```python
def ask_approval(state: MessagesState) -> dict:
    response = interrupt({"message": "승인하시겠습니까?", "action": state["messages"][-1].content})
    if response == "approve":
        return {"messages": [AIMessage(content="작업이 승인되었습니다.")]}
    return {"messages": [AIMessage(content="작업이 거부되었습니다.")]}

agent = graph.compile(checkpointer=InMemorySaver())  # checkpointer 필수
```

### 2-4-2. 고급 패턴과 Interrupt 규칙
원본: https://wikidocs.net/261619

- **조건부 라우팅 확장**: 단순 승인/거부를 넘어 승인(`approve`)·수정(`edit`, 수정된 내용으로 추론 노드
  재시도)·거부(`reject`)·상위 에스컬레이션(`escalate`) 네 갈래로 분기하는 패턴을 `Command(goto=...,
  update=...)`로 구현한다 — `Command`를 반환하면 일반 딕셔너리 반환과 달리 다음 노드를 동적으로
  지정하면서 동시에 상태를 갱신할 수 있다.
- **Interrupt 4대 규칙**: (1) `interrupt()` 호출을 `try/except`로 감싸지 말 것(재개 메커니즘과 충돌),
  (2) 재개 시 노드 함수가 처음부터 다시 실행되므로 여러 `interrupt()`를 쓸 때 **호출 순서를 일관되게
  유지**할 것, (3) `interrupt()`에 전달/반환되는 값은 **JSON 직렬화 가능한 값만** 사용할 것, (4)
  `interrupt()` 이전에 실행되는 코드(특히 부수 효과가 있는 코드)는 재개 시 다시 실행되므로 **멱등성
  (idempotency)을 보장**할 것 — 이는 Part 1-7-2의 `@task` 규칙(Durable Execution)과 같은 맥락이다.
- 마지막으로 `StateGraph`로 직접 구현하는 방식과 `HumanInTheLoopMiddleware`로 `create_agent` 위에서
  간결하게 구현하는 방식을 비교하며, 세밀한 제어가 필요하면 전자를, 빠른 구현이 우선이면 후자를
  권장한다.

## 2-5. Guardrails & Safety
원본: https://wikidocs.net/319079

에이전트가 위험하거나 부적절한 입력/출력을 다루지 않도록 보호하는 세 겹의 가드레일 전략을 다룬다.

### 2-5-1. 결정론적 가드레일 (PII & Prompt Injection)
원본: https://wikidocs.net/319080

- 정규표현식·키워드 매칭 기반이라 비용이 거의 없고 항상 같은 결과를 내는 첫 번째 방어선이다. 예제는
  이메일·전화번호·신용카드·주민등록번호·API 키 패턴을 각각 정규식으로 정의한 `PIIDetector` 클래스로,
  `detect()`로 위치를 찾고 `redact()`/마스킹 전략으로 값을 가린다(한국 특화 패턴인 휴대전화·주민등록번호
  형식도 포함).
- 프롬프트 인젝션 방지도 같은 결정론적 접근으로 다루며, 알려진 공격 패턴 매칭과 함께 정상적인 문장에서
  오탐(False Positive)이 나지 않도록 관리하는 방법도 함께 언급된다.

```python
PATTERNS = {"email": r'[\w.%+-]+@[\w.-]+\.[a-zA-Z]{2,}', "ssn": r'\d{6}[-\s]?\d{7}'}
```

### 2-5-2. 모델 기반 가드레일 (LLM-as-Judge)
원본: https://wikidocs.net/319081

- 결정론적 규칙으로 잡기 어려운 미묘한 위반(맥락 의존적 유해성 등)은 별도 LLM을 "심사자"로 세워
  판단하게 한다. 핵심 구현 패턴은 `with_structured_output(PydanticModel)`로 LLM 응답을
  `is_safe`/`risk_level`/`reason` 같은 필드를 가진 구조화된 결과로 안정적으로 파싱하는 것이다.
- `ContentModerator` 클래스 예시는 입력 안전성 검사(유해 콘텐츠·불법 요청·개인정보 노출·시스템 조작
  시도 여부)와 출력 품질 검사(환각 여부 포함)를 각각 별도의 구조화 출력 체커로 수행하며, 매번 호출하면
  비용이 크므로 위험도가 높다고 판단되는 경우에만 선택적으로 호출하는 비용 최적화 전략도 함께 다룬다.

```python
class SafetyCheckResult(BaseModel):
    is_safe: bool
    risk_level: str
    reason: str

checker = init_chat_model("openai:gpt-4.1-nano").with_structured_output(SafetyCheckResult)
```

### 2-5-3. HITL 가드레일 (interrupt 기반)
원본: https://wikidocs.net/319082

- 세 번째이자 가장 강력한 방어선은 Part 2-4의 `interrupt()`를 그대로 가드레일로 활용하는 것이다. State에
  `requires_approval`/`approval_reason`/`is_approved` 같은 필드를 두고, 도구 목록 중 민감한 것들
  (예: `send_email`, `delete_file`)을 `SENSITIVE_TOOLS` 집합으로 미리 정의해 두었다가, 모델이 그 중
  하나를 호출하려 하면 `check_and_approve` 노드가 `interrupt()`로 실행을 멈추고 사람의 승인을 기다린다.
- `create_agent`를 쓴다면 이 전체 패턴을 `HumanInTheLoopMiddleware`로 훨씬 간결하게 구현할 수 있다는
  점도 함께 제시되며, 결정론적(2-5-1) → 모델 기반(2-5-2) → HITL(2-5-3) 세 레이어를 비용이 낮은 것부터
  순서대로 적용해 명백한 문제는 즉시 차단하고 정말 애매하거나 고위험인 경우만 사람에게 올리는 계층적
  안전 아키텍처가 Part 2-5 전체의 결론이다.

```python
SENSITIVE_TOOLS = {"send_email", "delete_file"}

class HITLState(TypedDict):
    messages: Annotated[list, add_messages]
    requires_approval: bool
    is_approved: Optional[bool]
```
