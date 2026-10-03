class Firm < ApplicationRecord
  has_many :payments_made, class_name: "Payment", foreign_key: :payer_firm_id, inverse_of: :payer_firm
  has_many :payments_received, class_name: "Payment", foreign_key: :payee_firm_id, inverse_of: :payee_firm

  validates :name, presence: true
end
