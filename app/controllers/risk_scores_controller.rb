class RiskScoresController < ApplicationController
  def create
    result = RiskScorer.new(score_params.to_h.deep_symbolize_keys).call
    render json: result, status: :ok
  rescue ActionController::ParameterMissing => error
    render_bad_request(error)
  rescue RiskScorer::InvalidInput => error
    render json: { error: error.message }, status: :unprocessable_entity
  rescue StandardError => error
    Rails.logger.error(
      "risk_scores.create_failed error_class=#{error.class} message=#{error.message}"
    )
    render json: { error: "Unable to score risk right now" }, status: :internal_server_error
  end

  private

  def score_params
    permitted = params.permit(
      customer: [
        :customer_type,
        { card: [:country, :funding, :age_months] },
        { history: [:successful_collections, :failed_collections, :days_since_last_successful_payment,
                    :average_order_value_cents, { recent_failed_reasons: [] }] }
      ],
      collection: [:amount_cents, :scheduled_at]
    )

    raise ActionController::ParameterMissing.new(:customer) if permitted[:customer].blank?
    raise ActionController::ParameterMissing.new(:collection) if permitted[:collection].blank?

    permitted
  end

  def render_bad_request(error)
    render json: { error: "Missing required parameter: #{error.param}" }, status: :bad_request
  end
end
