class Payment::BulkSettlement
  class InsufficientFunds < StandardError; end

  MAX_ATTEMPTS = 3

  private attr_reader :payer_id, :entries

  def initialize(payer_id:, entries:)
    @payer_id = payer_id
    @entries = entries
  end

  def settle
    attempts = 0

    begin
      attempts += 1
      ApplicationRecord.transaction { settle_locked }
    rescue ActiveRecord::Deadlocked
      retry if attempts < MAX_ATTEMPTS
      raise
    end
  end

  private
    def settle_locked
      firms = Firm.where(id: firm_ids).order(:id).lock.index_by(&:id)
      payer = firms.fetch(payer_id)

      raise InsufficientFunds, "payer #{payer_id} has #{payer.balance_cents}, needs #{total_cents}" if payer.balance_cents < total_cents

      payer.update!(balance_cents: payer.balance_cents - total_cents)
      credits.each { |id, cents| firms.fetch(id).then { |firm| firm.update!(balance_cents: firm.balance_cents + cents) } }

      create_payments
    end

    def create_payments
      Payment.create!(entries.map { |entry|
        { payer_firm_id: payer_id, payee_firm_id: entry.payee_firm_id, amount_cents: entry.amount_cents, description: entry.description }
      })
    end

    def firm_ids
      [ payer_id, *entries.map(&:payee_firm_id) ].uniq
    end

    def total_cents
      entries.sum(&:amount_cents)
    end

    def credits
      entries.group_by(&:payee_firm_id).transform_values { |group| group.sum(&:amount_cents) }
    end
end
