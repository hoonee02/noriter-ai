# Part 8. GraphRAG 고급 기법

> 원본: [neo4j] GraphRAG 완전 정복 - 초보자를 위한 지식 그래프 기반 RAG 시스템
> https://wikidocs.net/book/18976

## 8-1. 하이브리드 검색 최적화
원본: https://wikidocs.net/319228

- Part7의 하이브리드(벡터+전문 검색) 결과를 어떻게 하나의 랭킹으로 합칠지가 핵심 주제. **RRF(Reciprocal Rank Fusion)** 알고리즘을 소개: 각 검색 결과에서의 순위(rank)를 `1/(k+rank)` (k는 보통 60) 형태로 점수화한 뒤 합산해 최종 순위를 매기는 방식으로, 서로 다른 스케일의 점수(코사인 유사도 vs 전문검색 점수)를 공정하게 합치는 표준 기법이다.
- 벡터 검색과 전문 검색의 비중을 상황에 맞게 조절하는 **가중치 조정**을 다룬다. `neo4j-graphrag`의 `HybridRetriever`는 기본 하이브리드 검색을 제공하지만, 세밀한 가중치 커스터마이징은 직접 Cypher로 벡터 인덱스 쿼리(`db.index.vector.queryNodes`)와 전문 인덱스 쿼리(`db.index.fulltext.queryNodes`) 결과를 가져와 `vector_weight`/`fulltext_weight` 파라미터로 점수를 합산하는 커스텀 함수를 구현하는 방식으로 확장한다.
- 이어서 **재순위화(Reranking)** — Cross-Encoder 모델로 1차 검색 결과를 재정렬해 정확도를 높이는 기법, **쿼리 확장(Query Expansion)** — LLM으로 원 질문을 여러 변형 질의로 늘려 검색 재현율을 높이는 기법과, 검색 없이 "가상의 답변 문서"를 LLM으로 먼저 생성해 그 문서의 임베딩으로 검색하는 **HyDE(Hypothetical Document Embedding)** 기법을 소개한다.
- 마지막으로 검색 품질을 정량 측정하기 위한 간단한 평가 지표(정확도/재현율류)를 언급하며, 최적화 기법들을 요약 정리한다.

## 8-2. 컨텍스트 확장 기법
원본: https://wikidocs.net/319229

- **컨텍스트 확장(Context Expansion)**: 검색으로 찾은 청크/엔티티에서 그래프 관계를 따라 주변 정보를 추가로 끌어와 LLM에게 더 풍부한 컨텍스트를 제공하는 기법. "세종대왕이 만든 것은?"이라는 질문에 기본 검색은 훈민정음 한 건만 반환하지만, 확장을 적용하면 집현전 설립, 장영실과의 협업으로 만든 측우기·앙부일구까지 함께 포착된다는 예시로 효과를 보여준다.
- **1홉 확장**: 대상 엔티티에서 나가는 관계와 들어오는 관계를 모두 수집하는 Cypher 패턴(`OPTIONAL MATCH (e)-[r]->(related)`와 `OPTIONAL MATCH (incoming)-[r2]->(e)`를 동시에 사용)으로 구현.
- **2홉 확장**: 1홉에서 찾은 노드를 다시 시작점으로 삼아 한 단계 더 탐색하되, 시작 노드로 돌아오는 순환 경로는 제외(`WHERE hop2 <> start`)하는 패턴.
- 이 외에 컨텍스트 윈도우 확장(검색된 청크의 앞뒤 인접 청크를 함께 가져오는 기법), 그래프 컨텍스트를 하나의 문자열로 통합하는 방법, 경로(path) 자체를 컨텍스트로 활용하는 방법을 다루고, 확장 폭(1홉 vs 2홉 vs 인접 청크)에 따른 트레이드오프(정보량 vs 노이즈/비용)를 비교하며 마무리한다.

## 8-3. Text2Cypher - 자연어를 쿼리로
원본: https://wikidocs.net/319230

- **Text2Cypher**: 사용자의 자연어 질문을 LLM이 직접 Cypher 쿼리로 변환해 실행하는 기술. 예: "세종대왕이 만든 발명품은?" → `MATCH (p:Person {name:'세종대왕'})-[:INVENTED]->(i:Invention) RETURN i.name, i.description`. 사전에 정의된 Retriever 패턴 없이도 임의의 질문에 유연하게 대응할 수 있는 것이 장점이지만, 잘못된/위험한 쿼리 생성 위험이 단점으로 언급된다.
- 구현은 LangChain의 **`GraphCypherQAChain`**이 가장 간단한 방법으로 소개된다:
```python
chain = GraphCypherQAChain.from_llm(
    llm=llm, graph=graph, verbose=True,
    allow_dangerous_requests=True
)
response = chain.invoke({"query": "조선시대 과학자 중 2개 이상의 발명품을 만든 사람은?"})
```
`verbose=True`로 실행하면 LLM이 생성한 중간 Cypher와 조회 결과(Full Context)를 확인할 수 있어 디버깅에 유용하다.
- **스키마 품질이 Text2Cypher 정확도의 핵심**이라는 점을 강조: `Neo4jGraph.schema`가 자동 추출한 노드/관계 속성 정보를 LLM 프롬프트에 넣어주며, 자동 추출이 불완전한 경우 사람이 직접 다듬은 커스텀 스키마 설명을 제공해 정확도를 끌어올릴 수 있다.
- `neo4j-graphrag`의 `Text2CypherRetriever`로 GraphRAG 파이프라인에 통합하는 법, Few-shot 프롬프트(질문-Cypher 예시 쌍을 프롬프트에 포함)로 생성 품질을 높이는 기법, 그리고 생성된 Cypher의 문법 오류나 위험한 쿼리(예: 전체 삭제)를 걸러내는 검증 체인·쿼리 결과 개수 제한 등 안전장치를 함께 다룬다. 마지막에는 이 모든 기법을 조합한 대화형 그래프 탐색기 예제로 마무리.

## 8-4. 성능 최적화
원본: https://wikidocs.net/319232

- 데이터가 커질수록 검색 속도·메모리·API 비용이 중요해진다는 문제의식에서 출발해 Neo4j 인덱스 3종(벡터/Fulltext/속성)의 최적화를 다룬다.
- **벡터 인덱스 튜닝**: `CREATE VECTOR INDEX`의 `indexConfig`에서 차원(`vector.dimensions`)과 유사도 함수(`vector.similarity_function`)를 지정하고, 내부적으로 쓰이는 HNSW 알고리즘의 `vector.hnsw.m`(노드당 연결 수, 기본 16 — 클수록 정확하지만 메모리 증가), `vector.hnsw.ef_construction`(인덱스 구축 시 탐색 범위, 기본 128)을 조정. 대규모 데이터는 `m=32, ef_construction=256`, 실시간성이 중요하면 더 낮은 값을 권장한다는 가이드 제시.
- **Fulltext 인덱스**는 키워드 검색용으로 `fulltext.analyzer` 옵션(예: 불용어 제거)을 설정할 수 있고, 여러 속성을 묶은 복합 Fulltext 인덱스도 가능. **속성 인덱스**는 자주 필터링하는 속성(예: `source`)에 단일/복합/범위(RANGE) 인덱스를 추가해 조회 속도를 높인다.
- **쿼리 최적화**: `EXPLAIN`(실행 계획만 확인)과 `PROFILE`(실제 실행하며 통계 확인)로 병목을 진단하고, 비효율적인 다단계 MATCH를 효율적인 패턴으로 재작성하는 예시, 대량 결과에는 페이지네이션(`SKIP`/`LIMIT`)을 적용할 것을 권장.
- **배치 처리**: 대량 문서의 임베딩을 한 번에 여러 건씩 묶어 API 호출 수를 줄이는 배치 임베딩 생성, Neo4j에 대량 데이터를 올릴 때 `UNWIND` + 파라미터 배치로 삽입 성능을 높이는 패턴.
- **캐싱 전략**: 동일 텍스트의 임베딩을 재계산하지 않도록 임베딩 캐싱, 자주 반복되는 질의의 검색 결과 자체를 캐싱하는 전략을 제안.
- 마지막으로 쿼리 실행 시간 측정 방법과 종합 성능 대시보드 구성 아이디어로 책 전체를 마무리한다. 이 절이 프로덕션 배포를 염두에 둔 마지막 실무 팁 모음에 해당한다.

---
이전: [Part7_GraphRAG_파이프라인.md](./Part7_GraphRAG_파이프라인.md) · 다음: (없음, 책 끝)
