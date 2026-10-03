require "test_helper"

class Payment::BulkSettlementConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  Entry = Struct.new(:payee_firm_id, :amount_cents, :description)

  THREADS = 4
  ROUNDS = 25

  setup do
    @a = Firm.create!(name: "A", balance_cents: 1_000_000)
    @b = Firm.create!(name: "B", balance_cents: 1_000_000)
  end

  teardown do
    Payment.where(payer_firm_id: [ @a.id, @b.id ]).delete_all
    Firm.where(id: [ @a.id, @b.id ]).delete_all
  end

  test "opposite-direction payments neither deadlock nor lose money" do
    without_retries do
      run_concurrently(THREADS) do |index|
        payer, payee = index.even? ? [ @a, @b ] : [ @b, @a ]
        ROUNDS.times { settle(payer, payee, 100) }
      end
    end

    assert_equal 2_000_000, @a.reload.balance_cents + @b.reload.balance_cents
    assert_equal 1_000_000, @a.balance_cents
    assert_equal THREADS * ROUNDS, Payment.where(payer_firm_id: [ @a.id, @b.id ]).count
  end

  test "concurrent payments cannot overdraw the payer" do
    @a.update!(balance_cents: 1_000)

    results = run_concurrently(10) do
      settle(@a, @b, 300)
      :paid
    rescue Payment::BulkSettlement::InsufficientFunds
      :denied
    end

    assert_equal [ 3, 7 ], [ results.count(:paid), results.count(:denied) ]
    assert_equal 100, @a.reload.balance_cents
    assert_equal 1_000_900, @b.reload.balance_cents
  end

  private
    def settle(payer, payee, cents)
      Payment::BulkSettlement.new(payer_id: payer.id, entries: [ Entry.new(payee.id, cents, nil) ]).settle
    end

    def run_concurrently(count)
      start = Queue.new
      threads = count.times.map do |index|
        Thread.new do
          start.pop
          ActiveRecord::Base.connection_pool.with_connection { yield index }
        end
      end
      count.times { start << true }
      threads.map(&:value)
    end

    def without_retries
      original = Payment::BulkSettlement::MAX_ATTEMPTS
      Payment::BulkSettlement.send(:remove_const, :MAX_ATTEMPTS)
      Payment::BulkSettlement.const_set(:MAX_ATTEMPTS, 1)
      yield
    ensure
      Payment::BulkSettlement.send(:remove_const, :MAX_ATTEMPTS)
      Payment::BulkSettlement.const_set(:MAX_ATTEMPTS, original)
    end
end
