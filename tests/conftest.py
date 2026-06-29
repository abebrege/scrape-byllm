"""Shared pytest fixtures and jaclang bootstrap.

``scrape_byLLM/__init__.py`` (the Python facade) installs jaclang's import hook
when it is first imported.  Importing the package here in conftest ensures the
hook is installed before any test file runs, so Jac sub-modules (robots.jac,
fetch.jac, scraper.jac) can be loaded by their tests.
"""

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

# Importing the facade bootstraps jaclang and caches the Python wrapper in
# sys.modules under "scrape_byLLM".  Because __init__.jac has been removed,
# the jaclang pytest plugin cannot shadow it with the Jac package init.
import scrape_byLLM  # noqa: F401, E402
