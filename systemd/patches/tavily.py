import logging
from typing import Optional

import requests
from open_webui.retrieval.web.main import SearchResult, get_filtered_results

log = logging.getLogger(__name__)


def search_tavily(
    api_key: str,
    query: str,
    count: int,
    filter_list: Optional[list[str]] = None,
    # **kwargs,
) -> list[SearchResult]:
    """Search using Tavily's Search API and return the results as a list of SearchResult objects.

    PATCHED (CDCR ollama-stack 2026-05-27): see ../README.md "Web search tuning"
    for the full rationale. This patch sends Tavily four extra params and
    injects Tavily's synthesized 'answer' field as a citable first result.

      topic='news'         -- restricts to news articles. Required for `days` to
                              take effect; with `topic='general'` Tavily ignores
                              `days` and returns mixed-vintage results.
      days=3               -- bound to the last 72 hours. Tunes recall vs noise
                              for current events. Raise to 7 for broader sweeps.
      include_answer=True  -- ask Tavily to synthesize an answer paragraph from
                              all returned sources. We prepend this as the first
                              SearchResult so the chat model has a clean dated
                              summary to cite at index [1].
      (search_depth left as default 'basic'.) advanced is ~8x larger snippet
      payloads which blew up prefill time on llama3.2:3b CPU inference.

    Tradeoffs:
      - Costs Tavily credits proportional to results returned per call (and
        slightly more for include_answer).
      - The synthesized answer can drift if Tavily's underlying summarizer
        has a bad day; the real article snippets serve as crosschecks.
    """
    url = 'https://api.tavily.com/search'
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {api_key}',
    }
    data = {
        'query': query,
        'max_results': count,
        'topic': 'news',
        'days': 3,
        'include_answer': True,
    }
    response = requests.post(url, headers=headers, json=data)
    response.raise_for_status()

    json_response = response.json()

    results = json_response.get('results', [])
    if filter_list:
        results = get_filtered_results(results, filter_list)

    out = [
        SearchResult(
            link=result['url'],
            title=result.get('title', ''),
            snippet=result.get('content'),
        )
        for result in results
    ]

    # Prepend Tavily's synthesized current-state answer as a citable source.
    # The chat model sees this at index 0 and typically cites it as [1].
    answer = (json_response.get('answer') or '').strip()
    if answer:
        out.insert(0, SearchResult(
            link='https://api.tavily.com/',
            title='Tavily synthesized current-state summary',
            snippet=answer,
        ))

    return out
