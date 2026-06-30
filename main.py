import argparse
import json
import sys

from comparison import run_comparison
from comparison_parameters import COMPARISONS, DEFAULT_COMPARISON

_RUN_KEYS = ("direct_anthropic", "byllm", "direct_byllm", "direct_pipeline")


def _compact(result: dict) -> dict:
    out = {}
    for key in _RUN_KEYS:
        synthesis = result.get(key, {}).get("synthesis", {})
        if not isinstance(synthesis, dict):
            synthesis = {}
        out[key] = {
            "summary": synthesis.get("summary", ""),
            "items": synthesis.get("items", []),
        }
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="Run scraping comparison benchmarks.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--name",
        metavar="NAME",
        help=f"Run a specific comparison. Choices: {', '.join(COMPARISONS)}",
    )
    group.add_argument("--all", action="store_true", help="Run all comparisons")
    parser.add_argument(
        "--verbose",
        action="store_true",
        default=False,
        help="Print full results and progress; default prints only summary+items per method",
    )
    args = parser.parse_args()

    if args.all:
        names = list(COMPARISONS.keys())
    elif args.name:
        if args.name not in COMPARISONS:
            print(
                f"Unknown comparison '{args.name}'. Available: {', '.join(COMPARISONS)}",
                file=sys.stderr,
            )
            sys.exit(1)
        names = [args.name]
    else:
        names = [DEFAULT_COMPARISON]

    for name in names:
        params = COMPARISONS[name]

        if args.verbose:
            print(f"\n=== {name} (category {params.category}, {params.failure_type}) ===")
            print(f"URL:   {params.url}")
            print(f"Query: {params.query}")

        result = run_comparison(params, verbose=args.verbose)

        with open(params.output_file, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)

        if args.verbose:
            print(f"  -> {params.output_file}")
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(json.dumps(_compact(result), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
