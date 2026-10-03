# Firm Payments: bulk payment service

## Approach

The service exposes `POST /bulk_payments`. It's split into two pieces rather than one monolithic handler:

- `BulkPaymentRequest` (`app/models/bulk_payment_request.rb`) is the boundary: it validates the shape of the incoming JSON, resolves `payer_firm_uuid`/ `payee_firm_uuid` to firm ids, and converts dollar-string amounts to integer cents via `BigDecimal` (never `Float`, to avoid rounding errors). It does not touch the database beyond existence checks.
- `Payment::BulkSettlement` (`app/models/payment/bulk_settlement.rb`) is the actual domain operation: given a resolved payer id and a list of resolved entries, it runs the whole batch in one transaction, debits the payer, credits every payee, and writes the `payments` rows.

`BulkPaymentsController#create` wires the two together and maps outcomes to HTTP status: `201`, `422` for both a malformed request and insufficient funds (both expressed as validation / domain-exception failures, no bespoke status codes beyond what the spec asks for).

### Concurrency

The spec calls out that the server runs as multiple load-balanced instances, so correctness under concurrent requests was the actual core of the exercise, not the happy-path arithmetic.

`Payment::BulkSettlement` locks every firm involved in a batch — the payer **and** every distinct payee — in one query, ordered by id:

```ruby
Firm.where(id: involved_ids).order(:id).lock
```

A naive version that only locks the payer is enough to stop a firm from overspending its own balance, but it isn't enough on its own: firms pay each other in both directions in this domain (referral fees, overflow returns), so two concurrent batches moving money the opposite way between the same two firms can each lock their own payer row and then block on the other's - a deadlock. Locking the full, sorted set of participants up front removes the circular wait. A retry on `ActiveRecord::Deadlocked` (2-3 attempts) sits around the transaction as a second line of defense.

## Assumptions

- **Self-payment.** If `payer_firm_uuid` appears as one of its own `payee_firm_uuid` entries, the request is still processed: the amount is debited and credited back to the same firm. Not explicitly addressed by the spec; rejecting it outright felt like adding a rule that wasn't asked for.
- **Status codes.** The spec defines exactly two outcomes, 201 and 422. I kept to those two rather than introducing a 400/404 split for malformed requests vs. unknown firms vs. insufficient funds — all non-success paths return 422 with an `errors` describing what failed.
- **No idempotency key.** The request format has none, so retried requests (client timeout, load balancer retry) can double-process. Noted under Possible improvements rather than invented unasked.

## Possible improvements

- **Idempotency key** on the request, stored against the batch, so retried identical requests are detected and short-circuited rather than double-processed.
- **Double-entry ledger.** Balances currently live on a single mutable `firms.balance_cents` column, written alongside the `payments` rows in the same transaction. That's consistent given the locking above, but it means there's no immutable record of *why* a balance moved beyond the `payments` table itself. In a real system I'd want balances derived from (or reconciled against) an append-only ledger of debits/credits. Out of scope here since the given schema is exactly two tables and I treated that as fixed, not something to redesign for the exercise.
- **Per-leg settlement.** This service settles a batch as one atomic transaction, which is correct for the internal balance transfer described here (no external rails, no per-payment fees in the spec). A real multi-rail payments system usually can't gate an entire batch behind one all-or-nothing transaction, since each leg can fail independently further downstream. Flagging the distinction rather than building for a mechanism the spec doesn't describe.
- **Bulk insert.** Payments are created one at a time inside the loop; `insert_all` would cut round-trips for large batches.

## How to run and verify

```bash
bundle install
bin/rails db:setup
bin/rails test
```

Seed and sample request from the spec:

```bash
bin/rails runner '
  Firm.create!(name: "Pinecrest CPA Group", balance_cents: 50_00000, uuid: "3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41")
  Firm.create!(name: "Lopez Bookkeeping",   balance_cents: 50000,    uuid: "8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10")
  Firm.create!(name: "Nair Tax Services",   balance_cents: 200000,   uuid: "e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25")
'

curl -i -X POST http://localhost:3000/bulk_payments \
  -H "Content-Type: application/json" \
  -d '{
    "payer_firm_uuid": "3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41",
    "payments": [
      { "amount": "6250",    "payee_firm_uuid": "e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25", "description": "Overflow returns, August 2026" },
      { "amount": "5800.5",  "payee_firm_uuid": "e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25", "description": "Amended returns, August 2026" },
      { "amount": "1200.75", "payee_firm_uuid": "8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10", "description": "Bookkeeping cleanup, 3 clients" }
    ]
  }'
```

Expected: `201`, Pinecrest ends at 36,748.75, Lopez at 1,700.75, Nair at 14,050.50 — matching the worked example in the spec.

`test/models/payment/bulk_settlement_concurrency_test.rb` includes a concurrency tes that fires opposite-direction bulk payments between the same two firms from separate DB connections and asserts neither deadlocks nor leaves a negative balance.

## How much time did you spend on this task?

Less than 3 hours

## How proud are you of your work?

Fairly produd