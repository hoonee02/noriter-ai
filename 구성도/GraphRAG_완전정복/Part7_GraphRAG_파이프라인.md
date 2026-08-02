# Part 7. GraphRAG 파이프라인 기초

> 원본: [neo4j] GraphRAG 완전 정복 - 초보자를 위한 지식 그래프 기반 RAG 시스템
> https://wikidocs.net/book/18976

## 7-1. GraphRAG 아키텍처 이해
원본: https://wikidocs.net/319223

- GraphRAG는 벡터 검색과 그래프 탐색을 한 시스템 안에 결합한 구조. 핵심 컴포넌트는 3가지: (1) 청크+임베딩(Chunk 노드에 원문 텍스트와 임베딩 벡터를 함께 저장), (2) 지식 그래프(엔티티·관계), (3) Retriever(검색 전략을 담당하는 계층).
- Retriever 3종을 역할별로 구분: `VectorRetriever`(임베딩 유사도 기반, 빠르고 의미 검색에 강함), `GraphRetriever`(그래프 관계 탐색, 다단계 추론에 강함), `HybridRetriever`(둘을 결합해 최상의 결과를 노림).
- 파이프라인은 두 단계로 나뉜다: **인덱싱 단계**(문서를 청크로 나누고 임베딩+엔티티 추출을 한 번 수행해 그래프/인덱스로 적재)와 **검색 단계**(사용자 질문마다 벡터 검색과 그래프 탐색을 실시간으로 조합).
- 비교표로 전통 RAG(벡터 유사도만, 관계 추론 불가, 청크가 서로 독립적)와 GraphRAG(벡터+그래프, 관계 추론 가능, 다단계 추론 자연스러움, 연결된 컨텍스트 구성 가능)를 재확인 — "세종대왕이 설립한 기관에서 누가 일했나요?"처럼 벡터 검색만으로는 답하기 어려운 질문을 예시로 든다.
- **neo4j-graphrag** 라이브러리 소개: `VectorRetriever`/`HybridRetriever`/`VectorCypherRetriever`(벡터 검색 + Cypher 확장) 등의 Retriever 클래스와, 검색-생성을 하나로 묶는 `GraphRAG` 파이프라인 클래스를 제공한다. 기본 사용 패턴:
```python
retriever = VectorRetriever(driver=driver, index_name="chunk_embeddings", embedder=embeddings)
rag = GraphRAG(retriever=retriever, llm=llm)
answer = rag.search(query="세종대왕의 업적은?")
```

## 7-2. 벡터 인덱스 만들기
원본: https://wikidocs.net/319224

- Neo4j는 벡터 인덱스를 기본 기능으로 지원해, 그래프 DB 안에서 임베딩 기반 유사도 검색을 직접 수행할 수 있다(별도의 외부 벡터DB 없이 하나의 시스템에서 그래프+벡터를 함께 다룰 수 있다는 것이 GraphRAG 구현의 실질적 이점).
- 실습은 한국사 관련 5개 청크(세종대왕, 훈민정음, 집현전, 장영실, 정조)를 `Chunk` 노드로 만들며 각 노드에 `text`, `source`, `embedding`(OpenAI 임베딩) 속성을 채우고, 각 청크가 언급하는 엔티티 노드와 `MENTIONS` 유형의 관계로 연결한다 — 즉 "청크 레이어"와 "엔티티/그래프 레이어"를 하나의 그래프 안에서 공존시키는 것이 이 실습의 핵심.
- 이후 Cypher(`CREATE VECTOR INDEX ...`) 또는 Python 코드로 `embedding` 속성 위에 벡터 인덱스를 생성하고, 인덱스 목록을 조회해 정상 생성 여부를 확인한다.
- 검색 테스트는 세 갈래로 제시된다: (1) Cypher로 직접 벡터 검색 procedure 호출, (2) Python에서 `neo4j-graphrag`의 `VectorRetriever`로 검색, (3) LangChain의 `Neo4jVector`를 사용하는 방법 — 목적에 따라 저수준 제어(Cypher/드라이버) 또는 프레임워크 편의성(LangChain) 중 선택 가능함을 보여준다.

## 7-3. 그래프+벡터 검색 결합
원본: https://wikidocs.net/319225

- GraphRAG의 성패는 "어떻게 검색하는가"에 달려 있다며 4가지 Retriever 전략을 비교: `VectorRetriever`(벡터만, 일반 질문용), `VectorCypherRetriever`(벡터 검색 후 Cypher로 그래프 확장, 관계 탐색이 필요할 때), `HybridRetriever`(벡터+전문/키워드 검색 결합), `HybridCypherRetriever`(Hybrid+Cypher 확장, 최대 성능이 필요할 때).
- **`VectorCypherRetriever`**가 이 절의 핵심: 먼저 벡터 유사도로 관련 Chunk를 찾은 뒤(`node`, `score`), `retrieval_query`에 지정한 Cypher로 그 청크가 언급하는 엔티티(`MENTIONS` 관계)와 그 엔티티의 추가 관계까지 확장 탐색해 컨텍스트를 풍부하게 만든다. 결과 포맷은 `result_formatter` 콜백으로 커스터마이즈할 수 있어, 청크 텍스트+언급 엔티티+관계 목록을 구조화된 형태로 함께 받을 수 있다.
- 이 패턴으로 "세종대왕이 설립한 기관에서 누가 일했나요?" 같은, 순수 벡터 검색만으로는 놓치기 쉬운 관계형 질문에 대해 벡터로 관련 청크를 먼저 찾고 그래프로 관계를 보강하는 하이브리드 답변이 가능해진다.
- 이어서 `HybridRetriever`(전문 검색 인덱스와 벡터 인덱스를 함께 사용하는 구성)와 컨텍스트 확장 패턴(1단계 관계 확장, 2단계 관계 확장, 특정 관계 유형만 선택적으로 탐색)을 다루며, 상황별 Retriever 선택 가이드로 마무리한다. Part8에서는 이 하이브리드 검색을 더 정교하게 튜닝하고 성능을 최적화하는 내용으로 이어진다.

---
이전: [Part6_지식그래프_만들기.md](./Part6_지식그래프_만들기.md) · 다음: [Part8_GraphRAG_고급기법.md](./Part8_GraphRAG_고급기법.md)
