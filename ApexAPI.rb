require 'sinatra'
require 'mechanize'
require 'json'

# http://shielded-mesa-1340.herokuapp.com/

class Apex
  def initialize
    @browser = Mechanize.new
  end

  def login(username, password)
    url = 'https://fastsolutions.mroadmin.com/APEX-Login/account_login.action'
    login_data = {'user.login_id' => username, 'user.password' => password}
    response = @browser.post(url, login_data).content
    if response =~ /Invalid login!/
      'Invalid login!'
    else
      # comId not available unless I navigate further
      url = 'https://fastsolutions.mroadmin.com/Apex-Device/siteAction_getSelectedCompanyList.action'
      response = @browser.get(url).content
      response = JSON.parse(response)[0]
      @store = response['tableId']
      # throw out useless data
      response = {'name' => response['name'], 'comId' => response['tableId']}
      response
    end
  end

  def find_customers
    # @customers[0].keys =>
    # ["state", "siteName", "siteId", "statusCd", "class", "deviceCount", "city", "address1"]
    url = 'https://fastsolutions.mroadmin.com/Apex-Device/siteAction_viewSitesOwnedByMyCompany.action'
    response = @browser.get(url).content.split('|')
    @customers = JSON.parse response[-2]
    #@customers = Hash[@customers.map { |c| [c['siteId'], c] }]
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
      response = @browser.get(url, params).content.split('|')
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

  def find_parts_info(site_id)
    parts_info = {}
    url = 'https://fastsolutions.mroadmin.com/ProductManager/product_listSiteProductAjax.action'
    params = {'page' => 1, 'companyId' => @store, 'siteId' => site_id}
    response = @browser.get(url, params).content.split('|')
    pages = Nokogiri::HTML(response[0])
    pages = pages.at_css('.table_head').content
    pages = pages.scan(/\w+/)[4].to_i
    (0...pages).each do
      rows = JSON.parse(response[-2])
      rows.each do |row|
        sku = row['productNum1'][/[\d\w\[\]-]+/]
        parts_info[sku] = row
      end
      params['page'] += 1
      response = @browser.get(url, params).content.split('|')
    end
    parts_info
  end

  def find_machine_counts(site_id, device_id)
    counts = {}
    url = 'https://fastsolutions.mroadmin.com/Apex-Device/devicePOGAction_detailPOG.action'
    params = {'comId' => @store, 'siteId' => site_id, 'requestId' => device_id}
    response = @browser.get(url, params).content
    response = Nokogiri::HTML(response)
    row_ids = response.css('.tableContainer tr')
    row_ids = row_ids.select { |node| node.values[0].to_s =~ /tr/ or node.values[0].to_s =~ /lockerTr/ }
    row_ids = row_ids.collect { |node| node.values[0].to_s}
    row_ids.each do |id|
      row = response.css("tr##{id} td")
      row = row.collect { |node| node.content.to_s.strip}[0...-2]
      if id =~ /tr/
        row = {'position' => row[0], 'description' => row[1], 'sku' => row[2], 'count' => row[3],
               'capacity' => row[4], 'max' => row[5], 'min' => row[6], 'critical' => row[7],
               'available_offline' => row[8], 'status' => row[9]}
      elsif id =~ /lockerTr/
        # lockers have no capacity
        row = {'position' => row[0], 'description' => row[1], 'sku' => row[2], 'count' => row[3],
               'max' => row[4], 'min' => row[5], 'critical' => row[6], 'available_offline' => row[7],
               'status' => row[8]}
      end
      counts[row['position'].to_i] = row
    end
    counts
  end

  def find_transaction_details(site_id, device_id, begin_date, end_date)
    transactions = []
    url = 'https://fastsolutions.mroadmin.com/ReportManager/transactionReportAction_viewTransaction.action'
    params = {'page' => 1, 'beginDate' => begin_date, 'endDate' => end_date,
              'checkBoxFileds' => 'Date|ActionDate,Product SKU|ProductNum1,Quantity Dispensed|QtyDispensed,Package Qty|PackageQty',
              'companyId' => @store, 'sideIdTmp' => site_id, 'deviceId' => device_id, 'searchFlag' => 'SEARCH', 'companyType' => 'OWNER'}
    response = @browser.get(url, params).content
    response = JSON.parse(response)[0]['showPageData']
    response = Nokogiri::HTML(response)
    pages = response.at_css('#pageLinknull').content
    pages = pages.scan(/\w+/)[4].to_i
    (0...pages).each do
      rows = response.css('.stripe_tb tr')
      rows.each do |row|
        columns = row.css('td')
        record = []
        (0...columns.length).each do |i|
          record << columns[i].content.strip
        end
        transactions << record
      end
      params['page'] += 1
      response = @browser.get(url, params).content
      response = JSON.parse(response)[0]['showPageData']
      response = Nokogiri::HTML(response)
    end
    transactions = transactions[0...-2]
    transactions
  end

  def find_transaction_summary(site_id, device_id, begin_date, end_date)
    url = 'https://fastsolutions.mroadmin.com/ReportManager/usageReportAction_getOwnerReportByDeviceBinValue.action'
    params = {'company.companyId' => @store, 'siteIdTmp' => site_id, 'deviceIdTemp' => device_id,
              'beginDate' => begin_date, 'endDate' => end_date, 'reportType' => 'owner', 'currencyCode' => 'USD'}
    response = @browser.get(url, params).content.split('|')
    response = JSON.parse(response[-1])[0...-1]
    response
  end
end


#get('/') { a = Apex.new }
a = Apex.new

# curl -d 'username=FLGANStore&password=password' http://localhost:5000/login.json
post '/login.json' do
  content_type :json
  return a.login(params['username'], params['password']).to_json
end

# curl http://localhost:5000/customers.json
get '/customers.json' do
  content_type :json
  return a.find_customers.to_json
end

# curl http://localhost:5000/machines.json
get '/machines.json' do
  content_type :json
  return a.find_machines.to_json
end

# curl -d 'site_id=SIT100110786' http://localhost:5000/parts_info.json
post '/parts_info.json' do
  content_type :json
  return a.find_parts_info(params['site_id']).to_json
end

# curl -d 'site_id=SIT100110786&device_id=DEV100115202' http://localhost:5000/machine_counts.json
post '/machine_counts.json' do
  content_type :json
  return a.find_machine_counts(params['site_id'], params['device_id']).to_json
end

# curl -d 'site_id=SIT100110786&device_id=DEV100115202&begin_date=08/01/2013&end_date=08/31/2013' http://localhost:5000/transaction_details.json
post '/transaction_details.json' do
  content_type :json
  return a.find_transaction_details(params['site_id'], params['device_id'], params['begin_date'], params['end_date']).to_json
end

# curl -d 'site_id=SIT100110786&device_id=DEV100115202&begin_date=08/01/2013&end_date=08/31/2013' http://localhost:5000/transaction_details.json
post '/transaction_summary.json' do
  content_type :json
  return a.find_transaction_summary(params['site_id'], params['device_id'], params['begin_date'], params['end_date']).to_json
end