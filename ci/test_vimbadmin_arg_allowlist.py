#!/usr/bin/env python3
"""Regression checks for the ViMbAdmin inner Angie query allowlist."""

import os
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = Path(os.environ.get("VIMBADMIN_ANGIE_CONFIG", ROOT / "src/vimbadmin/angie.conf"))


def allowlist_pattern():
    text = CONFIG.read_text(encoding="utf-8")
    match = re.search(
        r'map \$args \$vimb_bad_args \{.*?^\s+"~\*(\^.*\$)" 0;',
        text,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError("ViMbAdmin argument allowlist pattern not found")
    return re.compile(match.group(1), re.IGNORECASE)


class VimbadminArgAllowlistTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pattern = allowlist_pattern()

    def assert_allowed(self, query):
        self.assertIsNotNone(self.pattern.fullmatch(query), query)

    def assert_denied(self, query):
        self.assertIsNone(self.pattern.fullmatch(query), query)

    def test_datatables_2_encoded_wire_is_allowed(self):
        self.assert_allowed(
            "draw=1&start=0&length=50"
            "&search%5Bvalue%5D=&search%5Bregex%5D=false"
            "&order%5B0%5D%5Bcolumn%5D=0"
            "&order%5B0%5D%5Bdir%5D=asc"
            "&order%5B0%5D%5Bname%5D="
            "&columns%5B0%5D%5Bdata%5D=name"
            "&columns%5B0%5D%5Bname%5D="
            "&columns%5B0%5D%5Bsearchable%5D=true"
            "&columns%5B0%5D%5Borderable%5D=true"
            "&columns%5B0%5D%5Bsearch%5D%5Bvalue%5D="
            "&columns%5B0%5D%5Bsearch%5D%5Bregex%5D=false&_="
        )

    def test_literal_brackets_and_multi_digit_indices_are_allowed(self):
        self.assert_allowed(
            "draw=2&order[10][column]=10&columns[10][data]=name"
            "&columns[10][search][value]=example"
        )

    def test_normal_application_arguments_remain_allowed(self):
        self.assert_allowed("domain=example.com&active=1&csrf_token=abc")

    def test_unknown_nested_members_are_denied(self):
        for query in (
            "draw=1&search%5Bscript%5D=x",
            "draw=1&order%5B0%5D%5Bscript%5D=x",
            "draw=1&columns%5B0%5D%5Bscript%5D=x",
            "draw=1&columns%5B0%5D%5Bsearch%5D%5Bscript%5D=x",
        ):
            with self.subTest(query=query):
                self.assert_denied(query)

    def test_legacy_only_datatables_names_are_denied(self):
        self.assert_denied("sEcho=1&iDisplayStart=0&iDisplayLength=50")

    def test_unrelated_argument_is_denied(self):
        self.assert_denied("draw=1&evil_unexpected_param=1")


if __name__ == "__main__":
    unittest.main()
