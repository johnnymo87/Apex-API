require 'sinatra'
require 'json'

get '/machines.json' do
  content_type :json
  return {
      'customer' => %w(machine1 machine2)
  }.to_json
end