#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# mrr-floor-check/run.sh — daily MRR vs floor monitor.
# Pulls Stripe active subscriptions, sums monthly + annualized MRR, compares
# against data/finance/mrr_floor.yaml, snapshots to mrr_history/, alerts on breach.
set +e

REPO=/Users/bots/Dev/daily-ai-agent-os
HERMES_CONFIG=/Users/bots/.hermes/config.yaml
HISTORY_DIR="$REPO/data/finance/mrr_history"
FLOOR_YAML="$REPO/data/finance/mrr_floor.yaml"
DATE_STAMP=$(date +%Y-%m-%d)
SNAPSHOT="$HISTORY_DIR/${DATE_STAMP}.json"

mkdir -p "$HISTORY_DIR"

# Read Stripe key from Hermes config
SK=$(grep "STRIPE_SECRET_KEY" "$HERMES_CONFIG" 2>/dev/null | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
if [ -z "$SK" ]; then
  echo "STATUS=error reason=stripe-key-missing config=$HERMES_CONFIG"
  exit 2
fi

# Read floor + threshold from YAML (simple grep — no external yaml parser needed)
FLOOR_USD=$(grep -E "^floor_usd:" "$FLOOR_YAML" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ')
ALERT_PCT=$(grep -E "^alert_threshold_pct:" "$FLOOR_YAML" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ')
if [ -z "$FLOOR_USD" ] || [ -z "$ALERT_PCT" ]; then
  echo "STATUS=error reason=floor-yaml-malformed path=$FLOOR_YAML"
  exit 2
fi

# Fetch active subscriptions (paginated; cap at 100 — beyond that, the company has scaled past this skill's usefulness)
RESP=$(curl -sf -u "${SK}:" "https://api.stripe.com/v1/subscriptions?status=active&limit=100&expand[]=data.items.data.price" 2>&1)
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "STATUS=error reason=stripe-api-failed rc=$RC"
  # Fail-loud: Telegram Cooper
  if [ -x "$REPO/tools/notify/telegram_send.py" ]; then
    python3 "$REPO/tools/notify/telegram_send.py" --priority high \
      --text "🚨 mrr-floor-check FAILED — Stripe API error (rc=$RC). Check $HERMES_CONFIG STRIPE_SECRET_KEY validity." 2>/dev/null
  fi
  exit 1
fi

# Compute MRR via Python (stdlib only)
RESULT=$(python3 - "$RESP" "$FLOOR_USD" "$ALERT_PCT" "$DATE_STAMP" <<'PY'
import json, sys, datetime, pathlib
data = json.loads(sys.argv[1])
floor_usd = float(sys.argv[2])
alert_pct = float(sys.argv[3])
date_stamp = sys.argv[4]

subs_in = data.get("data", [])
mrr_cents = 0
sub_breakdown = []

for sub in subs_in:
    items = sub.get("items", {}).get("data", [])
    sub_id = sub.get("id", "")
    cust_id = sub.get("customer", "")
    sub_mrr_cents = 0
    for it in items:
        price = it.get("price", {})
        unit_amount = price.get("unit_amount") or 0
        qty = it.get("quantity", 1)
        recur = price.get("recurring", {}) or {}
        interval = recur.get("interval", "")
        if interval == "month":
            sub_mrr_cents += unit_amount * qty
        elif interval == "year":
            sub_mrr_cents += (unit_amount * qty) // 12
        # Other intervals (week, day) are extremely rare for SaaS — skip; log noisily if they appear
        elif interval and interval not in ("month", "year"):
            sub_breakdown.append({"sub_id": sub_id, "warning": f"unhandled-interval-{interval}"})
    mrr_cents += sub_mrr_cents
    sub_breakdown.append({
        "sub_id": sub_id,
        "customer_id": cust_id,
        "mrr_usd": round(sub_mrr_cents / 100, 2),
    })

current_mrr = round(mrr_cents / 100, 2)
threshold_usd = floor_usd * (alert_pct / 100.0)
alert_triggered = floor_usd > 0 and current_mrr < threshold_usd

snapshot = {
    "date": date_stamp,
    "current_mrr_usd": current_mrr,
    "floor_usd": floor_usd,
    "alert_threshold_pct": alert_pct,
    "alert_threshold_usd": round(threshold_usd, 2),
    "alert_triggered": alert_triggered,
    "subscription_count": len([s for s in sub_breakdown if "sub_id" in s and "warning" not in s]),
    "subscriptions": sub_breakdown,
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}

# Output: JSON snapshot, then a STATUS line on stderr-style stdout
print(json.dumps(snapshot, indent=2))
PY
)
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "STATUS=error reason=mrr-compute-failed rc=$RC"
  exit 1
fi

# Write snapshot
echo "$RESULT" > "$SNAPSHOT"

# Parse the values for status + telegram
CURRENT=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['current_mrr_usd'])")
ALERT=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['alert_triggered'])")
THRESH=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['alert_threshold_usd'])")
COUNT=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['subscription_count'])")

if [ "$ALERT" = "True" ]; then
  echo "STATUS=alert current_mrr=$CURRENT floor=$FLOOR_USD threshold=$THRESH subs=$COUNT snapshot=$SNAPSHOT"
  if [ -x "$REPO/tools/notify/telegram_send.py" ]; then
    python3 "$REPO/tools/notify/telegram_send.py" --priority high \
      --text "🚨 MRR FLOOR BREACH
Current MRR: \$${CURRENT}
Floor:       \$${FLOOR_USD}
Alert at:    \$${THRESH} (${ALERT_PCT}% of floor)
Active subs: ${COUNT}
Snapshot: data/finance/mrr_history/${DATE_STAMP}.json" 2>/dev/null
  fi
  # cont-11: also fire audible alert via voice-alert skill (Daniel/200wpm)
  if [ -x "$HOME/.hermes/skills/voice-alert/run.sh" ]; then
    bash "$HOME/.hermes/skills/voice-alert/run.sh" --priority high \
      --text "MRR floor breach. See Telegram for details." 2>/dev/null
  fi
else
  echo "STATUS=ok current_mrr=$CURRENT floor=$FLOOR_USD subs=$COUNT snapshot=$SNAPSHOT"
fi
