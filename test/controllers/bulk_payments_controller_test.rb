require "test_helper"

class BulkPaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @payer = Firm.create!(name: "Payer", balance_cents: 1_000_00)
    @lopez = Firm.create!(name: "Lopez", balance_cents: 0)
    @nair = Firm.create!(name: "Nair", balance_cents: 0)
  end

  test "creates payments and moves balances" do
    assert_difference "Payment.count", 3 do
      post_bulk payments: [
        { amount: "62.50", payee_firm_uuid: @nair.uuid, description: "Overflow" },
        { amount: "58.5", payee_firm_uuid: @nair.uuid, description: "Amended" },
        { amount: "12.75", payee_firm_uuid: @lopez.uuid, description: "Cleanup" }
      ]
    end

    assert_response :created
    assert_equal [ 100_000 - 13_375, 1_275, 12_100 ], [ @payer, @lopez, @nair ].map { _1.reload.balance_cents }
  end

  test "denies the whole request when funds are insufficient" do
    assert_no_difference "Payment.count" do
      post_bulk payments: [
        { amount: "600", payee_firm_uuid: @lopez.uuid },
        { amount: "400.01", payee_firm_uuid: @nair.uuid }
      ]
    end

    assert_response :unprocessable_entity
    assert_equal [ "insufficient funds" ], response.parsed_body.dig("errors", "base")
    assert_equal [ 100_000, 0, 0 ], [ @payer, @lopez, @nair ].map { _1.reload.balance_cents }
  end

  test "denies an invalid request with field errors" do
    assert_no_difference "Payment.count" do
      post_bulk payer_firm_uuid: "nope", payments: [ { amount: "1.234", payee_firm_uuid: SecureRandom.uuid } ]
    end

    assert_response :unprocessable_entity
    assert_equal %w[ payer_firm_uuid payments[0].amount payments[0].payee_firm_uuid ], response.parsed_body["errors"].keys.sort
  end

  test "denies a missing or malformed payments list" do
    post_bulk payments: nil
    assert_response :unprocessable_entity

    post_bulk payments: "nope"
    assert_response :unprocessable_entity
    assert_equal [ "must be a non-empty array" ], response.parsed_body.dig("errors", "payments")
  end

  private
    def post_bulk(payer_firm_uuid: @payer.uuid, payments:)
      post bulk_payments_url, params: { payer_firm_uuid:, payments: }, as: :json
    end
end
