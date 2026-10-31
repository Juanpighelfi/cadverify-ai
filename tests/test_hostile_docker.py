"""The hostile cases against the real session sandbox (cadverify.hostile).

No model and no API calls: the tool box is called as the model would. Runs on the host and is
skipped when Docker or the cadverify-sandbox image is not available.
"""

import pytest

from cadverify import hostile
from tests.test_agent_docker import pytestmark  # noqa: F401  (same skip condition)


@pytest.mark.parametrize("name", list(hostile.CASES))
def test_hostile_case(name, tmp_path):
    result = hostile.run_case(name, tmp_path)
    assert result["error"] is None, result["error"]
    failed = [check for check, ok in result["checks"].items() if ok is False]
    assert not failed, (failed, result["calls"])
