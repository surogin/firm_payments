class Payment < ApplicationRecord
  belongs_to :payer_firm, class_name: "Firm", inverse_of: :payments_made
  belongs_to :payee_firm, class_name: "Firm", inverse_of: :payments_received

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
end
