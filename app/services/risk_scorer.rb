class RiskScorer
  InvalidInput = Class.new(StandardError)

  BASE_SCORE = 15
  MAX_SCORE = 100
  MAX_RECENT_FAILED_REASONS = 5

  def initialize(payload)
    @payload = payload
  end

  def call
    normalized = normalize_input
    features = extract_features(normalized)
    score, weighted_reasons = compute_score(features)

    {
      risk_score: score,
      risk_band: derive_band(score),
      reasons: build_reasons(weighted_reasons)
    }
  end

  private

  attr_reader :payload

  def normalize_input
    customer = payload.fetch(:customer) { raise InvalidInput, "customer is required" }
    collection = payload.fetch(:collection) { raise InvalidInput, "collection is required" }
    history = customer[:history] || {}
    card = customer[:card] || {}
    recent_failed_reasons = normalize_recent_failed_reasons(history[:recent_failed_reasons])

    {
      customer_type: normalize_string(customer[:customer_type]),
      card_country: normalize_string(card[:country]),
      card_funding: normalize_string(card[:funding]),
      card_age_months: optional_integer(card[:age_months], "customer.card.age_months"),
      successful_collections: integer!(history[:successful_collections], "customer.history.successful_collections"),
      failed_collections: integer!(history[:failed_collections], "customer.history.failed_collections"),
      days_since_last_successful_payment: optional_integer(
        history[:days_since_last_successful_payment],
        "customer.history.days_since_last_successful_payment"
      ),
      average_order_value_cents: optional_integer(
        history[:average_order_value_cents],
        "customer.history.average_order_value_cents"
      ),
      recent_failed_reasons: recent_failed_reasons,
      amount_cents: integer!(collection[:amount_cents], "collection.amount_cents"),
      scheduled_at: date!(collection[:scheduled_at], "collection.scheduled_at")
    }
  end

  def normalize_recent_failed_reasons(value)
    return [] if value.nil?
    raise InvalidInput, "customer.history.recent_failed_reasons must be an array" unless value.is_a?(Array)
    if value.length > MAX_RECENT_FAILED_REASONS
      raise InvalidInput, "customer.history.recent_failed_reasons can include at most #{MAX_RECENT_FAILED_REASONS} items"
    end

    value.map { |reason| normalize_string(reason) }.compact
  end

  def extract_features(input)
    total_collections = input[:successful_collections] + input[:failed_collections]
    failure_rate = total_collections.zero? ? nil : input[:failed_collections].to_f / total_collections
    amount_ratio = if input[:average_order_value_cents].to_i.positive?
      input[:amount_cents].to_f / input[:average_order_value_cents]
    end

    input.merge(
      total_collections: total_collections,
      failure_rate: failure_rate,
      amount_ratio: amount_ratio,
      scheduled_day: input[:scheduled_at].day,
      has_recent_insufficient_funds: input[:recent_failed_reasons].include?("insufficient_funds"),
      has_recent_expired_card: input[:recent_failed_reasons].include?("expired_card")
    )
  end

  def compute_score(features)
    score = BASE_SCORE
    reasons = []

    if features[:total_collections].zero?
      score += 12
      reasons << [12, "Customer has no collection history yet"]
    elsif features[:failure_rate] >= 0.5
      score += 28
      reasons << [28, "Customer has a high failed collection rate"]
    elsif features[:failure_rate] >= 0.25
      score += 18
      reasons << [18, "Customer has a mixed recent collection record"]
    elsif features[:failure_rate] >= 0.1
      score += 8
      reasons << [8, "Customer has a small recent collection failure pattern"]
    end

    if features[:days_since_last_successful_payment].to_i > 45
      score += 18
      reasons << [18, "Last successful payment was more than 45 days ago"]
    elsif features[:days_since_last_successful_payment].to_i > 21
      score += 10
      reasons << [10, "Last successful payment was more than 3 weeks ago"]
    end

    if features[:amount_ratio].to_f >= 1.5
      score += 18
      reasons << [18, "Collection amount is much higher than the customer's usual order value"]
    elsif features[:amount_ratio].to_f >= 1.2
      score += 10
      reasons << [10, "Collection amount is above the customer's usual order value"]
    end

    if features[:customer_type] == "new"
      score += 8
      reasons << [8, "New customers have less payment history to rely on"]
    end

    case features[:card_funding]
    when "prepaid"
      score += 10
      reasons << [10, "Prepaid cards can have less predictable available balances"]
    when "debit"
      score += 4
      reasons << [4, "Debit collections can be more sensitive to available balance timing"]
    end

    if features[:card_age_months].to_i >= 48
      score += 12
      reasons << [12, "Card has been on file for a long time and may be stale"]
    elsif features[:card_age_months].to_i >= 24
      score += 6
      reasons << [6, "Card has been on file for over 2 years"]
    end

    if features[:card_country].present? && features[:card_country] != "za"
      score += 4
      reasons << [4, "Card country differs from the core collection market"]
    end

    if features[:scheduled_day] >= 25
      score += 8
      reasons << [8, "Collection is scheduled late in the month when balances can be tighter"]
    end

    if features[:has_recent_expired_card]
      score += 16
      reasons << [16, "Recent failures include an expired card"]
    elsif features[:has_recent_insufficient_funds]
      score += 12
      reasons << [12, "Recent failures include insufficient funds"]
    end

    [score.clamp(0, MAX_SCORE), reasons]
  end

  def derive_band(score)
    return "high" if score >= 65
    return "medium" if score >= 35

    "low"
  end

  def build_reasons(weighted_reasons)
    sorted = weighted_reasons.sort_by { |weight, _reason| -weight }.map(&:last)
    sorted.presence || ["Customer has a stable recent collection profile"]
  end

  def integer!(value, field_name)
    Integer(value)
  rescue ArgumentError, TypeError
    raise InvalidInput, "#{field_name} must be an integer"
  end

  def optional_integer(value, field_name)
    return nil if value.nil?

    integer!(value, field_name)
  end

  def date!(value, field_name)
    raise InvalidInput, "#{field_name} is required" if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    raise InvalidInput, "#{field_name} must be a valid ISO 8601 date"
  end

  def normalize_string(value)
    return nil if value.blank?

    value.to_s.strip.downcase
  end
end
