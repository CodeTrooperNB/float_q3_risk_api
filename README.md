# Float Risk Scoring POC

This repository contains a small Rails API proof of concept that scores collection risk before an instalment payment attempt.

## Approach

The current build intentionally stays simple:

- one `POST /risk_scores` endpoint
- one `RiskScorer` PORO
- bounded input payloads
- deterministic heuristics
- human-readable reasons in the response

The scorer uses a small set of weighted rules based on signals from the brief:

- previous collection success/failure rate
- days since last successful payment
- card funding and age
- customer type
- time of month
- order value relative to the customer's history
- recent failure reasons, capped to a short window

The implementation keeps a clear seam between:

1. HTTP contract
2. feature extraction
3. score calculation
4. explanation generation

That seam is the AI/ML story for this POC. Today it runs deterministic rules. Later it can host a statistical scorer or an LLM explanation sidecar without changing the controller contract.

## Why This Approach

This case study is scoped to 3-4 hours, so the best tradeoff is a clean, inspectable rules engine rather than a fake-precise ML pipeline trained on toy data.

Why heuristics now:

- easier to read in one pass
- easier to demo live
- easier to test thoroughly
- easier to explain to a reviewer
- avoids pretending small seed data is a credible model-training content

Why the scorer seam still matters:

- the repo demonstrates where a future ML-backed scorer would plug in
- the README can discuss long-term architecture honestly
- the build stays deterministic for the live demo

## API

### `POST /risk_scores`

Example request:

```json
{
  "customer": {
    "customer_type": "returning",
    "card": {
      "country": "ZA",
      "funding": "credit",
      "age_months": 12
    },
    "history": {
      "successful_collections": 18,
      "failed_collections": 1,
      "days_since_last_successful_payment": 6,
      "average_order_value_cents": 15000,
      "recent_failed_reasons": []
    }
  },
  "collection": {
    "amount_cents": 14000,
    "scheduled_at": "2026-04-10"
  }
}
```

Example response:

```json
{
  "risk_score": 15,
  "risk_band": "low",
  "reasons": [
    "Customer has a stable recent collection profile"
  ]
}
```

### Validation behavior

- missing `customer` or `collection`: `400 Bad Request`
- malformed numeric/date fields: `422 Unprocessable Entity`
- unexpected scorer failure: `500 Internal Server Error`

## Demo Data

This API is stateless, so demo fixtures are stored in [`demo`](/Users/codetroopernb/Dev/FLOAT%20Case%20Study/float_q3_risk_api/demo):

- Low risk:
  [low_risk_1.json](./demo/low_risk_1.json),
  [low_risk_2.json](./demo/low_risk_2.json),
  [low_risk_3.json](./demo/low_risk_3.json)
- Medium risk:
  [medium_risk_1.json](./demo/medium_risk_1.json),
  [medium_risk_2.json](./demo/medium_risk_2.json),
  [medium_risk_3.json](./demo/medium_risk_3.json)
- High risk:
  [high_risk_1.json](./demo/high_risk_1.json),
  [high_risk_2.json](./demo/high_risk_2.json),
  [high_risk_3.json](./demo/high_risk_3.json)

Run the app:

```bash
bin/rails server
```

Try a demo request:

```bash
curl -X POST http://localhost:3000/risk_scores \
  -H "Content-Type: application/json" \
  --data @demo/high_risk_1.json
```

`bin/rails db:seed` prints the same demo fixture locations for convenience.

## Tests

Run the suite:

```bash
bin/rails test
```

The tests cover:

- request contract and error handling
- low/medium/high risk scenarios
- score band boundaries
- reason ordering
- bounded recent-history inputs
- empty-history and zero-average edge cases

## Tradeoffs

What this POC does well:

- clean Rails shape
- strong demo story
- deterministic, explainable output
- minimal diff without premature abstraction

What it deliberately does not do:

- persist scoring events
- train a real model
- separate prediction from policy in code yet
- shadow-score future models
- monitor drift or outcomes
- use an LLM in the live scoring path

## What I'd Do Next

If this moved beyond the case study, the next architectural steps would be:

1. add a decision ledger so scores are replayable by scorer version
2. introduce a champion/challenger lane for future scorers
3. add a formal evaluation harness before promotions
4. monitor feature drift, score drift, and realized outcomes
5. separate score generation from retry/policy decisions
6. add an LLM explanation sidecar only after the deterministic score contract is trusted
