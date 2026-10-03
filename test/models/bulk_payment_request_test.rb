require "test_helper"

class BulkPaymentRequestTest < ActiveSupport::TestCase
  setup do
    @payer = Firm.create!(name: "Payer", balance_cents: 100_000)
    @payee = Firm.create!(name: "Payee")
  end

  test "valid request resolves uuids and converts amounts to cents" do
    bulk = build(payments: [
      { "amount" => "6250", "payee_firm_uuid" => @payee.uuid, "description" => "Overflow" },
      { "amount" => "5800.5", "payee_firm_uuid" => @payee.uuid }
    ])

    assert bulk.valid?, bulk.errors.full_messages.to_sentence
    assert_equal @payer.id, bulk.payer_firm_id
    assert_equal [ [ @payee.id, 625_000, "Overflow" ], [ @payee.id, 580_050, nil ] ],
      bulk.items.map { [ _1.payee_firm_id, _1.amount_cents, _1.description ] }
  end

  test "unknown or missing payer is invalid" do
    assert_invalid_on :payer_firm_uuid, build(payer_firm_uuid: SecureRandom.uuid)
    assert_invalid_on :payer_firm_uuid, build(payer_firm_uuid: nil)
  end

  test "malformed payer uuid is invalid without lookup" do
    bulk = build(payer_firm_uuid: "not-a-uuid")

    assert_not bulk.valid?
    assert_equal [ "is invalid" ], bulk.errors[:payer_firm_uuid]
  end

  test "payments must be a non-empty array" do
    assert_invalid_on :payments, build(payments: [])
    assert_invalid_on :payments, build(payments: { "amount" => "1" })
    assert_invalid_on :payments, build(payments: nil)
  end

  test "unknown payee is invalid" do
    assert_invalid_on :"payments[0].payee_firm_uuid", build(payments: [ { "amount" => "1", "payee_firm_uuid" => SecureRandom.uuid } ])
  end

  test "bad amounts are invalid" do
    [ "0", "0.00", "-5", "1.234", "abc", "1e3", "", nil, " 5" ].each do |amount|
      assert_invalid_on :"payments[0].amount", build(payments: [ { "amount" => amount, "payee_firm_uuid" => @payee.uuid } ]), amount.inspect
    end
  end

  test "non-object payment is invalid" do
    assert_invalid_on :"payments[0]", build(payments: [ "nope" ])
  end

  test "validation does not write" do
    assert_no_difference -> { Payment.count + Firm.count } do
      build(payments: [ { "amount" => "1", "payee_firm_uuid" => @payee.uuid } ]).valid?
    end
  end

  private
    def build(payer_firm_uuid: @payer.uuid, payments: [ { "amount" => "1", "payee_firm_uuid" => @payee.uuid } ])
      BulkPaymentRequest.new(payer_firm_uuid:, payments:)
    end

    def assert_invalid_on(attribute, bulk, message = nil)
      assert_not bulk.valid?, message
      assert bulk.errors.key?(attribute), "expected error on #{attribute}, got #{bulk.errors.attribute_names}"
    end
end
