require "test_helper"

class RiskScoresTest < ActionDispatch::IntegrationTest
  test "scores a low-risk payload" do
    post risk_scores_path, params: demo_payload("low_risk_1"), as: :json

    assert_response :success
    assert_equal "low", response_json.fetch("risk_band")
    assert_equal %w[risk_score risk_band reasons], response_json.keys
    assert_kind_of Array, response_json.fetch("reasons")
  end

  test "scores a medium-risk payload" do
    post risk_scores_path, params: demo_payload("medium_risk_1"), as: :json

    assert_response :success
    assert_equal "medium", response_json.fetch("risk_band")
  end

  test "scores a high-risk payload" do
    post risk_scores_path, params: demo_payload("high_risk_1"), as: :json

    assert_response :success
    assert_equal "high", response_json.fetch("risk_band")
    assert_equal 100, response_json.fetch("risk_score")
  end

  test "all demo payloads score into their labeled bands" do
    {
      "low" => %w[low_risk_1 low_risk_2 low_risk_3],
      "medium" => %w[medium_risk_1 medium_risk_2 medium_risk_3],
      "high" => %w[high_risk_1 high_risk_2 high_risk_3]
    }.each do |expected_band, names|
      names.each do |name|
        post risk_scores_path, params: demo_payload(name), as: :json

        assert_response :success, "#{name} should return 200"
        assert_equal expected_band, response_json.fetch("risk_band"), "#{name} should score as #{expected_band}"
      end
    end
  end

  test "returns bad request when top-level customer is missing" do
    post risk_scores_path, params: { collection: { amount_cents: 10_000, scheduled_at: "2026-04-10" } }, as: :json

    assert_response :bad_request
    assert_match(/customer/, response_json.fetch("error"))
  end

  test "returns unprocessable entity for invalid field types" do
    payload = demo_payload("low_risk_1")
    payload.fetch("collection")["amount_cents"] = "not-a-number"

    post risk_scores_path, params: payload, as: :json

    assert_response :unprocessable_entity
    assert_match(/amount_cents/, response_json.fetch("error"))
  end

  test "returns a clear internal server error when scoring crashes" do
    failing_scorer = Object.new
    def failing_scorer.call
      raise StandardError, "boom"
    end

    original_new = RiskScorer.method(:new)
    RiskScorer.singleton_class.define_method(:new) { |_payload| failing_scorer }

    post risk_scores_path, params: demo_payload("low_risk_1"), as: :json

    assert_response :internal_server_error
    assert_equal "Unable to score risk right now", response_json.fetch("error")
  ensure
    RiskScorer.singleton_class.define_method(:new, original_new)
  end

  private

  def demo_payload(name)
    JSON.parse(Rails.root.join("demo", "#{name}.json").read)
  end

  def response_json
    JSON.parse(response.body)
  end
end
