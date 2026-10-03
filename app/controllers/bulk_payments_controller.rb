class BulkPaymentsController < ApplicationController
  def create
    bulk_payment = BulkPaymentRequest.new(bulk_payment_params)

    if bulk_payment.valid?
      Payment::BulkSettlement.new(payer_id: bulk_payment.payer_firm_id, entries: bulk_payment.items).settle
      head :created
    else
      render json: { errors: bulk_payment.errors.to_hash }, status: :unprocessable_entity
    end
  rescue Payment::BulkSettlement::InsufficientFunds
    render json: { errors: { base: [ "insufficient funds" ] } }, status: :unprocessable_entity
  end

  private
    def bulk_payment_params
      params.permit(:payer_firm_uuid, payments: [ :amount, :payee_firm_uuid, :description ]).to_h
    end
end
