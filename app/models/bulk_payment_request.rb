class BulkPaymentRequest
  include ActiveModel::Model
  include ActiveModel::Attributes

  Item = Data.define(:payee_firm_id, :amount_cents, :description)

  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  AMOUNT_FORMAT = /\A\d+(\.\d{1,2})?\z/

  attribute :payer_firm_uuid, :string
  attribute :payments, default: -> { [] }

  validates :payer_firm_uuid, presence: true, format: { with: UUID_FORMAT, allow_blank: true }
  validate :payer_firm_must_exist
  validate :payments_must_be_valid

  def payer_firm_id
    firm_ids[payer_firm_uuid]
  end

  def items
    payments.map do |payment|
      payment = payment.with_indifferent_access
      Item.new(
        payee_firm_id: firm_ids[payment[:payee_firm_uuid]],
        amount_cents: amount_to_cents(payment[:amount]),
        description: payment[:description]
      )
    end
  end

  private
    def payer_firm_must_exist
      errors.add(:payer_firm_uuid, "is not a known firm") if payer_firm_uuid.to_s.match?(UUID_FORMAT) && payer_firm_id.nil?
    end

    def payments_must_be_valid
      if payments.is_a?(Array) && payments.any?
        payments.each_with_index { |payment, index| validate_payment(payment, index) }
      else
        errors.add(:payments, "must be a non-empty array")
      end
    end

    def validate_payment(payment, index)
      return errors.add(:"payments[#{index}]", "must be an object") unless payment.is_a?(Hash)

      payment = payment.with_indifferent_access
      errors.add(:"payments[#{index}].payee_firm_uuid", "is not a known firm") unless firm_ids.key?(payment[:payee_firm_uuid])
      errors.add(:"payments[#{index}].amount", "must be positive with at most 2 decimals") unless amount_to_cents(payment[:amount])&.positive?
    end

    def firm_ids
      @firm_ids ||= Firm.where(uuid: requested_uuids).pluck(:uuid, :id).to_h
    end

    def requested_uuids
      payees = Array(payments).filter_map { |payment| payment.with_indifferent_access[:payee_firm_uuid] if payment.is_a?(Hash) }
      [ payer_firm_uuid, *payees ].grep(String).uniq
    end

    def amount_to_cents(amount)
      (BigDecimal(amount.to_s) * 100).to_i if amount.to_s.match?(AMOUNT_FORMAT)
    end
end
