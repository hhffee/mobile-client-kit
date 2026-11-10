"""Generate private build config from environment, without printing credentials."""
import json
import os
from pathlib import Path
import re
import sys


def configuration(env):
    api_id = env.get("TELEGRAM_API_ID", "")
    api_hash = env.get("TELEGRAM_API_HASH", "")
    bundle = env.get("AYU_BUNDLE_ID", "org.personal.ayupersonal")
    team = env.get("APPLE_TEAM_ID", "0000000000")
    if not api_id.isdigit() or not 0 < int(api_id) <= 2**31 - 1:
        raise ValueError("Set TELEGRAM_API_ID to your application api_id from my.telegram.org/apps")
    if not re.fullmatch(r"[a-fA-F0-9]{32}", api_hash):
        raise ValueError("Set TELEGRAM_API_HASH to your application api_hash from my.telegram.org/apps")
    if not re.fullmatch(r"[A-Za-z0-9]+(?:\.[A-Za-z0-9-]+){2,}", bundle):
        raise ValueError("AYU_BUNDLE_ID must be a reverse-domain bundle identifier")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("APPLE_TEAM_ID must contain 10 uppercase letters/digits")
    return {
        "bundle_id": bundle, "api_id": api_id, "api_hash": api_hash,
        "team_id": team, "is_internal_build": "false", "is_appstore_build": "false",
        "appstore_id": "0", "app_specific_url_scheme": "ayupersonal",
        "premium_iap_product_id": "", "enable_siri": False, "enable_icloud": False,
    }


if __name__ == "__main__":
    try:
        result = configuration(os.environ)
        destination = Path(sys.argv[1])
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print("Private build configuration written.")
    except (ValueError, IndexError) as error:
        raise SystemExit(str(error))
