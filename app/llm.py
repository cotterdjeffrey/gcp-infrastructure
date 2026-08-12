"""Generation layer: streams a grounded answer from the Claude API.

ANTHROPIC_API_KEY is read from the environment. In-cluster it is synced from GCP
Secret Manager by the Secrets Store CSI driver (Workload Identity) — never baked
into the image, the manifest, or the repo.
"""

import os
from collections.abc import AsyncGenerator

import anthropic

# Default to Claude Opus 5. For a high-volume chat workload, claude-sonnet-5 or
# claude-haiku-4-5 trade some capability for lower cost/latency — a one-env-var
# change, no code edit.
ANTHROPIC_MODEL = os.getenv("ANTHROPIC_MODEL", "claude-opus-5")
MAX_TOKENS = int(os.getenv("ANTHROPIC_MAX_TOKENS", "1024"))

SYSTEM_PROMPT = (
    "You are Pocket Preacher, a friendly and conversational Bible guide. "
    "Answer questions using ONLY the provided Bible passages. "
    "Cite verses naturally in your responses (e.g., 'As John 3:16 tells us...'). "
    "Be warm but not preachy. If the passages don't contain relevant information, "
    "say so honestly rather than making things up. "
    "IMPORTANT: You are ONLY a Bible study guide. If the user asks for something "
    "that is not a question about Scripture, theology, or biblical teaching, "
    "politely decline and redirect them to ask about the Bible instead."
)

BACKEND_ERROR_MESSAGE = (
    "Sorry — I'm having trouble reaching my study notes right now. "
    "Please try again in a moment. (The language model backend returned an error.)"
)

_client: anthropic.AsyncAnthropic | None = None


def _get_client() -> anthropic.AsyncAnthropic:
    global _client
    if _client is None:
        _client = anthropic.AsyncAnthropic()  # reads ANTHROPIC_API_KEY
    return _client


def _build_context_block(passages: list[dict]) -> str:
    lines = ["Here are relevant Bible passages:\n"]
    for p in passages:
        lines.append(f"[{p['reference']}] {p['text']}")
    return "\n".join(lines)


async def chat_stream(
    message: str,
    passages: list[dict],
    history: list[dict] | None = None,
) -> AsyncGenerator[str, None]:
    """Stream a grounded answer from Claude. Yields a friendly message on API error."""
    context = _build_context_block(passages)
    messages = list(history or [])
    messages.append(
        {"role": "user", "content": f"{context}\n\nUser question: {message}"}
    )

    try:
        async with _get_client().messages.stream(
            model=ANTHROPIC_MODEL,
            max_tokens=MAX_TOKENS,
            system=SYSTEM_PROMPT,
            messages=messages,
        ) as stream:
            async for text in stream.text_stream:
                yield text
    except anthropic.APIError:
        yield BACKEND_ERROR_MESSAGE
