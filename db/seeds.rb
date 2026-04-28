demo_payloads = Dir[Rails.root.join("demo", "*_risk_*.json")].sort

puts "This API is stateless, so demo data is shipped as JSON fixtures:"
demo_payloads.each do |payload|
  puts "- #{Pathname(payload).relative_path_from(Rails.root)}"
end

puts
puts "Run the server and try:"
puts "curl -X POST http://localhost:3000/risk_scores \\"
puts "  -H 'Content-Type: application/json' \\"
puts "  --data @demo/high_risk_1.json"
