# Contributing

## Development setup

```bash
git clone https://github.com/abebrege/scrape-byLLM.git
cd scrape-byLLM
pip install -e ".[dev]"
```

Copy `.env.example` to `.env` and add your `ANTHROPIC_API_KEY` (only needed for
tests that make live LLM calls).

## Running tests

```bash
pytest tests/ -v
```

Lint and type-check:

```bash
ruff check .
mypy scrape_byllm/
```

## Submitting changes

1. Fork the repository and create a feature branch from `main`.
2. Write tests for any new behaviour.
3. Make sure `pytest`, `ruff check`, and `mypy` all pass.
4. Open a pull request with a clear description of the change and its motivation.

## Coding conventions

- Jac sources live in `scrape_byLLM/`; the Python facade lives in `scrape_byllm/`.
- Keep LLM call counts minimal — the planner is called once per unique
  `(pattern, query)` pair and its result is cached.
- All public Python functions and classes must have type annotations.

## Reporting bugs

Please open an issue using the bug-report template and include a minimal
reproducible example.
