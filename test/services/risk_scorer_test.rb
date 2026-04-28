require "test_helper"

class RiskScorerTest < ActiveSupport::TestCase
  test "returns a stable low-risk profile when signals are calm" do
    result = RiskScorer.new(payload("low_risk_1")).call

    assert_equal 15, result.fetch(:risk_score)
    assert_equal "low", result.fetch(:risk_band)
    assert_equal ["Customer has a stable recent collection profile"], result.fetch(:reasons)
  end

  test "returns a medium-risk profile for mixed signals" do
    result = RiskScorer.new(payload("medium_risk_1")).call

    assert_equal "medium", result.fetch(:risk_band)
    assert_equal 45, result.fetch(:risk_score)
    assert_equal "Recent failures include insufficient funds", result.fetch(:reasons).first
  end

  test "returns an ordered high-risk explanation and clamps the score" do
    result = RiskScorer.new(payload("high_risk_1")).call

    assert_equal "high", result.fetch(:risk_band)
    assert_equal 100, result.fetch(:risk_score)
    assert_equal "Customer has a high failed collection rate", result.fetch(:reasons).first
  end

  test "all numbered demo payloads score into their labeled bands" do
    {
      "low" => %w[low_risk_1 low_risk_2 low_risk_3],
      "medium" => %w[medium_risk_1 medium_risk_2 medium_risk_3],
      "high" => %w[high_risk_1 high_risk_2 high_risk_3]
    }.each do |expected_band, names|
      names.each do |name|
        result = RiskScorer.new(payload(name)).call
        assert_equal expected_band, result.fetch(:risk_band), "#{name} should score as #{expected_band}"
      end
    end
  end

  test "treats missing history carefully without dividing by zero" do
    result = RiskScorer.new(
      customer: {
        customer_type: "new",
        card: { funding: "credit", age_months: 8 },
        history: {
          successful_collections: 0,
          failed_collections: 0,
          days_since_last_successful_payment: nil,
          average_order_value_cents: 0,
          recent_failed_reasons: []
        }
      },
      collection: {
        amount_cents: 12_000,
        scheduled_at: "2026-04-12"
      }
    ).call

    assert_equal "medium", result.fetch(:risk_band)
    assert_includes result.fetch(:reasons), "Customer has no collection history yet"
  end

  test "rejects unbounded recent failure lists" do
    invalid_payload = payload("low_risk_1")
    invalid_payload.dig(:customer, :history)[:recent_failed_reasons] = %w[a b c d e f]

    error = assert_raises(RiskScorer::InvalidInput) do
      RiskScorer.new(invalid_payload).call
    end

    assert_match(/at most 5 items/, error.message)
  end

  test "rejects invalid scheduled dates" do
    invalid_payload = payload("low_risk_1")
    invalid_payload[:collection][:scheduled_at] = "tomorrow-ish"

    error = assert_raises(RiskScorer::InvalidInput) do
      RiskScorer.new(invalid_payload).call
    end

    assert_match(/valid ISO 8601 date/, error.message)
  end

  test "derives risk bands at score boundaries" do
    scorer = RiskScorer.new(payload("low_risk_1"))

    assert_equal "low", scorer.send(:derive_band, 34)
    assert_equal "medium", scorer.send(:derive_band, 35)
    assert_equal "medium", scorer.send(:derive_band, 64)
    assert_equal "high", scorer.send(:derive_band, 65)
  end

  private

  def payload(name)
    JSON.parse(Rails.root.join("demo", "#{name}.json").read, symbolize_names: true)
  end
end
