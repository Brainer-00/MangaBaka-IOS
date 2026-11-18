"""Verify Xcode registered every bundled alternate icon in the built app."""

import plistlib
import re
import sys
from pathlib import Path


def main() -> None:
    plist_path = Path(sys.argv[1])
    mapping = Path("lib/core/theme/ios_icon_variants.dart").read_text()
    expected = set(re.findall(r"'(Icon[A-Za-z]+)'", mapping))
    if len(expected) != 12:
        raise SystemExit(f"Expected 12 icon names in mapping, found {len(expected)}")

    with plist_path.open("rb") as source:
        info = plistlib.load(source)
    icons = info.get("CFBundleIcons", {})
    alternate = icons.get("CFBundleAlternateIcons", {})
    if set(alternate) != expected:
        raise SystemExit(
            f"Compiled alternate icons differ. Missing: {sorted(expected - set(alternate))}; "
            f"unexpected: {sorted(set(alternate) - expected)}"
        )
    print(f"Verified {len(expected)} compiled alternate icon registrations.")


if __name__ == "__main__":
    main()
