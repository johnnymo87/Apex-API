require 'sinatra'
require 'mechanize'
require 'json'

class Apex
  def initialize
    @browser = Mechanize.new
  end

  def login(username, password)
    url = 'https://fastsolutions.mroadmin.com/APEX-Login/account_login.action'
    login_data = {'user.login_id' => username, 'user.password' => password}
    response = @browser.post url, login_data
    response.code
  end

  def find_customers
    # @customers[0].keys =>
    # ["state", "siteName", "siteId", "statusCd", "class", "deviceCount", "city", "address1"]
    url = 'https://fastsolutions.mroadmin.com/Apex-Device/siteAction_viewSitesOwnedByMyCompany.action'
    response = @browser.get url
    response = response.content.split('|')
    @store = response[-1].chomp
    @customers = JSON.parse response[-2]
    @customers
  end

  def find_machines
    url = 'https://fastsolutions.mroadmin.com/Apex-Device/deviceBinAction_initDevicesList.action'
    @machines = {}
    @customers.each do |customer|
      params = {
        'actionSequence' => 20, 'requestId' => customer['siteId'],'comId' => @store,
        'newSortColumn' => 0, 'oldSortColumn' => 0, 'sortFlag' => 'null',
        'sortCancel' => 0, 'siteType' => 'owner'}
      response = @browser.get url, params
      response = response.content.split('|')
      machines = JSON.parse(response[-2])
      customer['machines'] = []
      machines.each do |machine|
        customer['machines'] << machine['deviceId']
        machine['siteId'] = customer['siteId']
        @machines[machine['deviceId']] = machine
      end
    end
    @machines
  end
end


#get('/') { a = Apex.new }
a = Apex.new

# curl -d "username=FLGANStore&password=password" http://localhost:5000/login
post '/login' do
  return a.login(params['username'], params['password']).to_json
end

#curl http://localhost:5000/customers.json
get '/customers.json' do
  content_type :json
  return a.find_customers.to_json
end

#curl http://localhost:5000/machines.json
get '/machines.json' do
  content_type :json
  return a.find_machines.to_json
end