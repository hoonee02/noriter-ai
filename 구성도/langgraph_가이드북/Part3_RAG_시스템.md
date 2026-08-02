# Part 3. RAG(Retrieval-Augmented Generation) 시스템 구축

> 출처: WikiDocs "LangGraph 가이드북 - 에이전트 RAG with 랭그래프 [ver 1.0+]" (판다스 스튜디오), https://wikidocs.net/book/16723
> 이 문서는 원문을 그대로 옮긴 것이 아니라 핵심 개념 위주로 재구성한 정리본입니다. 각 절 제목 아래 원본 URL을 표기했습니다.

## 개요
Part 3은 RAG의 기본 개념부터 문서 처리·벡터 DB 구축, `StateGraph` 기반 RAG 워크플로우 구현, 평가·최적화
까지 "검색 증강 생성" 시스템을 실제로 만드는 전 과정을 다룬다. (https://wikidocs.net/261607)

이 Part는 기존 정리 문서인 `구성도/RAG_개념_확장.md`·`구성도/하이브리드_에이전트_RAG.md`에서 다룬
Hierarchical/Agentic RAG 개념의 **실제 LangGraph 구현체**에 해당한다 — 개념 문서가 "왜 이런 구조가
필요한가"를 다뤘다면, 이 Part는 "그 구조를 LangGraph의 State/Node/조건부 Edge로 어떻게 코드화하는가"를
보여준다.

---

## 3-1. RAG 시스템 개요 및 설계
원본: https://wikidocs.net/293302

### 3-1-1. RAG 개요와 아키텍처
원본: https://wikidocs.net/293304

- RAG의 등장 배경은 생성형 AI의 두 가지 한계다: **할루시네이션**(학습 데이터에 없는 내용을 그럴듯하게
  지어냄)과 **지식의 시간적 경계**(학습 시점 이후 정보를 모름). RAG는 외부 지식 베이스에서 관련 정보를
  검색해 LLM의 컨텍스트에 주입함으로써 이를 보완한다.

| 구분 | RAG | Fine-tuning |
|---|---|---|
| 업데이트 | 실시간 가능(문서만 교체) | 재학습 필요 |
| 비용 | 상대적으로 저렴 | 높은 컴퓨팅 비용 |
| 투명성 | 출처 추적 가능 | 블랙박스 |
| 적합한 사례 | FAQ, 문서 검색 | 특수 도메인 언어 스타일 |

- RAG의 3단계 워크플로우: **검색(Retrieval)** — 쿼리와 관련된 문서를 지식 베이스에서 가져옴(검색
  정확도가 전체 성능을 좌우), **증강(Augmentation)** — 검색 결과를 LLM이 이해할 수 있는 프롬프트 형태로
  구성, **생성(Generation)** — 그 컨텍스트를 바탕으로 최종 답변 생성.
- **LCEL 체인 vs StateGraph RAG**: 단순한 선형 RAG는 LCEL(`retriever | format | prompt | llm | parser`
  형태의 파이프)로 몇 줄이면 충분하지만, 재검색·조건부 라우팅·다단계 검증처럼 복잡한 흐름이 필요해지면
  `StateGraph`로 전환하는 것이 유리하다 — Part 3-3에서 본격적으로 다룬다.
- 벡터 DB 선택, 노드 함수 작성 규칙(각 노드가 상태의 일부만 갱신) 등은 Part 1의 State/Node 설계 원칙을
  RAG 도메인에 그대로 적용한 것이다.

```python
retriever = vectorstore.as_retriever(search_kwargs={"k": 3})
chain = ({"context": retriever | format_docs, "question": RunnablePassthrough()}
         | prompt | llm | StrOutputParser())
```

## 3-2. 문서 처리 및 벡터 데이터베이스
원본: https://wikidocs.net/293307

### 3-2-1. 문서 로딩 및 청킹
원본: https://wikidocs.net/293312

- LangChain의 문서 로더들은 모두 동일한 `load()` 인터페이스로 파일을 `Document` 객체 리스트로 변환한다.
  형식별 로더: PDF는 `PyPDFLoader`(페이지 단위로 분할, `metadata`에 파일 경로·페이지 번호 자동 포함),
  텍스트는 `TextLoader`, 웹페이지는 `WebBaseLoader`, CSV는 `CSVLoader`, Word는 `Docx2txtLoader`. 범용
  래퍼를 직접 만들기보다 형식별 전용 로더를 쓰는 것이 간단하고 유지보수하기 쉽다고 권장한다.
- 로드된 문서는 보통 페이지 단위로 너무 길기 때문에 **청킹(chunking)**이 필요하다.
  `RecursiveCharacterTextSplitter`가 가장 널리 쓰이며, 문단(`\n\n`) → 줄바꿈(`\n`) → 문장(`.`) 순서로
  자연스러운 경계를 우선 찾아 분할한다. `chunk_size`(청크 최대 길이)와 `chunk_overlap`(인접 청크 간
  중복 구간, 문맥 단절 방지)을 문서 특성에 맞게 조정하는 것이 검색 품질에 큰 영향을 준다.

```python
splitter = RecursiveCharacterTextSplitter(chunk_size=800, chunk_overlap=150)
chunks = splitter.split_documents(documents)
```

### 3-2-2. 임베딩과 벡터 데이터베이스
원본: https://wikidocs.net/293313

- 임베딩은 텍스트를 고차원 벡터로 변환해, 의미가 비슷한 텍스트끼리 벡터 공간에서 가깝게 배치함으로써
  "유사도 검색"을 가능하게 하는 기술이다.

| 모델 | 차원 | 특징 |
|---|---|---|
| `text-embedding-3-small` | 1536 | 비용 효율적, 대부분의 용도에 충분(기본값) |
| `text-embedding-3-large` | 3072 | 더 높은 정확도, 비용 증가 |
| `text-embedding-ada-002` | 1536 | 이전 세대, 호환성 유지 |

- **Chroma**는 로컬에서 바로 쓸 수 있는 오픈소스 벡터 DB로 학습·프로토타이핑에 적합하다.
  `Chroma.from_documents(documents=chunks, embedding=OpenAIEmbeddings(), persist_directory=...)`로
  청킹된 문서를 임베딩과 동시에 디스크에 영속 저장하고, 이후에는 같은 `persist_directory`로 다시 열어
  재사용할 수 있다. `similarity_search()`/`similarity_search_with_score()`로 유사도 검색을 수행하며,
  `as_retriever()`로 감싸면 LCEL·`StateGraph` 노드에서 바로 쓸 수 있는 Retriever 인터페이스가 된다.

```python
vectorstore = Chroma.from_documents(chunks, OpenAIEmbeddings(), persist_directory="./chroma_db")
retriever = vectorstore.as_retriever(search_kwargs={"k": 3})
```

### 3-2-3. 검색 최적화
원본: https://wikidocs.net/293315

기본 유사도 검색만으로는 모호한 쿼리나 다양한 표현으로 작성된 문서를 놓치기 쉬워, 세 가지 보완 기법을
다룬다.

- **쿼리 확장(Query Expansion)**: LLM으로 원본 질문을 의미는 같지만 표현이 다른 여러 쿼리로 변형해
  각각 검색한 뒤 결과를 합치면 재현율(recall)이 향상된다.
- **하이브리드 검색(`EnsembleRetriever`)**: Dense 검색(임베딩 유사도 — 의미적으로 유사한 문서에 강함,
  "자동차"→"차량"도 매칭)과 Sparse 검색(`BM25Retriever`, 키워드 매칭 — 고유명사·코드명 등 정확한 단어
  매칭에 강함)을 가중치를 두어 결합하면 두 방식의 단점을 서로 보완할 수 있다.
- **메타데이터 필터링**: 문서에 저장된 메타데이터(출처, 날짜, 카테고리 등)로 검색 범위를 좁혀 정확도를
  높이고, 검색 결과 품질을 간단히 평가하는 방법(정답 문서 포함 여부 등)도 함께 소개된다.

```python
ensemble = EnsembleRetriever(
    retrievers=[vector_retriever, BM25Retriever.from_documents(chunks)],
    weights=[0.5, 0.5],
)
```

---

## 3-3. StateGraph 기반 RAG 워크플로우 구현
원본: https://wikidocs.net/293316

### 3-3-1. 기본 RAG 워크플로우
원본: https://wikidocs.net/293318

- `RAGState`를 `query`(질문) / `retrieved_docs`(검색된 `Document` 리스트) / `answer`(생성된 답변)
  세 필드만으로 간결하게 정의하고, `retrieve` 노드(벡터스토어에서 `similarity_search`)와 `generate`
  노드(검색 결과를 컨텍스트로 프롬프트에 넣어 LLM 호출) 두 개만으로 최소 RAG 그래프를 구성한다 —
  Part 3-1의 "검색→증강→생성"이 그대로 두 개의 노드로 대응된다.
- 여기에 **조건부 재검색**을 추가하는 확장도 다룬다: 생성된 답변의 품질이나 검색 결과 유무를 조건부
  엣지에서 판단해, 불충분하면 다른 파라미터로 `retrieve`를 다시 실행하거나 종료하는 라우팅을 붙인다.
  스트리밍 실행과 그래프 시각화(`get_graph().draw_mermaid()` 류)로 파이프라인을 눈으로 확인하는 방법도
  함께 소개된다.

```python
class RAGState(TypedDict):
    query: str
    retrieved_docs: List[Document]
    answer: str

def retrieve(state: RAGState) -> dict:
    docs = vectorstore.similarity_search(state["query"], k=3)
    return {"retrieved_docs": docs}

def generate(state: RAGState) -> dict:
    context = "\n\n".join(d.page_content for d in state["retrieved_docs"])
    return {"answer": llm.invoke(prompt.format(context=context, query=state["query"])).content}
```

### 3-3-2. 고급 RAG 패턴
원본: https://wikidocs.net/293319

기본 RAG는 쿼리가 모호하거나 답변 품질이 불안정할 때 한계가 있어, `StateGraph` 노드로 구현하는 세 가지
고급 패턴을 다룬다.

| 패턴 | 핵심 아이디어 | 적합한 상황 |
|---|---|---|
| Multi-Query | 하나의 질문을 여러 관점의 하위 쿼리로 분해해 각각 검색 후 결과를 합침 | 모호한 질문, 넓은 검색 범위 필요 |
| HyDE | 질문에 대한 "가상의 답변 문서"를 LLM으로 먼저 생성하고, 그 가상 문서로 검색 | 쿼리와 실제 문서의 표현 차이가 큰 경우 |
| Self-RAG | 생성된 답변을 스스로 평가하고 부족하면 재검색·재생성을 반복 | 높은 정확도가 필요한 복잡한 질문 |

- Multi-Query는 `sub_queries` 필드를 추가한 State에서 `generate_sub_queries` 노드(LLM으로 하위 쿼리
  3개 생성) → `multi_retrieve` 노드(각 하위 쿼리로 검색 후 중복 제거하며 병합)로 구현된다.
- HyDE는 "질문에 이렇게 답했을 것 같다"는 가상 문서를 임베딩해 검색하면, 질문 자체보다 실제 문서와
  표현이 비슷해 검색 정확도가 높아진다는 직관에 기반한다.
- Self-RAG는 Part 2-1-1-2에서 본 "Self-Correcting" 패턴을 RAG에 적용한 것으로, 생성된 답변을 평가하는
  노드와 조건부 엣지를 추가해 품질이 낮으면 검색·생성을 반복하는 순환 구조를 만든다.

### 3-3-3. RAG + ReAct 에이전트 통합
원본: https://wikidocs.net/293321

- 지금까지의 RAG는 고정된 그래프였지만, 이 절은 RAG 검색 기능 자체를 **에이전트가 스스로 호출 여부를
  판단하는 도구**로 전환한다. `@tool`로 감싼 `knowledge_search(query)` 함수가 벡터스토어를 검색해
  문서 조각과 출처를 정리된 문자열로 반환하고, 이를 `create_agent(model=..., tools=[knowledge_search],
  prompt=...)`에 등록하면 완성된 "RAG 에이전트"가 된다.
- 이 접근의 이점: (1) 에이전트가 매 턴 검색하는 대신 필요할 때만 검색 도구를 호출, (2) 계산기·웹 검색
  등 다른 도구와 자유롭게 결합 가능, (3) 체크포인터(`InMemorySaver` 등)로 대화 맥락을 유지하며 연속
  질의응답이 가능. 도구 함수의 docstring이 에이전트의 도구 선택 판단 근거가 된다는 점은 Part 2와 동일.
- 이 패턴이 바로 `구성도/하이브리드_에이전트_RAG.md`에서 다룬 "Agentic RAG"(검색을 에이전트의 판단에
  맡기는 방식)의 LangGraph/LangChain 구현체에 해당한다.

```python
@tool
def knowledge_search(query: str) -> str:
    """지식 베이스에서 관련 문서를 검색합니다. 기술 문서·매뉴얼에서 정보를 찾을 때 사용하세요."""
    docs = vectorstore.similarity_search(query, k=3)
    return "\n\n---\n\n".join(f"[출처: {d.metadata.get('source')}]\n{d.page_content}" for d in docs)

agent = create_agent(model=model, tools=[knowledge_search], checkpointer=InMemorySaver())
```

---

## 3-4. 평가 및 최적화
원본: https://wikidocs.net/293322

RAG는 검색·생성 두 단계로 이루어지므로 "답변이 좋다"는 주관적 판단 대신 각 단계를 독립적으로 정량
측정해야 병목을 찾고 개선 효과를 검증할 수 있다.

### 3-4-1. RAG 평가
원본: https://wikidocs.net/293323

| 구분 | 메트릭 | 의미 |
|---|---|---|
| 검색 | Recall@K | 상위 K개 결과에 정답 관련 문서가 포함된 비율 |
| 검색 | Precision@K | 상위 K개 결과 중 실제 관련 문서의 비율 |
| 검색 | MRR | 첫 관련 문서 순위의 역수 평균(순위가 빠를수록 높음) |
| 생성 | Faithfulness | 답변이 검색된 컨텍스트에 충실한 정도(할루시네이션 여부) |
| 생성 | Answer Relevancy | 답변이 질문에 적절히 대답하는 정도 |
| 생성 | Context Precision/Recall | 검색된 컨텍스트가 답변에 실제로 쓰였는지 / 정답에 필요한 정보를 포함하는지 |

- **RAGAS**(Retrieval Augmented Generation Assessment)는 이 메트릭들을 자동 계산해주는 평가
  프레임워크다. 평가에는 질문·생성된 답변·검색된 컨텍스트·정답(ground truth) 4요소로 구성된 데이터셋이
  필요하며, `ragas.evaluate()`에 데이터셋과 원하는 메트릭 목록을 넘기면 각 항목의 점수를 얻을 수 있다.
- RAGAS 외에도 특정 도메인에 맞춘 커스텀 평가 함수(예: 특정 키워드 포함 여부, 응답 길이 제약 등)를
  직접 작성해 자동화된 회귀 테스트처럼 사용하는 방법도 함께 소개된다.

### 3-4-2. 성능 최적화
원본: https://wikidocs.net/293324

최적화는 세 방향으로 나뉜다: **검색 품질**(더 정확한 문서 찾기), **생성 품질**(찾은 문서를 더 잘
활용), **비용/속도**(같은 품질을 더 싸고 빠르게).

- **컨텍스트 최적화**: LLM의 컨텍스트 창은 유한하므로, 토큰 예산 내에서 문서를 앞에서부터 채워 넣고
  초과분은 잘라내는 방식으로 관리한다. 또한 `similarity_search_with_score()`로 얻은 유사도 점수에
  임계값을 적용해, 점수가 낮은(관련성이 떨어지는) 문서는 애초에 컨텍스트에서 제외함으로써 노이즈를
  줄인다.
- **캐싱 전략**: 동일하거나 유사한 쿼리가 반복되면 임베딩·검색·생성 결과를 캐시해 LLM 재호출 비용을
  줄인다.
- **인덱스 선택**: Chroma(로컬·간편, 프로토타이핑에 적합)와 FAISS(대규모 데이터셋에서 빠른 근사
  최근접 이웃 검색에 강점) 등 벡터 인덱스별 장단점을 비교하고, 데이터 규모·지연시간 요구사항에 맞게
  선택하도록 안내하며 전체 최적화 체크리스트로 Part 3을 마무리한다.

```python
def optimize_context(docs: list[Document], max_tokens: int = 4000) -> list[Document]:
    max_chars = max_tokens * 4
    selected, total = [], 0
    for doc in docs:
        if total + len(doc.page_content) > max_chars:
            break
        selected.append(doc)
        total += len(doc.page_content)
    return selected
```
