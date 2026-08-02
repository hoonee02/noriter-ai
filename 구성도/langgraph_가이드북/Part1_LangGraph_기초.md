# Part 1. 랭그래프 LangGraph 기초

원본: https://wikidocs.net/261576 (Part 1 개요)

LangGraph의 개념, 설치, StateGraph의 핵심 구성요소(상태·노드·엣지), 메모리/체크포인터, 서브그래프,
스트리밍, Functional API까지 프레임워크의 기초 전체를 다루는 파트.

## 1-1. 랭그래프 LangGraph 소개
원본: https://wikidocs.net/261577

### 1-1-1. LangGraph 첫걸음
원본: https://wikidocs.net/261584

- LangGraph는 노드(작업 단위)와 엣지(연결)로 워크플로우를 구성하는 그래프 기반 프레임워크.
- 최소 예제 구조: `TypedDict`로 State 스키마 정의 → 상태를 받아 갱신된 딕셔너리를 반환하는 노드 함수 작성
  → `StateGraph(State)`에 `add_node`/`add_edge`로 START→노드→END 흐름을 연결 → `compile()` 후 `invoke()`로 실행.
- 핵심 포인트: 구조는 단순하지만(START→작업→END), 모든 노드가 동일한 State를 공유하며 읽고 쓴다는 점이
  LangGraph 이해의 출발점.

```python
class MyState(TypedDict):
    message: str

def say_hello(state):
    return {"message": "Hello, LangGraph!"}

graph = StateGraph(MyState)
graph.add_node("hello", say_hello)
graph.add_edge(START, "hello")
graph.add_edge("hello", END)
app = graph.compile()
```

### 1-1-2. LangGraph와 LangChain의 차이점
원본: https://wikidocs.net/261585

- **목적**: LangGraph는 복잡한 워크플로우·다단계 의사결정 프로세스 구현에 특화. LangChain은 LLM과 외부
  도구의 체인 구성, 빠른 프로토타이핑에 중점.
- **구조**: LangGraph는 노드/엣지의 그래프 구조로 분기·반복을 직관적으로 표현. LangChain은 체인/에이전트
  기반의 상대적으로 선형적인 구조.
- **상태 관리**: LangGraph는 명시적이고 세밀한 상태 제어가 가능(State를 직접 설계·갱신). LangChain은
  암시적·자동화된 상태 관리로 개발은 단순하지만 세부 제어는 제한적.
- **유연성/학습 곡선**: LangGraph는 커스텀 로직 구현의 자유도가 높은 대신 그래프·상태 개념을 익혀야 해서
  학습 곡선이 상대적으로 가파름. LangChain은 미리 정의된 컴포넌트 덕분에 진입장벽이 낮음.
- **용도**: 다중 에이전트·복잡한 의사결정이 필요하면 LangGraph, 단순 LLM 애플리케이션·RAG 프로토타입엔
  LangChain이 적합 — 상호 배타적이라기보다 프로젝트 복잡도에 따른 선택의 문제.

### 1-1-3. LangGraph를 사용해야 하는 이유
원본: https://wikidocs.net/261586

- 복잡한 다단계 의사결정 로직을 그래프로 표현하기 쉬움.
- 각 단계를 세밀하게 제어할 수 있어 고도로 커스터마이즈된 동작 구현이 가능.
- 서브그래프로 대규모 시스템을 모듈화해 확장성 확보.
- 체크포인팅 기반 상태 지속성으로 장기 실행 태스크·오류 복구가 용이.
- 여러 AI 에이전트의 상호작용(다중 에이전트 시스템)을 효과적으로 모델링 가능.

## 1-2. LangGraph 환경 설정 및 기본 사용법
원본: https://wikidocs.net/261578

### 1-2-1. LangGraph 설치 및 환경 구성
원본: https://wikidocs.net/261587

- Python 3.10+ 필요. 프로젝트별 격리를 위해 가상환경(venv/conda) 또는 빠른 패키지 매니저 `uv` 사용을 권장.
- `uv add langgraph langchain langchain-openai` 형태로 설치하며, `uv add`는 `pyproject.toml`에 의존성을
  기록하고 `uv pip install`은 단순 설치만 수행한다는 차이가 있음.
- 버전 이력: 0.2.x에서 `Command`/`interrupt` API 도입, 0.3.x에서 Functional API(`@entrypoint`, `@task`)
  추가, 1.0.x는 안정 릴리스(Python 3.10+ 필수, `create_react_agent` 강화).
- 설치 확인은 `from langgraph.graph import StateGraph` 임포트로, 버전은
  `importlib.metadata.version("langgraph")`로 확인.
- 그래프 시각화를 쓰려면 선택적으로 Graphviz도 설치.

### 1-2-2. 기본적인 LLM 모델 설정 (GPT)
원본: https://wikidocs.net/261588

- API 키는 `.env` 파일(`OPENAI_API_KEY=...`)로 관리하고 `python-dotenv`의 `load_dotenv()`로 불러오며,
  `.env`는 반드시 `.gitignore`에 추가해 커밋되지 않도록 함.
- **`init_chat_model`(권장)**: LangChain v1.0부터 `"프로바이더:모델명"` 문자열 하나로 모델을 초기화하는
  통일 인터페이스. OpenAI→Anthropic 등 프로바이더 전환이 문자열만 바꾸면 될 정도로 쉬워짐.
- **`ChatOpenAI` 직접 사용**: OpenAI 전용 고급 파라미터가 필요할 때 사용하는 대안.
- 주요 파라미터: `temperature`(낮을수록 일관, 높을수록 창의적), `max_tokens`(응답 길이 제한).
- 모델 라인업(2026년 2월 기준 스냅샷): GPT-5 계열(플래그십~nano, 코딩·에이전트 최적화), GPT-4.1 계열
  (코딩·지시 따르기 강점), 추론 특화 모델(o3, o4-mini, 복잡한 수학/논리). 교재 실습에는 비용 대비 성능이
  좋은 gpt-4.1-mini류를 권장하고, 복잡한 에이전트 구현엔 상위 모델 사용을 권장.

```python
from langchain.chat_models import init_chat_model
llm = init_chat_model("openai:gpt-4.1-mini", temperature=0.7, max_tokens=150)
response = llm.invoke("...")
```

### 1-2-3. 다양한 LLM 모델 활용 방법 (Anthropic Claude, Google Gemini)
원본: https://wikidocs.net/261589

- `init_chat_model`은 `"anthropic:claude-..."`, `"google-genai:gemini-..."`처럼 프로바이더 접두사만
  바꾸면 되는 통일 인터페이스이므로, 여러 LLM을 동일한 코드로 비교·전환하기 쉽다. 각 프로바이더 패키지
  (`langchain-anthropic`, `langchain-google-genai`)가 설치돼 있으면 자동으로 로드됨.
- 고급/전용 파라미터가 필요할 때는 `ChatAnthropic`, `ChatGoogleGenerativeAI` 같은 프로바이더 전용 클래스를
  직접 쓰는 대안도 있음.
- 모델 라인업 요약(2026년 2월 스냅샷): OpenAI는 GPT-5/4.1 계열과 추론 특화 o-시리즈, Anthropic은
  Opus(최고 성능)·Sonnet(균형)·Haiku(속도/비용), Google은 Gemini 3(프리뷰)와 Gemini 2.5 Pro/Flash
  (초대형 컨텍스트, 가성비).
- 용도별 선택 가이드: 학습·실험엔 각 계열의 경량 모델, 프로덕션 범용엔 중간급, 복잡한 추론·에이전트
  개발엔 최상위 모델을 권장.
- 공통 주의사항: API 키는 `.env` + `.gitignore`로 관리하고, 모델명은 계속 갱신되므로 공식 문서를 확인할 것.

## 1-3. StateGraph 이해하기
원본: https://wikidocs.net/261579

### 1-3-1. 기본 구성요소 이해
원본: https://wikidocs.net/261590

- **State**: 모든 노드가 공유하는 데이터 저장소(화이트보드 비유). `TypedDict`로 정의하며, 대화형 앱에는
  메시지 히스토리 관리(리듀서 포함)를 자동 제공하는 내장 `MessagesState`를 상속해 쓰는 것이 편리함.
- **Node**: 상태를 받아 새로운 상태 딕셔너리를 반환하는 일반 함수. 반환하지 않은 필드는 기존 값이 유지됨.
- **Edge**: `add_edge(A, B)`로 노드 간 실행 순서를 연결. `START`/`END` 상수로 그래프의 시작·끝을 지정.
- 세 요소는 "데이터(State)-작업자(Node)-화살표(Edge)"의 조합으로 이해하면 쉬우며, 노드를 여러 개
  체인처럼 연결하면(START→A→B→END) 상태가 각 노드를 거치며 누적·변형된다.

```python
class CounterState(TypedDict):
    count: int

def increment(state):
    return {"count": state["count"] + 1}

graph = StateGraph(CounterState)
graph.add_node("increment", increment)
graph.add_edge(START, "increment")
graph.add_edge("increment", END)
```

### 1-3-2. 상태 (State)
원본: https://wikidocs.net/261591

- 상태는 `TypedDict` 또는 Pydantic `BaseModel`로 정의하며, 그래프 내 모든 노드/엣지의 입출력 스키마 역할을
  한다. 타입을 명시하면 IDE 자동완성과 사전 오류 검출 등 유지보수 이점이 생김.
- 필드별로 **리듀서(Reducer)**를 지정해 "노드가 반환한 값을 기존 상태에 어떻게 반영할지"를 제어할 수
  있음 — 예: `Annotated[list, add_messages]`는 새 메시지를 리스트에 누적하고 동일 ID 메시지는 갱신하는
  스마트 리듀서. 일반 필드는 기본적으로 덮어쓰기(overwrite) 방식.
- 대화형 앱에서는 `MessagesState`를 상속하면 `messages` 필드와 `add_messages` 리듀서가 자동 포함되어
  직접 설정할 필요가 없음.
- 베스트 프랙티스: 모든 필드에 명확한 타입 지정, 꼭 필요한 데이터만 상태에 담아 복잡도 최소화, 상태를
  직접 변경하지 말고 새 값을 반환하는 불변성 원칙 유지.

#### 1-3-2-1. 상태 관리 기초
원본: https://wikidocs.net/293297

- LangGraph는 Google Pregel의 메시지 전달(Message Passing) 아키텍처에서 착안했다. 노드는 서로 직접
  통신하지 않고 공유 상태를 매개로 간접 통신하며, 병렬 실행 가능한 노드들은 같은 "super-step"에서
  동시에 처리된다는 실행 모델을 갖는다.
- 상태 관리가 중요한 이유 5가지: (1) 대화 맥락의 일관성 유지, (2) 누적된 정보를 바탕으로 한 맥락 이해
  향상, (3) 다단계·다주제 작업 처리, (4) 체크포인팅 기반 오류 복구/재개, (5) 계산 결과 캐싱을 통한
  성능 최적화.
- 노드는 상태 전체가 아니라 **변경할 필드만 반환**하며, LangGraph가 기존 상태와 자동 병합한다.
- 리듀서(Reducer) 개념 — "기존 값과 새 값을 어떻게 합칠지" 정의하는 함수(Redux의 reducer와 유사):
  - 기본(선언만 한 필드)은 **덮어쓰기** 방식.
  - `Annotated[List[str], add]`처럼 리듀서를 지정하면 `operator.add`를 통해 리스트/문자열/숫자를
    **누적**하는 방식으로 동작 — 예: 대화 메시지 리스트나 처리 로그는 누적이 자연스러움.

```python
from typing import Annotated, List
from operator import add

class BasicState(TypedDict):
    current_step: str                       # 덮어쓰기
    messages: Annotated[List[str], add]     # 누적
```

#### 1-3-2-2. 상태 스키마 설계
원본: https://wikidocs.net/293353

- 스키마 정의 3가지 방식과 트레이드오프:
  - **TypedDict**(권장·기본): 가볍고 런타임 오버헤드 없음, 대신 검증이 없고 기본값 지정이 불편. 필드별
    선택 여부는 `NotRequired[...]`로 지정(참고: `Optional`은 "None 허용"이지 "생략 가능"이 아님).
  - **dataclass**: 기본값(`field(default_factory=...)`) 지정이 쉬움, 검증은 없음.
  - **Pydantic BaseModel**: 런타임 검증·자동 타입 변환 등 가장 엄격하지만 성능 오버헤드와 추가 의존성 발생.
  - 선택 기준: 일반적인 경우/고성능이 필요하면 TypedDict, 기본값이 필요하면 dataclass, 엄격한 검증이
    필요하면 Pydantic.
- 설계 원칙: 명확성(의미 있는 필드명·타입힌트·문서화), 캡슐화(입력/출력 스키마 분리로 내부 구현 은닉),
  단일 책임(스키마 하나에 목적 하나).
- 스키마 유형 3단계:
  1. **기본 스키마**: 입출력이 동일한 단일 스키마 — 단순 챗봇/선형 워크플로우에 적합.
  2. **명시적 입출력 스키마**: `InputState`/`OutputState`를 분리하고 `OverallState`가 이를 상속,
     `StateGraph(OverallState, input=InputState, output=OutputState)`처럼 구성 — API형 인터페이스에 적합.
  3. **다중 스키마 + PrivateState**: 노드가 `OverallState`에 없는 필드(내부 디버그 정보 등)를 반환해
     노드 간 비공개로 전달 — RAG·멀티에이전트처럼 단계별 데이터가 다른 복잡한 시스템에 적합
     (자세한 내용은 1-3-3-5의 Private State 절 참고).

#### 1-3-2-3. 리듀서(Reducer) - 상태 업데이트
원본: https://wikidocs.net/293355

- 리듀서는 "노드가 반환한 부분 업데이트를 기존 상태와 어떻게 합칠지" 정하는 함수. 지정하지 않으면
  기본값은 덮어쓰기(대체), 지정하면 누적·병합 등 임의 전략 구현 가능.
- 내장 리듀서: `operator.add`를 `Annotated[list, add]`/`Annotated[str, add]`로 지정하면 리스트는 연결,
  문자열은 이어붙이기 방식으로 누적. 대화 메시지 전용으로는 `add_messages`가 있는데, 새 메시지는
  추가하고 같은 ID의 메시지는 갱신하며 메시지 객체 역직렬화까지 처리 — `MessagesState`를 상속하면
  자동 적용됨.
- 사용자 정의 리듀서: 임의 함수(예: 두 값 중 더 큰 값을 남기는 `max` 방식, 딕셔너리를 재귀적으로 깊게
  병합하는 방식)를 `Annotated[타입, 함수]`에 넣어 상태 필드별로 원하는 병합 규칙을 자유롭게 정의할 수
  있다. 필드마다 리듀서를 다르게 섞어 쓰는 것도 가능(예: 점수는 max, 로그는 누적, 상태 플래그는 덮어쓰기).

#### 1-3-2-4. MessagesState - 대화형 앱의 상태 관리
원본: https://wikidocs.net/319006

- 대부분의 LLM 프로바이더는 채팅 형식(역할+내용의 메시지 리스트)으로 상호작용하므로, 대화 앱은
  메시지 히스토리를 상태로 누적 관리해야 한다. 단순 `operator.add`로 리스트에 이어붙이기만 하면, Human
  -in-the-Loop 등에서 "기존 메시지를 수정"하려 할 때 같은 ID의 메시지가 중복 추가되는 문제가 생긴다.
- `add_messages` 리듀서는 메시지 ID를 기준으로 새 ID면 추가, 같은 ID면 해당 메시지를 갱신(덮어쓰기)하는
  식으로 중복을 방지하고, 딕셔너리로 들어온 메시지를 `HumanMessage`/`AIMessage` 등 LangChain 메시지
  객체로 자동 역직렬화해준다.
- `MessagesState`는 이 `messages` 필드와 `add_messages` 리듀서가 이미 정의된 내장 상태 클래스이므로,
  이를 상속(`class ChatState(MessagesState): ...`)해 필요한 필드(사용자 이름, 언어, RAG 컨텍스트, 턴 수
  등)만 추가하면 대화형 앱의 상태 설계가 크게 단순해진다.

```python
class ChatbotState(MessagesState):
    user_name: str
    context: Optional[list[str]]
```

#### 1-3-2-5. Private State - 노드 간 비공개 데이터
원본: https://wikidocs.net/319067

- Private State는 그래프의 공식 입출력 스키마에는 없지만 일부 노드들끼리만 주고받는 중간 데이터를 위한
  상태. LangGraph는 `StateGraph` 초기화 시 지정한 스키마에 없는 채널이라도, 스키마 정의 자체만 있으면
  노드가 그 채널에 값을 쓰고 다음 노드가 읽는 것을 허용한다.
- 활용 패턴: 노드1이 공개 상태(`PublicState`)를 읽고 비공개 상태(`PrivateState`)로 결과를 반환 → 노드2가
  그 비공개 상태를 읽고 다시 공개 상태로 결과를 반환 → 이후 노드는 공개 상태만 보이므로 중간 처리
  세부사항이 자연스럽게 캡슐화된다.
- 응용: `InputState`/`OutputState`/`OverallState`를 나누어 그래프의 대외 인터페이스는 단순하게 유지하고,
  내부적으로만 필요한 중간 데이터(`intermediate_data`, `processing_steps` 등)는 `OverallState`에서만
  다루는 식으로 입출력 스키마와 내부 구현을 분리할 수 있다.
- 이 패턴은 RAG 파이프라인처럼 "검색 결과 원문 → 재랭킹 점수 → 최종 답변"과 같이 여러 내부 단계를 거치는
  워크플로우에서 외부에는 질문/답변만 노출하고 싶을 때 특히 유용하다.

### 1-3-3. 노드 (Node)
원본: https://wikidocs.net/261580

- 노드는 상태를 받아 처리하고 갱신된 상태를 반환하는 파이썬 함수. LangGraph의 설계 철학은 "노드가
  작업을 수행하고, 엣지가 다음 순서를 정한다"는 역할 분리.
- 노드 함수 시그니처는 필요에 따라 세 단계로 확장 가능: `(state)` 기본형 → `(state, config)`로
  `RunnableConfig`(thread_id 등 실행 설정) 접근 → `(state, config, *, store, stream_writer)`로 장기
  메모리 스토어나 커스텀 스트리밍까지 접근하는 전체형.
- 동기 노드는 `def`, 비동기(I/O 바운드에 유리) 노드는 `async def`로 정의하며 각각 `invoke`/`ainvoke`로
  실행. `graph.add_node("이름", 함수)`로 등록하되 이름을 생략하면 함수명이 자동으로 노드명이 되고,
  LangChain의 `Runnable` 객체(예: LLM 인스턴스)도 그대로 노드로 등록 가능.
- `START`/`END`는 그래프의 진입점·종료점을 나타내는 특수 노드.
- **노드 캐싱**: `CachePolicy`(TTL, 캐시 키 함수)를 지정하고 `compile(cache=InMemoryCache())`로 컴파일하면
  동일 입력에 대해 재계산을 생략할 수 있다 — 비용이 큰 LLM/외부 API 호출에 특히 유용.

#### 1-3-3-1. 노드의 기본 개념
원본: https://wikidocs.net/261593

- 노드의 핵심 특징 4가지: 함수 기반(파이썬 함수로 구현), 상태 중심(현재 상태를 입력으로 받음),
  독립적 실행(각 노드가 서로 독립적으로 실행 가능), 조합 가능(여러 노드를 이어 복잡한 워크플로우 구성).
- 표준 노드 패턴: 상태에서 필요한 값을 `state.get(키, 기본값)`처럼 안전하게 추출 → 비즈니스 로직 처리를
  가급적 별도 함수로 분리(가독성·테스트 용이성 향상) → 변경할 필드만 딕셔너리로 반환(반환하지 않은
  필드는 그대로 유지).
- 노드 등록은 `graph.add_node("이름", 함수)`로, 그래프 생성 시 정의한 `State` 스키마와 노드 함수의
  입출력이 일관되게 맞물려야 한다는 점이 핵심.

#### 1-3-3-2. 노드의 역할과 책임
원본: https://wikidocs.net/293519

- 노드의 책임을 셋으로 정리: (1) 데이터 변환/처리(파싱·계산·외부 API 호출), (2) 상태 관리(현재 상태를
  읽고 다음 단계에 필요한 정보로 갱신), (3) 흐름 제어(조건부 로직으로 다음 노드 결정 또는 종료).
- 설계 원칙으로 모듈성·재사용성·타입 안전성(TypedDict 기반 스키마로 컴파일 타임 오류 예방)을 강조하며,
  리듀서를 통한 유연한 상태 병합, 서브그래프/Private State를 통한 대규모 아키텍처 지원까지 노드 설계의
  범위로 다룬다.
- 에러 처리·재시도, 실행 시간 모니터링 및 병목 최적화(캐싱·병렬화)도 노드 설계 시 함께 고려해야 할
  책임으로 언급된다.

#### 1-3-3-3. 노드 타입과 패턴
원본: https://wikidocs.net/293520

- **동기 노드**: 순차 실행, 완료까지 대기. 단순 계산·CPU 바운드 작업에 적합하며 디버깅이 쉬움.
- **비동기 노드**(`async def`): I/O 대기가 있는 작업(외부 API, DB 쿼리)에 유리. `await`로 개별 호출을,
  `asyncio.gather(...)`로 여러 비동기 작업을 동시에 실행해 지연시간을 단축할 수 있다. 그래프 실행도
  `ainvoke()`/`astream()`으로 맞춰줘야 한다.
- 이 외에도 조건부 로직을 품은 노드, 여러 도구를 순차 호출하는 노드 등 다양한 패턴이 등장하며, 작업의
  I/O 여부에 따라 동기/비동기를 선택하는 것이 성능에 큰 영향을 준다.

```python
async def async_node(state: State) -> dict:
    result = await perform_async_operation(state["input"])
    extra = await asyncio.gather(fetch_a(), fetch_b(), fetch_c())
    return {"output": result, "extra": extra}
```

#### 1-3-3-4. 노드와 구성 (Configuration)
원본: https://wikidocs.net/293528

- `RunnableConfig`를 노드의 두 번째 인자로 받으면 런타임에 노드 동작을 동적으로 조정할 수 있다.
  `config.get("configurable", {}).get("key", 기본값)` 패턴으로 안전하게 값을 꺼내 쓴다.
- 활용 예: 요청별로 다른 LLM 모델/temperature 선택, 재시도 횟수·타임아웃 등 오류 정책 조정, 개발/운영
  환경별 설정 분기, 사용자별 권한·개인화 처리, 로깅·트레이싱 수준 조정.
- 구성은 부모 그래프에서 서브그래프·하위 노드로 자동 전파되며 필요 시 특정 노드에서 오버라이드할 수
  있어 계층적 설정 관리가 가능하다. 민감 정보가 담길 수 있으므로 접근 제어·유효성 검증이 필요하다.

#### 1-3-3-5. 노드 구성 고급 패턴 유형
원본: https://wikidocs.net/293529

- **클래스 기반 노드**: `__init__`으로 초기 설정을 받고 `__call__`을 구현해 인스턴스를 호출 가능한
  노드로 사용. 처리 횟수·캐시 등 내부 상태를 인스턴스 변수로 유지할 수 있어, 캐싱/통계/설정 저장이
  필요한 복잡한 노드에 적합하며 상속으로 기능을 확장할 수 있다.
- 이 외에도 여러 처리 방식을 메서드로 분리하는 전략 패턴, 함수 노드와 클래스 노드를 혼합하는 하이브리드
  구성 등 유지보수성을 높이는 고급 패턴들이 소개된다.

```python
class DataProcessorNode:
    def __init__(self, processor_type: str = "standard"):
        self.processor_type = processor_type
        self.cache = {}

    def __call__(self, state: State) -> dict:
        key = f"{self.processor_type}:{state['input']}"
        if key in self.cache:
            return {"output": self.cache[key], "from_cache": True}
        result = self._process(state["input"])
        self.cache[key] = result
        return {"output": result}
```

### 1-3-4. 엣지 (Edge)
원본: https://wikidocs.net/262302 · https://wikidocs.net/261594

"노드가 작업을 수행하고 엣지가 다음 할 일을 알려준다"는 원칙대로, 엣지는 노드 간 실행 순서·데이터 흐름을
정의하는 방향성 연결이다. 엣지 유형은 크게 4가지: 일반 엣지(`add_edge(a, b)`, 고정 경로), 시작/종료
엣지(`START`/`END`와의 연결), 조건부 엣지(`add_conditional_edges`로 런타임 상태에 따라 분기), 조건부
진입점(START 시점부터 분기). 여러 엣지가 동시에 활성화되면 병렬 실행도 가능하다.

#### 1-3-4-1. 엣지의 개념과 종류
원본: https://wikidocs.net/261594

- 엣지의 핵심 속성: 방향성(단방향 연결), 상태 전달(다음 노드로 상태를 넘김), 흐름 제어(실행 순서·조건
  결정), 병렬 가능성(여러 엣지가 동시에 활성화될 수 있음).
- 기본형은 `add_edge(START, "노드")`, `add_edge("노드A", "노드B")`, `add_edge("노드", END)`로 시작·중간·
  종료를 연결하는 것이며, 조건부 엣지는 `add_conditional_edges("분기노드", 라우팅함수, {반환값: 목적지})`
  형태로 라우팅 함수의 반환 문자열을 목적지 노드 이름에 매핑한다.

#### 1-3-4-2. 엣지의 역할과 기능
원본: https://wikidocs.net/293533

- 엣지의 첫째 역할은 **실행 순서 정의**다. `START→step1→step2→step3→END` 같은 선형 흐름은 물론, 분기·
  병합이 섞인 복잡한 경로도 표현할 수 있다. 각 단계가 이전 단계 완료를 전제로 실행되도록 보장해 데이터
  파이프라인의 의존성 관리와 일관성을 지켜준다.
- 이 외에도 엣지는 병렬 실행 트리거, 조건 기반 동적 라우팅, 서브그래프 진입·복귀 지점 표시 등 그래프의
  "제어 구조" 역할 전반을 담당한다.

#### 1-3-4-3. 조건부 엣지 (Conditional Edges)
원본: https://wikidocs.net/293535

- 조건부 엣지는 런타임 상태를 보고 다음 노드를 동적으로 고르는 기능으로, "if-else" 분기를 그래프 수준
  에서 표현한 것이다. `add_conditional_edges(출발노드, 조건함수, {조건함수의_반환값: 목적지노드, ...})`
  형태로 정의하며, 조건 함수는 상태를 받아 문자열(또는 노드 이름)을 반환한다.
- 활용 예: 감정 분석 결과에 따라 다른 응답 노드로 분기, 점수 구간별로 처리 경로를 나누기, 여러 조건을
  조합한 복잡한 라우팅. 성능 최적화나 에러 발생 시 대체 경로로 우회하는 복구 전략에도 쓰인다.

```python
def route(state) -> str:
    return "high" if state["score"] > 0.8 else "low"

graph.add_conditional_edges("evaluate", route, {"high": "publish", "low": "revise"})
```

#### 1-3-4-4. Command를 활용한 고급 흐름 제어
원본: https://wikidocs.net/293558

- `Command`는 "다음에 어디로 갈지(goto)"와 "상태를 어떻게 바꿀지(update)"를 하나의 원자적 연산으로
  묶어 반환하는 객체로, 조건부 엣지가 라우팅만 담당하는 한계를 넘어선다. 노드 함수가
  `Command[Literal["a", "b", END]]`를 반환 타입으로 명시하면 타입 체크도 함께 받을 수 있다.
- 언제 Command를 쓰는가: 상태 업데이트와 라우팅을 동시에 해야 할 때(예: 재고 확인 후 상태 메시지 갱신
  +결제 노드로 이동), 멀티 에이전트 핸드오프(한 에이전트가 다른 에이전트로 제어를 넘기며 메시지도 함께
  전달), 서브그래프에서 부모 그래프로 복귀하며 상태를 반영해야 할 때. 단순 라우팅만 필요하면 여전히
  조건부 엣지가 더 간단하다.

```python
def check_inventory(state) -> Command[Literal["process_payment", "out_of_stock"]]:
    if stock_ok:
        return Command(goto="process_payment", update={"status": "재고 확인 완료"})
    return Command(goto="out_of_stock", update={"status": "품절"})
```

#### 1-3-4-5. Send API - 동적 병렬 실행
원본: https://wikidocs.net/319069

- 일반 엣지/조건부 엣지는 그래프 컴파일 시점에 분기 수가 고정되지만, 실행 중에 몇 개로 나뉠지 모르는
  경우(예: 리스트 길이가 런타임에 결정)에는 `Send` 객체를 쓴다. 조건부 엣지 함수가 `Send(노드이름, 상태)`
  리스트를 반환하면, 그 개수만큼 해당 노드가 각각 다른 입력 상태로 병렬 실행된다.
- 전형적 용도는 Map-Reduce 패턴: 한 노드가 항목 리스트를 생성하고, 각 항목에 대해 동일한 처리 노드를
  동적으로 병렬 호출한 뒤 결과를 리듀서(`Annotated[list, add]` 등)로 합친다.

```python
def route_to_summarizers(state) -> list[Send]:
    return [Send("summarize_topic", {"topic": t}) for t in state["topics"]]

builder.add_conditional_edges("generate_topics", route_to_summarizers)
```

### 1-3-5. 그래프 연결(컴파일) 및 실행
원본: https://wikidocs.net/262304

State·Node·Edge를 정의한 뒤 마지막 단계는 `graph.compile()`로 실행 가능한 앱으로 변환하고 `invoke()`로
실행하는 것이다. 컴파일 과정에서 그래프 구조의 일관성이 검증·최적화되며, 이후 `invoke()`는 초기 상태
딕셔너리를 받아 정의된 노드들을 순차/조건부로 실행한 뒤 최종 상태를 반환한다.

#### 1-3-5-1. 그래프 구성 요소 연결
원본: https://wikidocs.net/293393

- 그래프 설계의 핵심 원칙은 **책임 분리**다. 각 노드는 상태의 특정 측면만 명확히 담당해야 하며(예:
  `validate_input`은 입력 검증과 에러 상태만, `process_data`는 변환과 메타데이터만, `generate_output`은
  최종 결과만 처리), 이렇게 노드를 잘게 나눌수록 코드 이해도·유지보수성이 좋아진다.
- 실전 패턴: 검증 노드가 실패 시 `error` 필드를 채우고 `processing_stage`를 `"validation_failed"`로
  설정 → 이후 조건부 엣지가 이 필드를 보고 정상 경로/에러 처리 경로로 분기하는 식으로, 노드의 책임
  분리와 조건부 엣지의 라우팅을 결합해 견고한 워크플로우를 구성한다.

#### 1-3-5-2. 그래프 실행 방법 (invoke, stream, async)
원본: https://wikidocs.net/293826

| 메서드 | 실행 방식 | 주 용도 |
|---|---|---|
| `invoke()` | 동기, 완료까지 대기 후 최종 결과 반환 | 배치 처리, 테스트 |
| `stream()` | 동기, 중간 결과를 실시간 반환 | 실시간 UI, 진행 상황 표시 |
| `ainvoke()` | 비동기, 최종 결과만 반환 | 고동시성 서버 |
| `astream()` | 비동기 스트리밍 | 비동기 실시간 UI |

- `invoke`/`ainvoke`에 `config={"configurable": {"thread_id": "..."}}`로 세션(스레드)을 식별하고,
  `recursion_limit`으로 최대 실행(super-step) 횟수를 제한해 무한 루프를 방지할 수 있다.
- `stream_mode`는 `values`(매 단계 후 전체 상태), `updates`(변경분만), `messages`(LLM 토큰 단위),
  `custom`(사용자 정의 데이터), `debug`(상세 실행 정보) 중 선택 — 자세한 스트리밍 패턴은 Part 1-6에서
  별도로 다룬다.
- `asyncio.gather(app.ainvoke(...), ...)`로 여러 그래프 실행을 동시에 병렬 처리할 수 있어, 배치/멀티
  요청 처리 시 성능을 크게 높일 수 있다.

```python
config = {"configurable": {"thread_id": "user_123"}}
result = app.invoke({"counter": 0}, config=config, recursion_limit=10)

async for chunk in app.astream({"counter": 0}, stream_mode="values"):
    print(chunk)
```

## 1-4. 메모리 (Memory)
원본: https://wikidocs.net/261582

LangGraph의 "메모리"는 이전 실행/대화 내용을 기억하는 기능으로, 내부적으로 **체크포인터(Checkpointer)**가
이를 담당한다. 체크포인터가 있으면 자연스러운 연속 대화, 사용자별 개인화, 오류 발생 시 중단 지점부터의
안전한 재개가 가능해진다.

### 1-4-1. 메모리 기능과 기본 예제
원본: https://wikidocs.net/261599

- 메모리 활성화의 3요소: (1) 체크포인터 임포트(`from langgraph.checkpoint.memory import InMemorySaver`),
  (2) 인스턴스 생성, (3) `graph.compile(checkpointer=memory)`로 그래프에 연결.
- `thread_id`는 대화 세션(스레드)을 구분하는 식별자로, 실행 시 `config={"configurable": {"thread_id": "..."}}`
  로 전달한다. 같은 `thread_id`면 이전 상태를 이어받고, 다른 `thread_id`면 완전히 별개의 세션이 된다.
  실제 서비스에서는 보통 사용자 ID나 채팅방 ID를 `thread_id`로 사용한다.
- `MessagesState`를 상속한 챗봇 예제, 누적 계산기, 사용자별 방문 카운터 등 다양한 예제를 통해 "노드가
  반환한 부분 업데이트가 체크포인터에 의해 스레드별로 계속 누적/보존된다"는 감각을 보여준다.

```python
from langgraph.checkpoint.memory import InMemorySaver

memory = InMemorySaver()
app = graph.compile(checkpointer=memory)
config = {"configurable": {"thread_id": "user_123"}}
app.invoke(initial_state, config=config)
```

### 1-4-2. 체크포인터 종류별 활용법
원본: https://wikidocs.net/261600

체크포인터는 목적에 따라 여러 구현체 중 선택한다: 테스트/프로토타입엔 `InMemorySaver`, 로컬 개발·소규모
서비스엔 `SqliteSaver`, 프로덕션 분산 환경엔 `PostgresSaver`(트랜잭션 보장, 고가용성).

#### 1-4-2-1. InMemorySaver
원본: https://wikidocs.net/321315

- 가장 간단한 체크포인터로, 별도 설정 없이 인스턴스만 생성하면 즉시 사용 가능하다. 데이터는 프로세스
  메모리에만 있으므로 **프로세스 종료 시 소멸**(휘발성)하지만 성능은 가장 빠르다.
- `thread_id`로 다중 사용자 세션을 동시에 구분·관리할 수 있으며, 개발·테스트·데모·프로토타입에 권장된다.
- `InMemoryStore`를 함께 쓰면 체크포인터(단기 대화 기록)와 별개로 장기 메모리·시맨틱 검색(`index`
  파라미터로 임베딩 기반 검색 활성화)도 구성할 수 있다.

#### 1-4-2-2. SqliteSaver
원본: https://wikidocs.net/321316

- `pip install langgraph-checkpoint-sqlite`로 설치하는 파일 기반 체크포인터. 프로세스가 재시작돼도
  SQLite 파일에 상태가 남아있어 **영구 저장**이 가능하고, DB 서버 없이 로컬 파일만으로 동작한다.
- 사용 방식 두 가지: 연결을 직접 생성·관리(재사용에 유리하지만 `close()`를 직접 호출해야 함), 또는
  Context Manager(`with SqliteSaver.from_conn_string(...)`) 방식(권장 — 자동으로 안전하게 정리).
- 비동기 환경에서는 `AsyncSqliteSaver`를 사용한다. 로컬 개발·소규모 프로덕션에 적합.

### 1-4-3. Time Travel - 과거 상태로 이동
원본: https://wikidocs.net/319029

- Time Travel은 과거 체크포인트로 돌아가 다른 실행 경로를 시도해보는 기능으로, Git의 `checkout`+`branch`
  에 비유된다: `get_state_history()`가 `git log`, `update_state()`가 수정 후 커밋, 이전 체크포인트에서
  `invoke(None, config)`로 재개하는 것이 새 브랜치에서의 실행에 해당한다.
- 핵심 원리는 **Fork(분기)**다. 과거 체크포인트에서 재개해도 원래 실행 이력은 삭제되지 않고 그대로
  보존되며, 새로운 분기가 별도로 생성되어 원래 결과와 새 결과를 나란히 비교할 수 있다.
- 활용 목적 3가지: 추론 과정 이해(성공한 경로의 의사결정 역추적), 오류 디버깅(문제가 생긴 정확한 노드
  식별), 대안 탐색(같은 출발점에서 다른 경로를 시도해 더 나은 결과 탐색·A/B 비교).
- 절차는 4단계: 체크포인터로 그래프 실행 → `get_state_history()`로 체크포인트 목록 조회 → (선택)
  `update_state()`로 특정 체크포인트의 상태를 수정 → 해당 체크포인트 설정으로 그래프를 다시 `invoke`해
  재개.

### 1-4-4. Durable Execution - 견고한 실행
원본: https://wikidocs.net/319030

- Durable Execution은 실행이 중단되어도(HITL 대기, 시간 초과, 외부 API 장애, 서버 재시작 등) 중단된
  지점부터 정확히 재개할 수 있게 해주는 내결함성 기능으로, "자동 저장이 있는 장시간 게임"에 비유된다.
- 활성화 조건 3가지: (1) 체크포인터로 지속성 확보(프로덕션은 `PostgresSaver` 권장 — 분산 시스템·트랜잭션
  보장, 로컬은 `SqliteSaver`, 테스트는 `InMemorySaver`), (2) 실행마다 `thread_id` 지정, (3) 비결정적
  작업(외부 API 호출, 랜덤성이 있는 연산 등)은 `@task`로 감싸서 재실행 시 같은 결과가 재사용되도록 함
  (재실행 시 이미 완료된 `@task`는 다시 실행하지 않고 저장된 결과를 리플레이).
- `@task`로 감싸지 않은 부수 효과(side effect)는 재개 시 중복 실행될 위험이 있으므로, StateGraph보다
  Functional API(`@task`/`@entrypoint`, Part 1-7 참고)를 쓸 때 이 패턴이 특히 중요하다.

```python
from langgraph.checkpoint.postgres import PostgresSaver

checkpointer = PostgresSaver.from_conn_string("postgresql://user:pw@host/db")
graph = workflow.compile(checkpointer=checkpointer)
```

## 1-5. 서브그래프 (Sub-graph)
원본: https://wikidocs.net/261583

서브그래프는 독립적으로 컴파일 가능한 하나의 `StateGraph`를 더 큰 메인 그래프의 노드처럼 재사용하는
패턴이다. 복잡한 시스템을 기능 단위로 쪼개 모듈화하고, 각 서브그래프를 개별적으로 테스트·재사용할 수
있게 해준다.

### 1-5-1. 서브그래프 구현
원본: https://wikidocs.net/261602

- 구현은 3단계: (1) 상태 정의 — 메시지 필드는 `Annotated[list, add_messages]`로 선언(단순
  `operator.add`와 달리 메시지 ID 기반 중복 방지·갱신·삭제(`RemoveMessage`)·딕셔너리→메시지 객체 자동
  변환을 지원), (2) 노드 함수 구현 — 각 노드는 상태를 받아 처리 결과를 반환, (3) 그래프 구성 — `StateGraph`
  생성 후 노드·엣지를 연결하고 `compile()`.
- 서브그래프는 이 자체로 하나의 완결된 그래프이므로 독립적으로 실행·시각화·테스트할 수 있다.

### 1-5-2. 메인 그래프에 통합하여 구현
원본: https://wikidocs.net/264592

- 서브그래프를 메인 그래프에 통합하는 핵심 조건은 **상태 스키마의 키 공유**다. `MainState`가
  `SubGraphState`와 동일한 키(`messages`, `context` 등)를 가지고 있으면, 컴파일된 서브그래프를
  `main_builder.add_node("sub", compiled_subgraph)`처럼 일반 노드와 똑같이 추가할 수 있다.
- 공유되지 않는 키(서브그래프에만 있는 내부 필드)가 있으면 상태가 의도치 않게 덮어써질 수 있으므로,
  메인-서브그래프 간에 어떤 키를 공유하고 어떤 키를 서브그래프 전용(Private State)으로 둘지 명확히
  설계해야 한다.
- 메인 그래프는 라우팅 로직(조건부 엣지)으로 언제 서브그래프를 호출할지 결정하고, 서브그래프 실행 결과는
  다시 메인 상태에 반영되어 이후 노드들이 이어서 사용한다 — 복잡한 멀티 에이전트나 RAG 파이프라인에서
  "하나의 하위 기능을 통째로 서브그래프로 캡슐화"하는 패턴의 기반이 된다.

```python
class MainState(TypedDict):
    messages: Annotated[list, add_messages]
    context: str
    subgraph_result: Optional[str]

main_builder.add_node("sub_task", compiled_subgraph)  # 서브그래프를 노드처럼 추가
```

## 1-6. 스트리밍 (Streaming)
원본: https://wikidocs.net/319022

모든 컴파일된 그래프는 동기 `stream()`/비동기 `astream()`으로 실행 중 데이터를 실시간으로 흘려보낼 수
있다. 어떤 데이터를 스트리밍할지는 `stream_mode` 인자로 고른다.

### 1-6-1. 스트리밍 개요와 stream_mode
원본: https://wikidocs.net/319023

| 모드 | 내용 | 출력 형태 |
|---|---|---|
| `values` | 각 단계 후 전체 상태 | State 딕셔너리 |
| `updates` | 상태 변화분만 | `{노드명: 변경값}` |
| `messages` | LLM 토큰 단위 | `(message_chunk, metadata)` 튜플 |
| `custom` | 사용자 정의 데이터 | 자유 형식 |
| `debug` | 실행 상세 정보 | 디버그 이벤트 |

여러 모드를 리스트로 동시에 지정(`stream_mode=["values", "messages"]`)해 하나의 스트림에서 여러 종류의
이벤트를 함께 받을 수도 있다.

### 1-6-2. 상태 스트리밍 (values, updates)
원본: https://wikidocs.net/319024

- `values`는 매 노드 실행 후 **전체 상태 스냅샷**을 방출한다 — 항상 최신 전체 상태가 필요한 UI 렌더링에
  적합.
- `updates`는 각 노드가 반환한 **변경분(델타)만** 방출하며, 어떤 노드가 무엇을 바꿨는지 추적하기 좋아
  변경 이력 로깅·감사(audit)에 적합.
- 실전 예: 다단계 연구 파이프라인에서 `values`로 대시보드에 항상 최신 결과 요약을 보여주고, `updates`로
  각 단계(수집→분석→최종화)의 신뢰도(confidence) 변화만 별도로 로그에 남기는 조합 사용.

### 1-6-3. LLM 토큰 스트리밍 (messages)
원본: https://wikidocs.net/319025

- `messages` 모드는 LLM 응답을 토큰 단위로 실시간 방출해 ChatGPT류의 "타이핑 효과" UI를 구현할 수 있게
  한다. 각 청크는 `(message_chunk, metadata)` 튜플이며, `isinstance(message_chunk, AIMessageChunk)`로
  실제 LLM 응답 토�큰만 골라내는 것이 권장 패턴(스트림에는 `ToolMessage` 등 다른 타입도 섞여 있을 수
  있음).
- 메타데이터에는 노드 이름·모델 정보 등이 담겨 있어, 특정 노드나 태그로 필터링해 여러 LLM 호출이 섞인
  그래프에서도 원하는 호출의 토큰만 선택적으로 스트리밍할 수 있다.

```python
for chunk in app.stream({"messages": [HumanMessage(content="...")]}, stream_mode="messages"):
    message_chunk, metadata = chunk
    if isinstance(message_chunk, AIMessageChunk) and message_chunk.content:
        print(message_chunk.content, end="", flush=True)
```

### 1-6-4. 커스텀 데이터 스트리밍 (custom)
원본: https://wikidocs.net/319026

- `custom` 모드는 그래프 상태나 LLM 출력이 아닌 임의 데이터(진행률, 로그, 중간 결과 등)를 노드 내부에서
  자유롭게 흘려보내는 기능이다. 노드 안에서 `get_stream_writer()`로 writer를 얻고 `writer(값)`을 호출하면
  된다.
- 대표 활용: 긴 반복 작업의 진행률(%) 표시, `tqdm` 연동 진행바, 커스텀 로깅 시스템과의 연동.
- 주의: `get_stream_writer()`는 Python 3.11 미만의 비동기 함수에서는 컨텍스트 변수 전파 방식 차이로
  정상 동작하지 않는다.

```python
def process_node(state):
    writer = get_stream_writer()
    writer("처리 시작...")
    for i, v in enumerate(state["data"]):
        writer(f"진행률: {(i+1)/len(state['data'])*100:.0f}%")
    return {"result": sum(state["data"])}
```

### 1-6-5. 서브그래프 출력 스트리밍
원본: https://wikidocs.net/319028

- 서브그래프의 내부 이벤트까지 함께 받으려면 `stream(..., subgraphs=True)`를 쓰고, **컴파일된 서브그래프
  객체를 `add_node()`로 직접 노드로 등록**해야 한다(노드 함수 내부에서 `sub_app.invoke()`를 호출하는
  방식으로는 서브그래프 이벤트가 캡처되지 않는다는 점이 핵심 주의사항).
- 이 경우 출력은 `(namespace, data)` 튜플이 되며, `namespace`는 서브그래프가 호출된 경로를 나타내는
  튜플(`"노드이름:태스크ID"` 형식의 요소들)이다. 여러 단계로 중첩된 서브그래프에서도 namespace로 어느
  레벨의 이벤트인지 구분할 수 있다.

```python
main_graph.add_node("sub", sub_app)  # 컴파일된 서브그래프를 노드로 직접 등록
for namespace, data in main_graph.compile().stream(input, subgraphs=True):
    print(namespace, data)
```

## 1-7. Functional API
원본: https://wikidocs.net/319031

Functional API는 `StateGraph`(Graph API)의 보일러플레이트(상태 스키마·노드·엣지 선언)를 줄이고, 일반
파이썬 함수와 데코레이터만으로 체크포인팅·인터럽트·스트리밍 같은 LangGraph의 핵심 기능을 사용할 수
있게 해주는 대안 인터페이스다.

### 1-7-1. Functional API 소개
원본: https://wikidocs.net/319032

- Graph API는 강력하지만 "메시지 하나 처리"처럼 단순한 작업에도 상태 스키마 정의, 노드/엣지 연결,
  컴파일 같은 코드가 필요해 과도하게 장황해질 수 있다.
- Functional API는 `@entrypoint`(진입점)와 `@task`(개별 작업 단위) 두 데코레이터로 이를 대체한다.
  일반 함수를 `@entrypoint(checkpointer=...)`로 감싸기만 하면 지속성·재개·스트리밍이 자동으로 붙는다.
- 적합한 시나리오: 기존 파이썬 프로젝트에 지속성만 추가하고 싶을 때, 단순 선형 에이전트 워크플로우,
  API 호출 결과 캐싱, 빠른 프로토타이핑.

```python
@entrypoint(checkpointer=InMemorySaver())
def chat(messages: list):
    return [model.invoke(messages)]
```

### 1-7-2. @entrypoint와 @task 데코레이터
원본: https://wikidocs.net/319033

- `@entrypoint(checkpointer=..., config_schema=...)`는 함수를 워크플로우의 진입점으로 승격시켜 지속성·
  인터럽트·스트리밍 관리를 맡긴다. 실행 시 `config={"configurable": {"thread_id": "..."}}`로 세션을
  구분하는 방식은 Graph API와 동일하다.
- `@task`는 개별 작업(특히 side effect가 있는 연산: 외부 API 호출, 파일 I/O 등)을 감싸, Durable
  Execution 재개 시 이미 완료된 작업이 중복 실행되지 않고 결과가 재사용되도록 보장한다. `@task`로
  감싼 함수들은 `asyncio.gather`나 동시 호출을 통해 쉽게 병렬 실행할 수 있고, 비동기 함수도 지원한다.
- `@entrypoint.final`은 워크플로우가 다음 실행에 이어줄 값과 실제로 호출자에게 반환할 값을 다르게
  지정하고 싶을 때 사용한다.

### 1-7-3. Functional API 실습 예제
원본: https://wikidocs.net/319034

- 대표 예제 구성: (1) `previous` 인자로 이전 실행 결과를 이어받는 지속형 챗봇, (2) `@task`로 감싼 API
  호출을 캐싱해 같은 재시도가 반복 호출되지 않게 하는 예제, (3) `interrupt()`를 활용한 Human-in-the-Loop
  승인 워크플로우, (4) `custom` 스트리밍과 결합한 진행률 표시, (5) 스레드 간에 공유되는 장기 메모리
  (`Store`)를 함께 쓰는 예제.
- 챗봇 예제의 핵심은 `previous` 매개변수로 직전까지의 대화 메시지 리스트를 넘겨받아 이어붙이고, 함수의
  반환값이 다음 호출의 `previous`로 자동 전달된다는 점이다.

```python
@entrypoint(checkpointer=InMemorySaver())
def chatbot(message: str, *, previous):
    messages = (previous or []) + [{"role": "user", "content": message}]
    response = model.invoke(messages)
    messages.append({"role": "assistant", "content": response.content})
    return messages
```

### 1-7-4. Graph API와의 비교 및 마이그레이션
원본: https://wikidocs.net/319036

| 측면 | Graph API | Functional API |
|---|---|---|
| 구조 정의 | 명시적 노드/엣지 | 데코레이터가 붙은 함수 |
| 제어 흐름 | 조건부 엣지, `add_edge` | 표준 `if/else`, 반복문 |
| 상태 관리 | TypedDict 스키마 + 리듀서 | 함수 파라미터/반환값 |
| 시각화 | 그래프 다이어그램 자동 생성 | 함수 호출 추적 |
| 코드량 | 다소 장황 | 간결 |
| 적합한 경우 | 복잡한 워크플로우 | 간단한 선형 프로세스 |

- 마이그레이션 시 흔한 함정(Pitfall) 두 가지: (1) side effect가 있는 코드를 `@task`로 감싸지 않아 재개
  시 중복 실행되는 문제, (2) 비결정적 제어 흐름(예: 매번 다른 순서로 실행되는 로직)이 재생(replay) 시
  결과가 어긋나는 문제 — 두 경우 모두 Durable Execution의 전제(결정론·부수효과의 태스크화)를 어기는
  것이므로 마이그레이션 체크리스트에서 반드시 점검해야 한다.

### 1-7-5. 사용 사례별 API 선택
원본: https://wikidocs.net/319040

- **Graph API가 유리한 경우**: 여러 전문 에이전트 간 명시적 상태 공유와 다중 분기가 필요한 고객 지원
  시스템, `Send` API로 섹션을 병렬 생성하는 다단계 문서 생성 워크플로우, 자율 리서치 에이전트처럼 팀이
  워크플로우를 시각적으로 함께 이해해야 하는 경우(LangGraph Studio 디버깅 포함).
- **Functional API가 유리한 경우**: 간단한 챗봇, 선형적인 데이터 처리 파이프라인, 프롬프트 체이닝
  실험처럼 복잡한 분기 없이 빠르게 구현/반복하면 되는 경우.
- **하이브리드가 유리한 경우**: 엔터프라이즈 애플리케이션(전체 구조는 Graph, 세부 로직은 Functional),
  프로토타입(Functional)에서 프로덕션(Graph로 점진 전환)으로 넘어가는 과정.

### 1-7-6. 하이브리드 접근법
원본: https://wikidocs.net/319041

- 핵심 원칙: **"복잡한 구조는 Graph로, 간단한 로직은 Functional로."** 워크플로우의 전체 흐름·조건부
  라우팅은 `StateGraph`로 표현하고, 각 노드 내부의 세부 구현(특히 side-effect가 있는 개별 작업)은
  `@task`로 감싼 함수로 처리하면 가독성과 유지보수성을 동시에 얻을 수 있다.
- 대표 패턴: (1) Graph 노드 함수 내부에서 여러 `@task`를 호출·조합, (2) `@entrypoint` 함수 안에서 컴파일된
  서브그래프를 호출, (3) 서브그래프 자체를 Functional API로 구현, (4) 런타임 조건에 따라 실행할 태스크
  목록을 동적으로 구성, (5) 테스트에서는 Functional API로 개별 로직을 단위 테스트하고 프로덕션에서는
  Graph로 조립하는 방식의 분리.

```python
class DocumentState(TypedDict):
    documents: list[str]
    processed_docs: list[dict]

@task()
def extract_text(doc_path: str) -> str: ...

@task()
def analyze_sentiment(text: str) -> dict: ...

def process_node(state: DocumentState) -> dict:
    # Graph 노드 내부에서 Functional task들을 조합해 사용
    text = extract_text(state["documents"][0]).result()
    return {"processed_docs": [analyze_sentiment(text).result()]}
```

