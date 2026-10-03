require "test_helper"

class Payment::BulkSettlementTest < ActiveSupport::TestCase
  Entry = Struct.new(:payee_firm_id, :amount_cents, :description)

  setup do
    @payer = Firm.create!(name: "Payer", balance_cents: 100_000)
    @lopez = Firm.create!(name: "Lopez", balance_cents: 500)
    @nair = Firm.create!(name: "Nair")
  end

  test "debits payer, credits payees and records payments" do
    payments = settle(@payer, Entry.new(@lopez.id, 30_000, "a"), Entry.new(@nair.id, 20_000, "b"), Entry.new(@lopez.id, 5_000, nil))

    assert_equal 45_000, @payer.reload.balance_cents
    assert_equal 35_500, @lopez.reload.balance_cents
    assert_equal 20_000, @nair.reload.balance_cents
    assert_equal [ [ @lopez.id, 30_000, "a" ], [ @nair.id, 20_000, "b" ], [ @lopez.id, 5_000, nil ] ],
      payments.map { [ _1.payee_firm_id, _1.amount_cents, _1.description ] }
    assert payments.all? { _1.payer_firm_id == @payer.id && _1.persisted? }
  end

  test "spending the whole balance is allowed" do
    settle(@payer, Entry.new(@lopez.id, 100_000, nil))

    assert_equal 0, @payer.reload.balance_cents
  end

  test "insufficient funds raises and changes nothing" do
    assert_no_difference "Payment.count" do
      assert_raises(Payment::BulkSettlement::InsufficientFunds) do
        settle(@payer, Entry.new(@lopez.id, 60_000, nil), Entry.new(@nair.id, 40_001, nil))
      end
    end

    assert_equal [ 100_000, 500, 0 ], [ @payer, @lopez, @nair ].map { _1.reload.balance_cents }
  end

  test "payer listed as payee nets to zero" do
    settle(@payer, Entry.new(@payer.id, 10_000, nil), Entry.new(@lopez.id, 1_000, nil))

    assert_equal 99_000, @payer.reload.balance_cents
    assert_equal 1_500, @lopez.reload.balance_cents
  end

  test "retries on deadlock then succeeds" do
    calls = deadlock_on_where(times: 1) do
      settle(@payer, Entry.new(@lopez.id, 1_000, nil))
    end

    assert_equal 2, calls
    assert_equal 99_000, @payer.reload.balance_cents
  end

  test "gives up after max attempts" do
    calls = deadlock_on_where(times: 10) do
      assert_raises(ActiveRecord::Deadlocked) { settle(@payer, Entry.new(@lopez.id, 1_000, nil)) }
    end

    assert_equal Payment::BulkSettlement::MAX_ATTEMPTS, calls
  end

  private
    def deadlock_on_where(times:)
      calls = 0
      Firm.define_singleton_method(:where) { |*args, **kwargs| (calls += 1) <= times ? raise(ActiveRecord::Deadlocked) : super(*args, **kwargs) }
      yield
      calls
    ensure
      Firm.singleton_class.remove_method(:where)
    end

    def settle(payer, *entries)
      Payment::BulkSettlement.new(payer_id: payer.id, entries:).settle
    end
end
