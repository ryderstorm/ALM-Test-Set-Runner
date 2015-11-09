def connect_alm
	# Create the TDConnection object
	@alm = WIN32OLE.new('TDApiOle80.TDConnection')
	qcserver = $settings[:qcserver]

	# Initiate connection to the QC server
	plog "Connecting to #{qcserver.yellow}..."
	@alm.InitConnectionEx(qcserver)
	unless @alm.Connected
		plog "Error connecting to ALM".red
		return false
	end
	plog "ALM connected? " + @alm.Connected.to_s.green

	# Authenticates to QC
	@alm.Login($settings[:alm_user], $settings[:alm_password])
	unless @alm.LoggedIn
		plog "Error logging in to ALM".red
		return false
	end
	plog "ALM logged in? " + @alm.LoggedIn.to_s.green

	# Connect to the QC Domain and Project
	@alm.Connect($settings[:alm_domain], $settings[:alm_project])
	if @alm.ProjectName.empty?
		plog "Error connecting to ALM project".red
		return false
	end
	plog "ALM Domain Name: " + @alm.DomainName.to_s.yellow
	plog "ALM Project Name: " + @alm.ProjectName.to_s.yellow
	plog "Successfully connected to ALM!".green
	return true
rescue => e
	plog report_error(e, "Error encountered in [#{__method__.to_s}]")
	return false
end

def disconnect_alm
	plog "Logging out of ALM..."
	if @alm.nil?
		plog "@alm object is nil, no need to disconnect."
		return
	end

	if @alm.Connected
		# Disconnect and Logout from QC
		@alm.Disconnect
		@alm.Logout
		plog "Logged in status: #{@alm.LoggedIn.to_s.yellow}"

		# Release connection from the QC server
		@alm.ReleaseConnection
		plog "Connection status: #{@alm.Connected.to_s.yellow}"
		if @alm.Connected == 'true'
			plog "Error disconnecting from ALM!"
		else
			plog "Successfully disconnected from ALM server."
			@alm = nil
		end
	else
		@alm = nil
		plog "ALM already disconnected."
	end
rescue => e
	plog report_error(e, "Error encountered in [#{__method__.to_s}]")
end

def get_test_sets_from_alm(path:, test_set_name:nil, test_name:nil, automation_status:nil)
	# retrieves test sets from Test Lab based on Test Lab folder path, test set name, test name, and test status
	if @alm.nil?
		puts "Cannot get tests from ALM unless connected to ALM!".red
		return false
	end
	# finds all the tests in the folder defined by [path]
	# will retrieve tests in all test sets unless test_set_name is specified
	# will NOT get tests in subfolders
	test_sets_found = []
	tests_found = []
	plog "Getting tests from path: " + path.yellow
	plog "Only getting tests in test set: " + test_set_name.yellow unless test_set_name.nil?
	plog "Only getting tests with names that match: " + test_name.yellow unless test_name.nil?
	plog "Only getting tests with status: " + automation_status.yellow unless automation_status.nil?
	folder = path.split("\\").last
	# ==================
	# ??add logic to filter the test_sets list using the ALM filter??
	# ==================
	test_sets = @alm.TestSetTreeManager.NodeByPath(path).TestSetFactory.NewList("")
	test_count = 0
	i = 0
	test_sets.each do |test_set|
		unless test_set_name.nil?
			next unless test_set_name == test_set.Name
		end
		test_filter_object = test_set.TSTestFactory.Filter
		unless automation_status.nil?
			test_filter_object["TS_STATUS"] = automation_status
		end
		unless test_name.nil?
			test_filter_object["TS_NAME"] = test_name
		end
		filter = test_filter_object.Text
		filtered_test_list = test_set.TSTestFactory.NewList(filter)
		test_set_object = Test_Set.new(test_set, filtered_test_list)
		test_count += filtered_test_list.Count
		filtered_test_list.each do |test|
			i += 1
			new_test = Test.new(test, test_set_object.name, test_set_object.id)
			test_set_object.add_test new_test
			tests_found.push new_test
			log "Found test: #{new_test.name.blue}"
			print "\rFound #{tests_found.count.to_s.rjust(3, '0')} tests | #{get_percent_complete(i, test_count)}"
			# print "\rFound #{tests_found.count.to_s.rjust(3, '0')} tests..\t\t"
		end
		test_sets_found.push test_set_object
	end
	puts "\n=================================\n".blue
	plog "Finished loading test sets. Found #{test_sets_found.count.to_s.yellow} test sets and #{tests_found.count.to_s.yellow} tests."
	return test_sets_found, tests_found
rescue => e
	plog report_error(e, "Error encountered in [#{__method__.to_s}]")
end

def run_edi_test
	start_time = Time.now
	hosts = $settings[:test_host].split('|')
	path = $settings[:test_set_path]
	test_set_name = $settings[:test_set_name]
	unless connect_alm
		log "Exiting due to ALM connection failure".yellow
		exit
	end
	@test_sets, @tests = get_test_sets_from_alm(path:path, test_set_name:test_set_name)
	edi_test_set = @test_sets.first
	edi_test_set.display_tests
	edi_test_set.hosts = hosts
	puts "Preparing host: #{hosts.first}"
	kill_all_hp_procs(hosts.first)
	log "Beginning test execution!"
	edi_test_set.run_tests
	# finished_monitor = Thread.new do
		counter = 0
		loop do
			if edi_test_set.finished?
				edi_test_set.display_test_status
				puts "\n============================================================"
				puts "#{Time.now} | Execution of test set " + edi_test_set.name + " completed in #{seconds_to_string(Time.now - start_time)}."
				puts "\n============================================================"
				return
			end
			edi_test_set.display_test_status if counter % 10 == 0
			counter += 1
			sleep 1
		end
rescue Interrupt
	plog "\n\nInterrupting gracefully...\n".blue
	plog "The application was interrupted while in:\n\t".yellow + "#{__FILE__} | #{__method__}".blue
	puts "Press enter to exit the application..."
	gets.chomp
	# puts "Test exectuion was interrupted! Starting pry debugging session...".yellow
	# puts "To exit the debugging session(which will also stop test execution), type 'exit'.".yellow
	# binding.pry
rescue => e
	plog report_error(e, "Error encountered in [#{__method__.to_s}]")
	puts "Press enter to exit the application..."
	gets.chomp
ensure
	edi_test_set.stop_tests unless (edi_test_set.nil? || edi_test_set.finished?)
	# finished_monitor.join(1) unless finished_monitor.nil?
end

def display_tests(tests)
	temp = []
	headers = ['Company', 'Test Set', 'Test Name', 'Automation Status', 'Run Date', 'Run Status', 'Subject', 'Test ID', 'Last Run ID']
	tests.each{|test| temp.push test.info}
	puts make_table(temp, headers)
end
